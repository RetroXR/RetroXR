#include "RommArchiveExtractor.hpp"

#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/stream_peer_gzip.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

#include <algorithm>
#include <array>
#include <atomic>
#include <cstdint>
#include <limits>
#include <string>
#include <unordered_set>
#include <utility>
#include <vector>

using namespace godot;

namespace Xenu
{
namespace
{
constexpr uint32_t LOCAL_FILE_SIGNATURE        = 0x04034b50u;
constexpr uint32_t CENTRAL_FILE_SIGNATURE      = 0x02014b50u;
constexpr uint32_t EOCD_SIGNATURE              = 0x06054b50u;
constexpr uint32_t ZIP64_EOCD_SIGNATURE        = 0x06064b50u;
constexpr uint32_t ZIP64_LOCATOR_SIGNATURE     = 0x07064b50u;
constexpr uint16_t ZIP64_EXTRA_ID              = 0x0001u;
constexpr uint16_t METHOD_STORED                = 0u;
constexpr uint16_t METHOD_DEFLATE               = 8u;
constexpr size_t   EOCD_MIN_SIZE                = 22u;
constexpr size_t   EOCD_MAX_SEARCH              = EOCD_MIN_SIZE + 0xffffu;
constexpr int32_t  STREAM_CHUNK_SIZE            = 256 * 1024;
constexpr uint64_t MAX_ARCHIVE_ENTRIES          = 65536u;
constexpr int64_t  MAX_PLAN_ENTRIES             = 65536;
constexpr char     CANCELLED_ERROR[]             = "Archive extraction cancelled";

struct CentralEntry
{
    String name;
    std::vector<uint8_t> raw_name;
    uint16_t flags = 0;
    uint16_t method = 0;
    uint32_t crc32 = 0;
    uint64_t compressed_size = 0;
    uint64_t uncompressed_size = 0;
    uint64_t local_header_offset = 0;
};

struct ArchiveIndex
{
    Ref<FileAccess> file;
    uint64_t file_size = 0;
    uint64_t central_offset = 0;
    uint64_t central_size = 0;
    std::vector<CentralEntry> entries;
};

struct PlannedEntry
{
    const CentralEntry* archive_entry = nullptr;
    String output_path;
    String relative_path;
};

uint16_t Read16(const uint8_t* p)
{
    return static_cast<uint16_t>(p[0]) |
        (static_cast<uint16_t>(p[1]) << 8);
}

uint32_t Read32(const uint8_t* p)
{
    return static_cast<uint32_t>(p[0]) |
        (static_cast<uint32_t>(p[1]) << 8) |
        (static_cast<uint32_t>(p[2]) << 16) |
        (static_cast<uint32_t>(p[3]) << 24);
}

uint64_t Read64(const uint8_t* p)
{
    return static_cast<uint64_t>(Read32(p)) |
        (static_cast<uint64_t>(Read32(p + 4)) << 32);
}

bool AddFits(uint64_t a, uint64_t b, uint64_t limit)
{
    return a <= limit && b <= limit - a;
}

bool ReadAt(const Ref<FileAccess>& file, uint64_t file_size, uint64_t offset,
            uint8_t* destination, uint64_t size)
{
    if (file.is_null() || !AddFits(offset, size, file_size))
        return false;
    file->seek(offset);
    return file->get_buffer(destination, size) == size;
}

bool ReadAt(const Ref<FileAccess>& file, uint64_t file_size, uint64_t offset,
            std::vector<uint8_t>& destination, uint64_t size)
{
    if (size > static_cast<uint64_t>(std::numeric_limits<size_t>::max()))
        return false;
    destination.resize(static_cast<size_t>(size));
    return size == 0 || ReadAt(file, file_size, offset, destination.data(), size);
}

Dictionary Result(bool ok, const String& error, const Array& files,
                  uint64_t total_size, bool cancelled = false)
{
    Dictionary result;
    result["ok"] = ok;
    result["cancelled"] = cancelled;
    result["error"] = error;
    result["files"] = files;
    result["total_size"] = static_cast<int64_t>(total_size);
    return result;
}

bool CancellationRequested(const std::atomic_bool& cancel_requested, String& error)
{
    if (!cancel_requested.load(std::memory_order_acquire))
        return false;
    error = CANCELLED_ERROR;
    return true;
}

bool ParseZip64Extra(const std::vector<uint8_t>& extra,
                     bool need_uncompressed, bool need_compressed,
                     bool need_offset, bool need_disk,
                     uint64_t& uncompressed, uint64_t& compressed,
                     uint64_t& offset, uint32_t& disk, String& error)
{
    size_t cursor = 0;
    while (cursor + 4 <= extra.size())
    {
        const uint16_t id = Read16(extra.data() + cursor);
        const uint16_t size = Read16(extra.data() + cursor + 2);
        cursor += 4;
        if (size > extra.size() - cursor)
        {
            error = "Malformed ZIP extra field";
            return false;
        }
        if (id != ZIP64_EXTRA_ID)
        {
            cursor += size;
            continue;
        }

        size_t field = cursor;
        const size_t end = cursor + size;
        auto read_u64 = [&](uint64_t& value) -> bool
        {
            if (end - field < 8)
                return false;
            value = Read64(extra.data() + field);
            field += 8;
            return true;
        };
        auto read_u32 = [&](uint32_t& value) -> bool
        {
            if (end - field < 4)
                return false;
            value = Read32(extra.data() + field);
            field += 4;
            return true;
        };

        if ((need_uncompressed && !read_u64(uncompressed)) ||
            (need_compressed && !read_u64(compressed)) ||
            (need_offset && !read_u64(offset)) ||
            (need_disk && !read_u32(disk)))
        {
            error = "Incomplete ZIP64 extra field";
            return false;
        }
        return true;
    }

    error = "ZIP64 metadata is missing";
    return false;
}

bool ParseArchive(const String& zip_path, ArchiveIndex& index, String& error)
{
    index.file = FileAccess::open(zip_path, FileAccess::READ);
    if (index.file.is_null())
    {
        error = "Could not open ZIP archive";
        return false;
    }
    index.file_size = index.file->get_length();
    if (index.file_size < EOCD_MIN_SIZE)
    {
        error = "ZIP archive is truncated";
        return false;
    }

    const uint64_t tail_size = std::min<uint64_t>(index.file_size, EOCD_MAX_SEARCH);
    const uint64_t tail_offset = index.file_size - tail_size;
    std::vector<uint8_t> tail;
    if (!ReadAt(index.file, index.file_size, tail_offset, tail, tail_size))
    {
        error = "Could not read ZIP directory footer";
        return false;
    }

    size_t eocd_in_tail = std::numeric_limits<size_t>::max();
    for (size_t pos = tail.size() - EOCD_MIN_SIZE + 1; pos-- > 0;)
    {
        if (Read32(tail.data() + pos) != EOCD_SIGNATURE)
            continue;
        const uint16_t comment_size = Read16(tail.data() + pos + 20);
        if (tail_offset + pos + EOCD_MIN_SIZE + comment_size == index.file_size)
        {
            eocd_in_tail = pos;
            break;
        }
    }
    if (eocd_in_tail == std::numeric_limits<size_t>::max())
    {
        error = "ZIP end-of-directory record was not found";
        return false;
    }

    const uint8_t* eocd = tail.data() + eocd_in_tail;
    const uint64_t eocd_offset = tail_offset + eocd_in_tail;
    uint32_t disk_number = Read16(eocd + 4);
    uint32_t central_disk = Read16(eocd + 6);
    uint64_t entries_on_disk = Read16(eocd + 8);
    uint64_t entry_count = Read16(eocd + 10);
    index.central_size = Read32(eocd + 12);
    index.central_offset = Read32(eocd + 16);

    const bool needs_zip64 = disk_number == 0xffffu || central_disk == 0xffffu ||
        entries_on_disk == 0xffffu || entry_count == 0xffffu ||
        index.central_size == 0xffffffffu || index.central_offset == 0xffffffffu;

    if (needs_zip64)
    {
        if (eocd_offset < 20)
        {
            error = "ZIP64 locator is missing";
            return false;
        }
        std::array<uint8_t, 20> locator{};
        if (!ReadAt(index.file, index.file_size, eocd_offset - locator.size(),
                    locator.data(), locator.size()) ||
            Read32(locator.data()) != ZIP64_LOCATOR_SIGNATURE)
        {
            error = "ZIP64 locator is missing";
            return false;
        }
        const uint32_t zip64_disk = Read32(locator.data() + 4);
        const uint64_t zip64_offset = Read64(locator.data() + 8);
        const uint32_t disk_count = Read32(locator.data() + 16);
        std::array<uint8_t, 56> record{};
        if (!ReadAt(index.file, index.file_size, zip64_offset,
                    record.data(), record.size()) ||
            Read32(record.data()) != ZIP64_EOCD_SIGNATURE ||
            Read64(record.data() + 4) < 44)
        {
            error = "ZIP64 directory record is invalid";
            return false;
        }

        disk_number = Read32(record.data() + 16);
        central_disk = Read32(record.data() + 20);
        entries_on_disk = Read64(record.data() + 24);
        entry_count = Read64(record.data() + 32);
        index.central_size = Read64(record.data() + 40);
        index.central_offset = Read64(record.data() + 48);
        if (zip64_disk != 0 || disk_count != 1)
        {
            error = "Split ZIP archives are not supported";
            return false;
        }
    }

    if (disk_number != 0 || central_disk != 0 || entries_on_disk != entry_count)
    {
        error = "Split ZIP archives are not supported";
        return false;
    }
    if (entry_count > MAX_ARCHIVE_ENTRIES ||
        entry_count > index.central_size / 46u ||
        entry_count > static_cast<uint64_t>(std::numeric_limits<size_t>::max()) ||
        !AddFits(index.central_offset, index.central_size, index.file_size) ||
        index.central_offset + index.central_size > eocd_offset)
    {
        error = "ZIP central directory is outside the archive";
        return false;
    }

    index.entries.clear();
    index.entries.reserve(static_cast<size_t>(entry_count));
    uint64_t cursor = index.central_offset;
    const uint64_t central_end = index.central_offset + index.central_size;
    for (uint64_t i = 0; i < entry_count; ++i)
    {
        std::array<uint8_t, 46> header{};
        if (!ReadAt(index.file, index.file_size, cursor, header.data(), header.size()) ||
            Read32(header.data()) != CENTRAL_FILE_SIGNATURE)
        {
            error = "ZIP central directory entry is invalid";
            return false;
        }

        const uint16_t name_size = Read16(header.data() + 28);
        const uint16_t extra_size = Read16(header.data() + 30);
        const uint16_t comment_size = Read16(header.data() + 32);
        const uint64_t record_size = header.size() + static_cast<uint64_t>(name_size) +
            extra_size + comment_size;
        if (!AddFits(cursor, record_size, central_end))
        {
            error = "ZIP central directory entry is truncated";
            return false;
        }

        CentralEntry entry;
        entry.flags = Read16(header.data() + 8);
        entry.method = Read16(header.data() + 10);
        entry.crc32 = Read32(header.data() + 16);
        entry.compressed_size = Read32(header.data() + 20);
        entry.uncompressed_size = Read32(header.data() + 24);
        entry.local_header_offset = Read32(header.data() + 42);

        if (!ReadAt(index.file, index.file_size, cursor + header.size(),
                    entry.raw_name, name_size))
        {
            error = "Could not read ZIP member name";
            return false;
        }
        entry.name = String::utf8(
            reinterpret_cast<const char*>(entry.raw_name.data()),
            static_cast<int64_t>(entry.raw_name.size()));

        std::vector<uint8_t> extra;
        if (!ReadAt(index.file, index.file_size,
                    cursor + header.size() + name_size, extra, extra_size))
        {
            error = "Could not read ZIP member metadata";
            return false;
        }

        const bool need_uncompressed = entry.uncompressed_size == 0xffffffffu;
        const bool need_compressed = entry.compressed_size == 0xffffffffu;
        const bool need_offset = entry.local_header_offset == 0xffffffffu;
        uint32_t entry_disk = Read16(header.data() + 34);
        const bool need_disk = entry_disk == 0xffffu;
        if (need_uncompressed || need_compressed || need_offset || need_disk)
        {
            if (!ParseZip64Extra(extra, need_uncompressed, need_compressed,
                                 need_offset, need_disk,
                                 entry.uncompressed_size, entry.compressed_size,
                                 entry.local_header_offset, entry_disk, error))
                return false;
        }
        if (entry_disk != 0)
        {
            error = "Split ZIP archives are not supported";
            return false;
        }

        index.entries.push_back(std::move(entry));
        cursor += record_size;
    }

    if (cursor > central_end)
    {
        error = "ZIP central directory is malformed";
        return false;
    }
    return true;
}

bool BuildPlan(const ArchiveIndex& index, const Array& requested,
               std::vector<PlannedEntry>& plan, Array& described,
               uint64_t& total_size, String& error)
{
    if (requested.is_empty())
    {
        error = "Extraction plan is empty";
        return false;
    }
    if (requested.size() > MAX_PLAN_ENTRIES)
    {
        error = "Extraction plan contains too many members";
        return false;
    }

    std::unordered_set<std::string> requested_names;
    std::unordered_set<std::string> output_paths;
    plan.clear();
    described.clear();
    total_size = 0;
    plan.reserve(static_cast<size_t>(requested.size()));

    for (int64_t i = 0; i < requested.size(); ++i)
    {
        const Variant value = requested[i];
        if (value.get_type() != Variant::DICTIONARY)
        {
            error = "Extraction plan contains a non-dictionary entry";
            return false;
        }
        const Dictionary item = value;
        if (!item.has("entry") || !item.has("path") || !item.has("relative"))
        {
            error = "Extraction plan entry is missing entry, path, or relative";
            return false;
        }

        const String entry_name = item["entry"];
        const String output_path = item["path"];
        const String relative_path = item["relative"];
        if (entry_name.is_empty() || output_path.is_empty() || relative_path.is_empty())
        {
            error = "Extraction plan contains an empty entry or path";
            return false;
        }

        const std::string entry_key(entry_name.utf8().get_data());
        const std::string output_key(output_path.utf8().get_data());
        if (!requested_names.insert(entry_key).second)
        {
            error = "Extraction plan contains duplicate ZIP member: " + entry_name;
            return false;
        }
        if (!output_paths.insert(output_key).second)
        {
            error = "Extraction plan contains duplicate output path: " + output_path;
            return false;
        }

        const CentralEntry* match = nullptr;
        for (const CentralEntry& candidate : index.entries)
        {
            if (candidate.name != entry_name)
                continue;
            if (match != nullptr)
            {
                error = "ZIP contains duplicate requested member: " + entry_name;
                return false;
            }
            match = &candidate;
        }
        if (match == nullptr)
        {
            error = "ZIP member was not found: " + entry_name;
            return false;
        }
        if ((match->flags & 0x0041u) != 0)
        {
            error = "Encrypted ZIP members are not supported: " + entry_name;
            return false;
        }
        if (match->method != METHOD_STORED && match->method != METHOD_DEFLATE)
        {
            error = "Unsupported ZIP compression method for: " + entry_name;
            return false;
        }
        if (match->uncompressed_size > static_cast<uint64_t>(std::numeric_limits<int64_t>::max()) ||
            total_size > static_cast<uint64_t>(std::numeric_limits<int64_t>::max()) -
                match->uncompressed_size)
        {
            error = "ZIP extraction size is too large";
            return false;
        }
        total_size += match->uncompressed_size;

        plan.push_back({ match, output_path, relative_path });
        Dictionary description;
        description["entry"] = entry_name;
        description["path"] = output_path;
        description["relative"] = relative_path;
        description["size"] = static_cast<int64_t>(match->uncompressed_size);
        described.append(description);
    }
    return true;
}

const std::array<uint32_t, 256>& CrcTable()
{
    static const std::array<uint32_t, 256> table = []
    {
        std::array<uint32_t, 256> values{};
        for (uint32_t i = 0; i < values.size(); ++i)
        {
            uint32_t value = i;
            for (int bit = 0; bit < 8; ++bit)
                value = (value & 1u) ? (value >> 1) ^ 0xedb88320u : value >> 1;
            values[i] = value;
        }
        return values;
    }();
    return table;
}

uint32_t UpdateCrc(uint32_t crc, const uint8_t* data, size_t size)
{
    const auto& table = CrcTable();
    for (size_t i = 0; i < size; ++i)
        crc = table[(crc ^ data[i]) & 0xffu] ^ (crc >> 8);
    return crc;
}

bool WriteChunk(const Ref<FileAccess>& output, const PackedByteArray& bytes,
                uint64_t expected_size, uint64_t& written, uint32_t& crc,
                String& error)
{
    if (bytes.is_empty())
        return true;
    if (written > expected_size || static_cast<uint64_t>(bytes.size()) > expected_size - written)
    {
        error = "ZIP member expanded beyond its declared size";
        return false;
    }
    if (!output->store_buffer(bytes))
    {
        error = "Could not write extracted ZIP member";
        return false;
    }
    crc = UpdateCrc(crc, bytes.ptr(), static_cast<size_t>(bytes.size()));
    written += static_cast<uint64_t>(bytes.size());
    return true;
}

bool DrainInflater(const Ref<StreamPeerGZIP>& inflater,
                   const Ref<FileAccess>& output, uint64_t expected_size,
                   uint64_t& written, uint32_t& crc, String& error,
                   const std::atomic_bool& cancel_requested)
{
    while (inflater->get_available_bytes() > 0)
    {
        if (CancellationRequested(cancel_requested, error))
            return false;
        const int32_t available = inflater->get_available_bytes();
        const Array received = inflater->get_partial_data(
            std::min<int32_t>(available, STREAM_CHUNK_SIZE));
        if (received.size() != 2 || static_cast<Error>(static_cast<int64_t>(received[0])) != OK)
        {
            error = "Could not read decompressed ZIP data";
            return false;
        }
        const PackedByteArray bytes = received[1];
        if (bytes.is_empty())
        {
            error = "ZIP decompressor made no progress";
            return false;
        }
        if (!WriteChunk(output, bytes, expected_size, written, crc, error))
            return false;
    }
    return true;
}

bool LocateMemberData(const ArchiveIndex& index, const CentralEntry& entry,
                      uint64_t& data_offset, String& error)
{
    std::array<uint8_t, 30> local{};
    if (!ReadAt(index.file, index.file_size, entry.local_header_offset,
                local.data(), local.size()) ||
        Read32(local.data()) != LOCAL_FILE_SIGNATURE)
    {
        error = "ZIP local header is invalid for: " + entry.name;
        return false;
    }
    const uint16_t local_flags = Read16(local.data() + 6);
    const uint16_t local_method = Read16(local.data() + 8);
    const uint16_t name_size = Read16(local.data() + 26);
    const uint16_t extra_size = Read16(local.data() + 28);
    if ((local_flags & 0x0041u) != 0 || local_method != entry.method)
    {
        error = "ZIP local header disagrees with its directory entry: " + entry.name;
        return false;
    }

    std::vector<uint8_t> local_name;
    if (!ReadAt(index.file, index.file_size,
                entry.local_header_offset + local.size(), local_name, name_size) ||
        local_name != entry.raw_name)
    {
        error = "ZIP local member name disagrees with its directory entry: " + entry.name;
        return false;
    }

    const uint64_t variable_size = static_cast<uint64_t>(name_size) + extra_size;
    if (!AddFits(entry.local_header_offset + local.size(), variable_size, index.file_size))
    {
        error = "ZIP local header is truncated for: " + entry.name;
        return false;
    }
    data_offset = entry.local_header_offset + local.size() + variable_size;
    if (!AddFits(data_offset, entry.compressed_size, index.file_size) ||
        data_offset + entry.compressed_size > index.central_offset)
    {
        error = "ZIP member data is outside the archive: " + entry.name;
        return false;
    }
    return true;
}

bool ExtractStored(const ArchiveIndex& index, const CentralEntry& entry,
                   uint64_t data_offset, const Ref<FileAccess>& output,
                   uint64_t& written, uint32_t& crc, String& error,
                   const std::atomic_bool& cancel_requested)
{
    if (entry.compressed_size != entry.uncompressed_size)
    {
        error = "Stored ZIP member has inconsistent sizes: " + entry.name;
        return false;
    }

    PackedByteArray chunk;
    chunk.resize(STREAM_CHUNK_SIZE);
    uint64_t remaining = entry.compressed_size;
    uint64_t cursor = data_offset;
    while (remaining > 0)
    {
        if (CancellationRequested(cancel_requested, error))
            return false;
        const int32_t amount = static_cast<int32_t>(
            std::min<uint64_t>(remaining, STREAM_CHUNK_SIZE));
        if (index.file->get_position() != cursor)
            index.file->seek(cursor);
        if (index.file->get_buffer(chunk.ptrw(), amount) != static_cast<uint64_t>(amount))
        {
            error = "Could not read stored ZIP member: " + entry.name;
            return false;
        }
        chunk.resize(amount);
        if (!WriteChunk(output, chunk, entry.uncompressed_size, written, crc, error))
            return false;
        chunk.resize(STREAM_CHUNK_SIZE);
        cursor += amount;
        remaining -= amount;
    }
    return true;
}

bool ExtractDeflated(const ArchiveIndex& index, const CentralEntry& entry,
                     uint64_t data_offset, const Ref<FileAccess>& output,
                     uint64_t& written, uint32_t& crc, String& error,
                     const std::atomic_bool& cancel_requested)
{
    Ref<StreamPeerGZIP> inflater;
    inflater.instantiate();
    // StreamPeerGZIP cannot select ZIP's raw DEFLATE mode (-15). Supply a
    // minimal gzip envelope around the exact compressed member bytes instead.
    if (inflater->start_decompression(false, STREAM_CHUNK_SIZE) != OK)
    {
        error = "Could not initialize ZIP decompressor";
        return false;
    }

    // ZIP and gzip use the same raw DEFLATE payload. A gzip envelope is useful
    // here because its trailer is the ZIP central directory's CRC32 and size,
    // both known before decompression starts. A zlib envelope would require an
    // Adler-32 that cannot be finalized until StreamPeerGZIP has emitted the
    // tail of the member.
    auto feed_all = [&](const PackedByteArray& input) -> bool
    {
        int32_t consumed = 0;
        while (consumed < input.size())
        {
            if (CancellationRequested(cancel_requested, error))
                return false;
            const uint64_t written_before = written;
            if (!DrainInflater(inflater, output, entry.uncompressed_size,
                               written, crc, error, cancel_requested))
                return false;

            const PackedByteArray pending = input.slice(consumed, input.size());
            const Array sent = inflater->put_partial_data(pending);
            if (sent.size() != 2 || static_cast<Error>(static_cast<int64_t>(sent[0])) != OK)
            {
                error = "Invalid deflate stream in ZIP member: " + entry.name;
                return false;
            }
            const int32_t just_consumed = static_cast<int32_t>(static_cast<int64_t>(sent[1]));
            if (just_consumed < 0 || just_consumed > input.size() - consumed)
            {
                error = "ZIP decompressor returned an invalid byte count";
                return false;
            }
            consumed += just_consumed;
            if (!DrainInflater(inflater, output, entry.uncompressed_size,
                               written, crc, error, cancel_requested))
                return false;
            if (just_consumed == 0 && written == written_before)
            {
                error = "ZIP decompressor made no progress for: " + entry.name;
                return false;
            }
        }
        return true;
    };

    PackedByteArray gzip_header;
    gzip_header.resize(10);
    gzip_header[0] = 0x1f;
    gzip_header[1] = 0x8b;
    gzip_header[2] = 8; // DEFLATE
    gzip_header[3] = 0; // no optional fields
    gzip_header[4] = gzip_header[5] = gzip_header[6] = gzip_header[7] = 0;
    gzip_header[8] = 0;
    gzip_header[9] = 255; // unknown OS
    if (!feed_all(gzip_header))
        return false;

    PackedByteArray compressed;
    compressed.resize(STREAM_CHUNK_SIZE);
    uint64_t remaining = entry.compressed_size;
    uint64_t cursor = data_offset;
    while (remaining > 0)
    {
        if (CancellationRequested(cancel_requested, error))
            return false;
        const int32_t amount = static_cast<int32_t>(
            std::min<uint64_t>(remaining, STREAM_CHUNK_SIZE));
        if (index.file->get_position() != cursor)
            index.file->seek(cursor);
        if (index.file->get_buffer(compressed.ptrw(), amount) != static_cast<uint64_t>(amount))
        {
            error = "Could not read compressed ZIP member: " + entry.name;
            return false;
        }
        compressed.resize(amount);

        if (!feed_all(compressed))
            return false;

        compressed.resize(STREAM_CHUNK_SIZE);
        cursor += amount;
        remaining -= amount;
    }

    if (!DrainInflater(inflater, output, entry.uncompressed_size,
                       written, crc, error, cancel_requested))
        return false;

    if (CancellationRequested(cancel_requested, error))
        return false;

    // Append the gzip CRC32 and ISIZE in little-endian order plus one byte that
    // is NOT part of the stream. At Z_STREAM_END, StreamPeerGZIP reports only
    // the eight trailer bytes consumed and leaves the sentinel behind. Consuming
    // all nine would mean the deflate stream never terminated; fewer than eight
    // means an incomplete trailer. The ring is empty here, so backpressure cannot
    // explain any other count.
    PackedByteArray trailer;
    trailer.resize(9);
    trailer[0] = static_cast<uint8_t>(entry.crc32);
    trailer[1] = static_cast<uint8_t>(entry.crc32 >> 8);
    trailer[2] = static_cast<uint8_t>(entry.crc32 >> 16);
    trailer[3] = static_cast<uint8_t>(entry.crc32 >> 24);
    const uint32_t isize = static_cast<uint32_t>(entry.uncompressed_size);
    trailer[4] = static_cast<uint8_t>(isize);
    trailer[5] = static_cast<uint8_t>(isize >> 8);
    trailer[6] = static_cast<uint8_t>(isize >> 16);
    trailer[7] = static_cast<uint8_t>(isize >> 24);
    trailer[8] = 0;
    const Array finished = inflater->put_partial_data(trailer);
    if (finished.size() != 2 ||
        static_cast<Error>(static_cast<int64_t>(finished[0])) != OK ||
        static_cast<int64_t>(finished[1]) != 8)
    {
        error = "Deflate stream did not terminate cleanly for: " + entry.name;
        return false;
    }
    return DrainInflater(inflater, output, entry.uncompressed_size,
                         written, crc, error, cancel_requested);
}

void Cleanup(const std::vector<String>& parts, const std::vector<String>& finals)
{
    for (const String& path : parts)
    {
        if (FileAccess::file_exists(path))
            DirAccess::remove_absolute(path);
    }
    for (const String& path : finals)
    {
        if (FileAccess::file_exists(path))
            DirAccess::remove_absolute(path);
    }
}
}

Dictionary RommArchiveExtractor::Inspect(const String& zip_path, const Array& requested)
{
    if (m_cancel_requested.load(std::memory_order_acquire))
        return Result(false, CANCELLED_ERROR, Array(), 0, true);

    ArchiveIndex index;
    String error;
    if (!ParseArchive(zip_path, index, error))
        return Result(false, error, Array(), 0);

    std::vector<PlannedEntry> plan;
    Array described;
    uint64_t total_size = 0;
    if (!BuildPlan(index, requested, plan, described, total_size, error))
        return Result(false, error, Array(), 0);
    if (m_cancel_requested.load(std::memory_order_acquire))
        return Result(false, CANCELLED_ERROR, Array(), total_size, true);
    return Result(true, String(), described, total_size);
}

Dictionary RommArchiveExtractor::Extract(const String& zip_path, const Array& requested)
{
    if (m_cancel_requested.load(std::memory_order_acquire))
        return Result(false, CANCELLED_ERROR, Array(), 0, true);

    ArchiveIndex index;
    String error;
    if (!ParseArchive(zip_path, index, error))
        return Result(false, error, Array(), 0);

    std::vector<PlannedEntry> plan;
    Array described;
    uint64_t total_size = 0;
    if (!BuildPlan(index, requested, plan, described, total_size, error))
        return Result(false, error, Array(), 0);

    std::vector<String> parts;
    std::vector<String> finals;
    parts.reserve(plan.size());
    finals.reserve(plan.size());

    // Refuse to overwrite anything that existed before this call. This is a
    // final guard below GDScript's collision preflight: cleanup may delete only
    // files this invocation itself created.
    for (const PlannedEntry& item : plan)
    {
        if (m_cancel_requested.load(std::memory_order_acquire))
            return Result(false, CANCELLED_ERROR, Array(), total_size, true);
        if (FileAccess::file_exists(item.output_path) ||
            DirAccess::dir_exists_absolute(item.output_path))
        {
            error = "Extraction target already exists: " + item.output_path;
            return Result(false, error, Array(), total_size);
        }
        const String part = item.output_path + String(".part");
        if (FileAccess::file_exists(part) && DirAccess::remove_absolute(part) != OK)
        {
            error = "Could not remove stale extraction part: " + part;
            return Result(false, error, Array(), total_size);
        }
        parts.push_back(part);
    }

    for (size_t i = 0; i < plan.size(); ++i)
    {
        if (m_cancel_requested.load(std::memory_order_acquire))
        {
            Cleanup(parts, finals);
            return Result(false, CANCELLED_ERROR, Array(), total_size, true);
        }
        const PlannedEntry& item = plan[i];
        const CentralEntry& entry = *item.archive_entry;
        const String& part = parts[i];
        if (DirAccess::make_dir_recursive_absolute(item.output_path.get_base_dir()) != OK)
        {
            error = "Could not create extraction directory for: " + item.output_path;
            Cleanup(parts, finals);
            return Result(false, error, Array(), total_size);
        }

        Ref<FileAccess> output = FileAccess::open(part, FileAccess::WRITE);
        if (output.is_null())
        {
            error = "Could not create extraction part: " + part;
            Cleanup(parts, finals);
            return Result(false, error, Array(), total_size);
        }

        uint64_t data_offset = 0;
        uint64_t written = 0;
        uint32_t crc = 0xffffffffu;
        bool ok = LocateMemberData(index, entry, data_offset, error);
        if (ok && entry.method == METHOD_STORED)
            ok = ExtractStored(index, entry, data_offset, output, written, crc, error,
                               m_cancel_requested);
        else if (ok)
            ok = ExtractDeflated(index, entry, data_offset, output, written, crc, error,
                                 m_cancel_requested);
        output->close();

        crc ^= 0xffffffffu;
        if (ok && written != entry.uncompressed_size)
        {
            error = "ZIP member ended before its declared size: " + entry.name;
            ok = false;
        }
        if (ok && crc != entry.crc32)
        {
            error = "CRC mismatch in ZIP member: " + entry.name;
            ok = false;
        }
        if (!ok)
        {
            Cleanup(parts, finals);
            return Result(false, error, Array(), total_size,
                          m_cancel_requested.load(std::memory_order_acquire));
        }
        if (m_cancel_requested.load(std::memory_order_acquire))
        {
            Cleanup(parts, finals);
            return Result(false, CANCELLED_ERROR, Array(), total_size, true);
        }
        if (FileAccess::file_exists(item.output_path) ||
            DirAccess::rename_absolute(part, item.output_path) != OK)
        {
            error = "Could not finalize extracted ZIP member: " + entry.name;
            Cleanup(parts, finals);
            return Result(false, error, Array(), total_size);
        }
        finals.push_back(item.output_path);
    }

    if (m_cancel_requested.load(std::memory_order_acquire))
    {
        Cleanup(parts, finals);
        return Result(false, CANCELLED_ERROR, Array(), total_size, true);
    }
    return Result(true, String(), described, total_size);
}

void RommArchiveExtractor::RequestCancel()
{
    m_cancel_requested.store(true, std::memory_order_release);
}

void RommArchiveExtractor::_bind_methods()
{
    ClassDB::bind_method(D_METHOD("inspect", "zip_path", "plan"),
                         &RommArchiveExtractor::Inspect);
    ClassDB::bind_method(D_METHOD("extract", "zip_path", "plan"),
                         &RommArchiveExtractor::Extract);
    ClassDB::bind_method(D_METHOD("request_cancel"),
                         &RommArchiveExtractor::RequestCancel);
}
}

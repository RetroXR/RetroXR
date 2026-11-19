#pragma once

#include <atomic>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

namespace Xenu
{
/// Bounded-memory ZIP extraction for RomM's multi-file disc archives.
///
/// GDScript owns path policy: it enumerates the archive with ZIPReader, rejects
/// unsafe relative names, and passes only the members it intends to extract as
/// dictionaries containing { entry, path, relative }. This class independently
/// parses the central directory (including ZIP64), matches that plan exactly,
/// and either inspects it or streams it to disk without ever materializing a
/// complete member in memory.
class RommArchiveExtractor : public godot::RefCounted
{
    GDCLASS(RommArchiveExtractor, godot::RefCounted);

public:
    /// Validate and size a preflight plan without writing anything.
    /// Returns { ok, error, files: [{entry,path,relative,size}], total_size }.
    godot::Dictionary Inspect(const godot::String& zip_path, const godot::Array& plan);

    /// Stream the selected plan to per-member .part files, validate size + CRC,
    /// then rename each completed member into place. On any failure, every part
    /// and final file created by this call is removed.
    /// Returns { ok, cancelled, error, files, total_size }.
    godot::Dictionary Extract(const godot::String& zip_path, const godot::Array& plan);

    /// May be called from the main thread while Extract runs on a worker. The
    /// current operation stops at the next streaming chunk and removes all
    /// output it created.
    void RequestCancel();

protected:
    static void _bind_methods();

private:
    std::atomic_bool m_cancel_requested{false};
};
}

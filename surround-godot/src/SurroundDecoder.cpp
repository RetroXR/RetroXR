#include "SurroundDecoder.hpp"

#include "FreeSurround/ChannelMaps.h"
#include "FreeSurround/FreeSurroundDecoder.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cstring>

using namespace godot;

namespace Xenu
{

namespace
{

/// Our channel order expressed in FreeSurround's own identifiers, so the map
/// below is a lookup rather than an assumption about bit ordering.
constexpr channel_id k_wanted[SurroundDecoder::CH_COUNT] = {
    ci_front_left, ci_front_right, ci_front_center, ci_lfe, ci_back_left, ci_back_right,
};

bool IsPowerOfTwo(int v)
{
    return v > 0 && (v & (v - 1)) == 0;
}

} // namespace

SurroundDecoder::SurroundDecoder() = default;
SurroundDecoder::~SurroundDecoder() = default;

bool SurroundDecoder::Configure(int block_frames, int sample_rate)
{
    if (!IsPowerOfTwo(block_frames) || block_frames < 64 || block_frames > 16384)
    {
        UtilityFunctions::push_error("SurroundDecoder: block_frames must be a power of two in 64..16384, got ",
                                     block_frames);
        return false;
    }
    if (sample_rate < 8000 || sample_rate > 192000)
    {
        UtilityFunctions::push_error("SurroundDecoder: implausible sample_rate ", sample_rate);
        return false;
    }

    m_fs.reset();
    m_block = block_frames;
    m_rate = sample_rate;
    m_pending.clear();

    // Init must follow construction with nothing in between: ~DPL2FSDecoder
    // frees its kiss_fftr configs unconditionally, so an un-Init'd instance
    // frees uninitialised pointers.
    auto fs = std::make_unique<DPL2FSDecoder>();
    fs->Init(cs_5point1, static_cast<unsigned int>(block_frames), static_cast<unsigned int>(sample_rate));
    m_fs = std::move(fs);

    if (!BuildChannelMap())
    {
        m_fs.reset();
        return false;
    }

    for (auto &ch : m_out)
        ch.resize(0);

    return true;
}

bool SurroundDecoder::BuildChannelMap()
{
    const auto it = chn_id.find(static_cast<unsigned>(cs_5point1));
    if (it == chn_id.end())
    {
        UtilityFunctions::push_error("SurroundDecoder: FreeSurround has no channel table for cs_5point1");
        return false;
    }
    const std::vector<channel_id> &order = it->second;
    m_src_stride = static_cast<int>(order.size());

    for (int c = 0; c < CH_COUNT; ++c)
    {
        const auto found = std::find(order.begin(), order.end(), k_wanted[c]);
        if (found == order.end())
        {
            UtilityFunctions::push_error("SurroundDecoder: cs_5point1 is missing channel ", c);
            return false;
        }
        m_src_index[c] = static_cast<int>(found - order.begin());
    }
    return true;
}

Array SurroundDecoder::Decode(const PackedVector2Array &frames)
{
    if (m_fs == nullptr)
        return PackOutput(0);

    const int64_t n = frames.size();
    if (n > 0)
    {
        const size_t base = m_pending.size();
        m_pending.resize(base + static_cast<size_t>(n) * 2);
        // Vector2 is two floats, so an interleaved stereo run copies whole.
        std::memcpy(m_pending.data() + base, frames.ptr(), static_cast<size_t>(n) * sizeof(Vector2));
    }

    const int stride = m_block * 2;
    const int blocks = static_cast<int>(m_pending.size()) / stride;
    if (blocks == 0)
        return PackOutput(0);

    for (auto &ch : m_out)
        ch.resize(blocks * m_block);

    float *dst[CH_COUNT];
    for (int c = 0; c < CH_COUNT; ++c)
        dst[c] = m_out[c].ptrw();

    int produced = 0;
    for (int b = 0; b < blocks; ++b)
    {
        // decode() hands back an internal buffer that the next call overwrites.
        const float *src = m_fs->decode(m_pending.data() + static_cast<size_t>(b) * stride);
        if (src == nullptr)
            break;
        for (int c = 0; c < CH_COUNT; ++c)
        {
            const int si = m_src_index[c];
            float *d = dst[c] + produced;
            for (int k = 0; k < m_block; ++k)
                d[k] = src[k * m_src_stride + si];
        }
        produced += m_block;
    }

    m_pending.erase(m_pending.begin(), m_pending.begin() + static_cast<size_t>(blocks) * stride);
    return PackOutput(produced);
}

/// Input is assumed to be in WAVE order (FL, FR, FC, LFE, BL, BR), which is what
/// libVLC hands over and is already our own order.
Array SurroundDecoder::Deinterleave(const PackedFloat32Array &frames, int channels)
{
    if (channels < 1 || channels > CH_COUNT)
    {
        UtilityFunctions::push_error("SurroundDecoder: deinterleave wants 1..6 channels, got ", channels);
        return PackOutput(0);
    }

    const int produced = static_cast<int>(frames.size() / channels);
    for (auto &ch : m_out)
        ch.resize(produced);
    if (produced == 0)
        return PackOutput(0);

    const float *src = frames.ptr();
    for (int c = 0; c < CH_COUNT; ++c)
    {
        float *d = m_out[c].ptrw();
        if (c >= channels)
        {
            std::memset(d, 0, static_cast<size_t>(produced) * sizeof(float));
            continue;
        }
        for (int k = 0; k < produced; ++k)
            d[k] = src[k * channels + c];
    }
    return PackOutput(produced);
}

Array SurroundDecoder::PackOutput(int frames)
{
    if (frames <= 0)
        for (auto &ch : m_out)
            ch.resize(0);

    Array out;
    out.resize(CH_COUNT);
    for (int c = 0; c < CH_COUNT; ++c)
        out[c] = m_out[c];
    return out;
}

void SurroundDecoder::Flush()
{
    m_pending.clear();
    if (m_fs != nullptr)
        m_fs->flush();
}

void SurroundDecoder::SetCircularWrap(float v)
{
    if (m_fs)
        m_fs->set_circular_wrap(v);
}
void SurroundDecoder::SetShift(float v)
{
    if (m_fs)
        m_fs->set_shift(v);
}
void SurroundDecoder::SetDepth(float v)
{
    if (m_fs)
        m_fs->set_depth(v);
}
void SurroundDecoder::SetFocus(float v)
{
    if (m_fs)
        m_fs->set_focus(v);
}
void SurroundDecoder::SetCenterImage(float v)
{
    if (m_fs)
        m_fs->set_center_image(v);
}
void SurroundDecoder::SetFrontSeparation(float v)
{
    if (m_fs)
        m_fs->set_front_separation(v);
}
void SurroundDecoder::SetRearSeparation(float v)
{
    if (m_fs)
        m_fs->set_rear_separation(v);
}
void SurroundDecoder::SetLowCutoff(float v)
{
    if (m_fs)
        m_fs->set_low_cutoff(v);
}
void SurroundDecoder::SetHighCutoff(float v)
{
    if (m_fs)
        m_fs->set_high_cutoff(v);
}
void SurroundDecoder::SetBassRedirection(bool v)
{
    if (m_fs)
        m_fs->set_bass_redirection(v);
}

void SurroundDecoder::_bind_methods()
{
    ClassDB::bind_method(D_METHOD("configure", "block_frames", "sample_rate"), &SurroundDecoder::Configure,
                         DEFVAL(1024), DEFVAL(48000));
    ClassDB::bind_method(D_METHOD("is_configured"), &SurroundDecoder::IsConfigured);
    ClassDB::bind_method(D_METHOD("block_frames"), &SurroundDecoder::BlockFrames);
    ClassDB::bind_method(D_METHOD("latency_frames"), &SurroundDecoder::LatencyFrames);
    ClassDB::bind_method(D_METHOD("decode", "frames"), &SurroundDecoder::Decode);
    ClassDB::bind_method(D_METHOD("deinterleave", "frames", "channels"), &SurroundDecoder::Deinterleave);
    ClassDB::bind_method(D_METHOD("flush"), &SurroundDecoder::Flush);

    ClassDB::bind_method(D_METHOD("set_circular_wrap", "degrees"), &SurroundDecoder::SetCircularWrap);
    ClassDB::bind_method(D_METHOD("set_shift", "v"), &SurroundDecoder::SetShift);
    ClassDB::bind_method(D_METHOD("set_depth", "v"), &SurroundDecoder::SetDepth);
    ClassDB::bind_method(D_METHOD("set_focus", "v"), &SurroundDecoder::SetFocus);
    ClassDB::bind_method(D_METHOD("set_center_image", "v"), &SurroundDecoder::SetCenterImage);
    ClassDB::bind_method(D_METHOD("set_front_separation", "v"), &SurroundDecoder::SetFrontSeparation);
    ClassDB::bind_method(D_METHOD("set_rear_separation", "v"), &SurroundDecoder::SetRearSeparation);
    ClassDB::bind_method(D_METHOD("set_low_cutoff", "v"), &SurroundDecoder::SetLowCutoff);
    ClassDB::bind_method(D_METHOD("set_high_cutoff", "v"), &SurroundDecoder::SetHighCutoff);
    ClassDB::bind_method(D_METHOD("set_bass_redirection", "enabled"), &SurroundDecoder::SetBassRedirection);

    BIND_ENUM_CONSTANT(CH_FL);
    BIND_ENUM_CONSTANT(CH_FR);
    BIND_ENUM_CONSTANT(CH_C);
    BIND_ENUM_CONSTANT(CH_LFE);
    BIND_ENUM_CONSTANT(CH_SL);
    BIND_ENUM_CONSTANT(CH_SR);
    BIND_ENUM_CONSTANT(CH_COUNT);
}

} // namespace Xenu

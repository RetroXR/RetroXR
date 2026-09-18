#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include <memory>
#include <vector>

class DPL2FSDecoder;

namespace Xenu
{

/// Dolby Surround / Pro Logic II matrix decoder: interleaved stereo in, six mono
/// channels out.
///
/// One instance per source. The underlying STFT carries state, so two machines
/// sharing a decoder would interleave their spectra.
class SurroundDecoder : public godot::RefCounted
{
    GDCLASS(SurroundDecoder, godot::RefCounted)

public:
    /// Output channel order, which is NOT the order FreeSurround emits.
    enum Channel
    {
        CH_FL = 0,
        CH_FR,
        CH_C,
        CH_LFE,
        CH_SL,
        CH_SR,
        CH_COUNT
    };

    /// Both defined out of line: unique_ptr needs DPL2FSDecoder complete to
    /// destroy it, and the constructor instantiates that destructor too.
    SurroundDecoder();
    ~SurroundDecoder() override;

    /// Allocate the decoder. `block_frames` must be a power of two; the
    /// upstream header asks for 5-20 ms of single-channel samples, and the
    /// decoder's own delay is block_frames/2.
    ///
    /// Calling this again rebuilds from scratch: DPL2FSDecoder::Init is guarded
    /// by an `initialized` flag and silently ignores a second call.
    bool Configure(int block_frames, int sample_rate);

    bool IsConfigured() const { return m_fs != nullptr; }
    int BlockFrames() const { return m_block; }

    /// Frames of delay the decoder adds. Callers that mix a second stream
    /// against this one have to match it.
    int LatencyFrames() const { return m_block / 2; }

    /// Push interleaved stereo and take whatever complete blocks fall out.
    /// Returns CH_COUNT PackedFloat32Arrays, all the same length, empty until
    /// a whole block has accumulated.
    godot::Array Decode(const godot::PackedVector2Array &frames);

    /// Split already-discrete interleaved audio into the same output shape, for
    /// media that carries real 5.1. No FFT, no delay.
    godot::Array Deinterleave(const godot::PackedFloat32Array &frames, int channels);

    /// Drop buffered audio, so a source that stops and restarts does not replay
    /// a stale tail.
    void Flush();

    void SetCircularWrap(float v);
    void SetShift(float v);
    void SetDepth(float v);
    void SetFocus(float v);
    void SetCenterImage(float v);
    void SetFrontSeparation(float v);
    void SetRearSeparation(float v);
    void SetLowCutoff(float v);
    void SetHighCutoff(float v);
    void SetBassRedirection(bool v);

protected:
    static void _bind_methods();

private:
    /// Where each of our channels sits in FreeSurround's interleaved output,
    /// read from its own chn_id table rather than assumed.
    bool BuildChannelMap();

    /// Hand `m_out` back as an Array of CH_COUNT arrays.
    godot::Array PackOutput(int frames);

    std::unique_ptr<DPL2FSDecoder> m_fs;
    int m_block = 0;
    int m_rate = 0;

    int m_src_index[CH_COUNT] = {};
    int m_src_stride = CH_COUNT;

    /// Interleaved stereo not yet consumed by a whole block.
    std::vector<float> m_pending;

    godot::PackedFloat32Array m_out[CH_COUNT];
};

} // namespace Xenu

VARIANT_ENUM_CAST(Xenu::SurroundDecoder::Channel);

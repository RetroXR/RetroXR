#pragma once

// SurroundOutput - the six decoded channels sent to the output device's own
// speakers rather than rendered binaurally.
//
// Godot's players cannot address a speaker pair by itself: MIX_TARGET_STEREO
// is the front pair, SURROUND is every pair at once, and CENTER is the centre
// and LFE together. What CAN write a pair on its own is a bus effect, because
// the AudioServer runs a separate effect instance for every speaker pair of a
// bus. So the sink is a bus of its own, "SurroundOut", sending to Master, with
// one SurroundOutputEffect on it: the instance for pair 0 pulls one block from
// every live source into eight planes, and each instance writes its own pair
// from them.
//
// A bus only sends a pair while that pair is ACTIVE, and only a playback mixing
// into it makes it so - an effect that processes silence still has its output
// dropped. So the bus also carries a player of an AudioStreamGenerator that is
// never fed, whose only job is to keep every pair awake. It is a built-in
// stream on purpose: a playback of one of this extension's classes would be
// released through freed class records at exit, the fault MetaXRAudioMixer
// documents.

#include "DiscreteRing.hpp"

#include <godot_cpp/classes/audio_effect.hpp>
#include <godot_cpp/classes/audio_effect_instance.hpp>
#include <godot_cpp/classes/audio_frame.hpp>
#include <godot_cpp/classes/audio_stream_generator.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include <atomic>
#include <memory>
#include <mutex>
#include <vector>

namespace Xenu
{

/// Every source currently sending to the device, and the bus they reach it by.
/// Process-wide: a machine has one set of real speakers.
class DiscreteSink
{
public:
    static DiscreteSink& Get();

    void Register(const std::shared_ptr<DiscreteRing>& ring);
    void Unregister(const std::shared_ptr<DiscreteRing>& ring);

    /// Audio thread, from the pair-0 instance: one block from every source into
    /// the eight planes.
    void Pull(uint32_t frames);
    /// Audio thread: pair `pair` of the block Pull last made, added to `dst`.
    void Write(int pair, godot::AudioFrame* dst, uint32_t frames) const;

    /// Main thread. Makes the bus, its effect and its keep-awake player the
    /// first time a source asks. False when there is no AudioServer.
    bool EnsureBus();
    /// Main thread. The bus holds this extension's effect, which has to be gone
    /// before the extension's class records are.
    void Teardown();

    int BusIndex() const;
    static constexpr const char* kBusName = "SurroundOut";

private:
    mutable std::mutex m_mutex;
    std::vector<std::shared_ptr<DiscreteRing>> m_rings;
    std::vector<float> m_planes[DiscreteRing::kOutputs];
    uint32_t m_planes_frames = 0;
    bool m_bus_made = false;
    uint64_t m_player_id = 0;
    /// The keep-awake player's stream, held here as well as by the player. A
    /// generator's playback points at its generator RAW, and the tree frees the
    /// player at quit while the audio thread is still fading that playback out:
    /// freed with the player, the generator was read after free on the audio
    /// thread, where Godot has no crash handler -- one exit in six died silently.
    godot::Ref<godot::AudioStreamGenerator> m_quiet;
};

/// One source's handle on the device. Created through SurroundAudio's
/// create_output(), so a caller that cannot name this class can still hold it.
class SurroundOutput : public godot::RefCounted
{
    GDCLASS(SurroundOutput, godot::RefCounted)

public:
    SurroundOutput();
    ~SurroundOutput() override;

    /// Six PackedFloat32Array of equal length, the decoder's own output. Returns
    /// the frames taken.
    int Push(const godot::Array& planes);
    int PushSilence(int frames);
    int Queued() const;
    void Flush();
    /// 48 gains, input major: `gains[in * 8 + out]`. See DiscreteRing.
    void SetMatrix(const godot::PackedFloat32Array& gains);
    float GetGain(int in, int out) const;

protected:
    static void _bind_methods();

private:
    std::shared_ptr<DiscreteRing> m_ring;
    godot::PackedFloat32Array m_planes[DiscreteRing::kInputs];
};

class SurroundOutputInstance : public godot::AudioEffectInstance
{
    GDCLASS(SurroundOutputInstance, godot::AudioEffectInstance)

public:
    void _process(const void* p_src_buffer, godot::AudioFrame* p_dst_buffer, int32_t p_frame_count) override;
    /// Always: pair 0 is what drains the rings, and it must run whether or not
    /// the AudioServer thinks the bus has anything on it.
    bool _process_silence() const override { return true; }

    /// Which speaker pair of the bus this instance writes, looked up the first
    /// time it is asked. -1 when it is not on the bus.
    int GetPair();

protected:
    static void _bind_methods();

private:
    /// Found, never counted. The AudioServer remakes every instance whenever the
    /// bus's pair count changes, and the count the device reports can already be
    /// the new one while the bus is still being built at the old one -- numbering
    /// instances in the order they were made rotated every pair by one on a 5.1
    /// device, FL and FR playing out of the surrounds. Written from the audio
    /// thread and the main one, always with the same answer.
    std::atomic<int> m_pair{-1};
};

class SurroundOutputEffect : public godot::AudioEffect
{
    GDCLASS(SurroundOutputEffect, godot::AudioEffect)

public:
    godot::Ref<godot::AudioEffectInstance> _instantiate() override;

protected:
    static void _bind_methods() {}
};

} // namespace Xenu

#pragma once

// DiscreteRing - one source's six decoded channels on their way to the output
// device's own speakers, with no Godot in it so the C++ tests can drive it.
//
// The six normally leave as Meta XR Audio voices, and that mixer renders
// binaural stereo only: on a PC wired for 5.1, surround played as HRTF out of
// the front pair while the centre and the surrounds stood silent. This is the
// other road - the channels go to the device's channels, and the room's
// speakers do the placing.

#include <array>
#include <atomic>
#include <cstdint>
#include <vector>

namespace Xenu
{

class DiscreteRing
{
public:
    /// FL, FR, C, LFE, SL, SR in - the decoder's own order.
    static constexpr int kInputs = 6;
    /// The device's FL, FR, C, LFE, back L, back R, side L, side R out, which is
    /// Godot's own speaker-pair order: pair k of a bus is outputs 2k and 2k+1.
    static constexpr int kOutputs = 8;
    static constexpr int kGains = kInputs * kOutputs;
    /// A power of two, the depth a Meta XR voice's ring has.
    static constexpr uint32_t kFrames = 32768;

    DiscreteRing() : m_ring(static_cast<size_t>(kFrames) * kInputs, 0.0f)
    {
        for (auto& g : m_target)
            g.store(0.0f, std::memory_order_relaxed);
        m_applied.fill(0.0f);
    }

    uint32_t Queued() const
    {
        return m_write.load(std::memory_order_acquire) - m_read.load(std::memory_order_acquire);
    }

    /// Producer. Six planes of `frames` samples each. What does not fit is
    /// dropped, and the count taken is returned.
    uint32_t Push(const float* const planes[kInputs], uint32_t frames)
    {
        const uint32_t w = m_write.load(std::memory_order_relaxed);
        const uint32_t room = kFrames - (w - m_read.load(std::memory_order_acquire));
        const uint32_t take = frames < room ? frames : room;
        for (uint32_t f = 0; f < take; ++f)
        {
            float* slot = &m_ring[static_cast<size_t>((w + f) & (kFrames - 1)) * kInputs];
            for (int ch = 0; ch < kInputs; ++ch)
                slot[ch] = planes[ch] ? planes[ch][f] : 0.0f;
        }
        m_write.store(w + take, std::memory_order_release);
        return take;
    }

    /// Producer. Silence, to stand the ring at the depth the voices it runs
    /// beside already have - a queue is a delay, so the two play in step only
    /// if they start equally deep.
    uint32_t PushSilence(uint32_t frames)
    {
        const uint32_t w = m_write.load(std::memory_order_relaxed);
        const uint32_t room = kFrames - (w - m_read.load(std::memory_order_acquire));
        const uint32_t take = frames < room ? frames : room;
        for (uint32_t f = 0; f < take; ++f)
        {
            float* slot = &m_ring[static_cast<size_t>((w + f) & (kFrames - 1)) * kInputs];
            for (int ch = 0; ch < kInputs; ++ch)
                slot[ch] = 0.0f;
        }
        m_write.store(w + take, std::memory_order_release);
        return take;
    }

    /// Any thread. Honoured by the consumer on its next pull, since only it may
    /// move the read position.
    void RequestFlush() { m_flush.store(true, std::memory_order_release); }

    /// Any thread. `gains[in * kOutputs + out]`. Reached gradually: the consumer
    /// ramps from what it last applied across one pull, so a volume key or a
    /// speaker plugged in mid-game does not click.
    void SetMatrix(const float* gains)
    {
        for (int i = 0; i < kGains; ++i)
            m_target[i].store(gains[i], std::memory_order_relaxed);
    }

    float TargetGain(int in, int out) const
    {
        return m_target[in * kOutputs + out].load(std::memory_order_relaxed);
    }

    /// Consumer. Routes `frames` frames through the matrix and ADDS them to
    /// `outs`, so several sources can share one device. Returns how many came
    /// from the ring; the rest of the block is silence, never a stall.
    uint32_t MixInto(float* const outs[kOutputs], uint32_t frames)
    {
        if (m_flush.exchange(false, std::memory_order_acq_rel))
            m_read.store(m_write.load(std::memory_order_acquire), std::memory_order_release);

        std::array<float, kGains> target;
        for (int i = 0; i < kGains; ++i)
            target[i] = m_target[i].load(std::memory_order_relaxed);

        const uint32_t r = m_read.load(std::memory_order_relaxed);
        const uint32_t avail = m_write.load(std::memory_order_acquire) - r;
        const uint32_t take = frames < avail ? frames : avail;
        const float inv = frames > 0 ? 1.0f / static_cast<float>(frames) : 0.0f;

        for (int in = 0; in < kInputs; ++in)
        {
            for (int out = 0; out < kOutputs; ++out)
            {
                const int k = in * kOutputs + out;
                const float from = m_applied[k];
                const float to = target[k];
                if (from == 0.0f && to == 0.0f)
                    continue;
                float* dst = outs[out];
                if (dst == nullptr)
                    continue;
                const float step = (to - from) * inv;
                for (uint32_t f = 0; f < take; ++f)
                {
                    const float g = from + step * static_cast<float>(f + 1);
                    dst[f] += m_ring[static_cast<size_t>((r + f) & (kFrames - 1)) * kInputs + in] * g;
                }
            }
        }
        m_applied = target;
        m_read.store(r + take, std::memory_order_release);
        return take;
    }

private:
    std::vector<float> m_ring;          ///< interleaved, kInputs a frame
    std::atomic<uint32_t> m_write{0};
    std::atomic<uint32_t> m_read{0};
    std::atomic<bool> m_flush{false};
    std::array<std::atomic<float>, kGains> m_target;
    std::array<float, kGains> m_applied;   ///< consumer only
};

} // namespace Xenu

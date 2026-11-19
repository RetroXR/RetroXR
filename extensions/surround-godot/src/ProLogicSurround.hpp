#pragma once

// ProLogicSurround - the surround half of a first-generation Dolby Pro Logic
// decoder, applied to the two rear channels FreeSurround produces. No Godot in
// it, so the C++ tests can drive it.
//
// FreeSurround is a Pro Logic II decoder, and the difference that matters to a
// listener is the surround. Pro Logic II gives a stereo pair of full-range
// surrounds; the original Dolby Surround / Pro Logic decoder had ONE surround
// channel, played identically from both rear speakers, band-limited to
// 100 Hz - 7 kHz and delayed about 20 ms so that the precedence effect keeps
// dialogue leaking into it pinned to the front. Dolphin's trimmed copy of
// FreeSurround has only its 5.1 and 7.1 layouts - no four-channel one - so the
// older decoder is the 5.1 decode with its rears put through this:
//
//   mono = (SL - SR) / 2  ->  100 Hz high-pass  ->  7 kHz low-pass  ->  20 ms
//
// and the result written back to both.
//
// The DIFFERENCE, which is what the old decoder took too (S = Lt - Rt), and the
// sum is the trap. FreeSurround gives every left-hand output Lt's phase and every
// right-hand one Rt's, and a Dolby Surround rear is encoded +90 degrees in Lt and
// -90 in Rt - so a sound behind the listener decodes as SL and SR in ANTI-phase.
// Their sum cancelled it to -55 dB; half the difference keeps its level, and a
// sound in one rear alone comes out of both 6 dB down.
//
// Frames in equal frames out, always. The delay is a line inside the channel,
// not a change in how much is queued, so the six voices stay level.

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <vector>

namespace Xenu
{

class ProLogicSurround
{
public:
    /// The surround channel's passband and delay, from the Dolby Surround
    /// decoder specification.
    static constexpr double kHighPassHz = 100.0;
    static constexpr double kLowPassHz = 7000.0;
    static constexpr double kDelaySeconds = 0.020;

    /// Size the delay line and design both filters for `sample_rate`. Clears
    /// every bit of state, so it is also how a source starts afresh.
    void Configure(int sample_rate)
    {
        m_rate = sample_rate > 0 ? sample_rate : 48000;
        m_delay.assign(DelayFrames(), 0.0f);
        m_pos = 0;
        m_hp = Biquad::HighPass(kHighPassHz, m_rate);
        m_lp = Biquad::LowPass(kLowPassHz, m_rate);
    }

    /// Drop the delay line's contents and the filters' memory, so a source that
    /// stops and restarts does not open on a stale 20 ms of its last surround.
    void Reset()
    {
        std::fill(m_delay.begin(), m_delay.end(), 0.0f);
        m_pos = 0;
        m_hp.Clear();
        m_lp.Clear();
    }

    size_t DelayFrames() const
    {
        return static_cast<size_t>(std::lround(kDelaySeconds * static_cast<double>(m_rate)));
    }

    /// Replace `sl` and `sr` in place with the one band-limited, delayed
    /// surround, `frames` samples each.
    void Process(float* sl, float* sr, size_t frames)
    {
        if (m_delay.empty())
            Configure(m_rate);
        const size_t len = m_delay.size();
        for (size_t k = 0; k < frames; ++k)
        {
            const double mono = 0.5 * (static_cast<double>(sl[k]) - static_cast<double>(sr[k]));
            const float filtered = static_cast<float>(m_lp.Run(m_hp.Run(mono)));
            const float out = m_delay[m_pos];
            m_delay[m_pos] = filtered;
            m_pos = m_pos + 1 == len ? 0 : m_pos + 1;
            sl[k] = out;
            sr[k] = out;
        }
    }

private:
    /// A second-order Butterworth section (Q = 1/sqrt 2), RBJ cookbook form,
    /// transposed direct form II. Double state: a 100 Hz pole at 48 kHz sits
    /// close enough to the unit circle that float state drifts.
    struct Biquad
    {
        double b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0;
        double z1 = 0.0, z2 = 0.0;

        static Biquad LowPass(double hz, int rate)
        {
            const double w = 2.0 * kPi * hz / static_cast<double>(rate);
            const double c = std::cos(w);
            const double alpha = std::sin(w) / (2.0 * kQ);
            const double a0 = 1.0 + alpha;
            Biquad q;
            q.b0 = (1.0 - c) * 0.5 / a0;
            q.b1 = (1.0 - c) / a0;
            q.b2 = q.b0;
            q.a1 = -2.0 * c / a0;
            q.a2 = (1.0 - alpha) / a0;
            return q;
        }

        static Biquad HighPass(double hz, int rate)
        {
            const double w = 2.0 * kPi * hz / static_cast<double>(rate);
            const double c = std::cos(w);
            const double alpha = std::sin(w) / (2.0 * kQ);
            const double a0 = 1.0 + alpha;
            Biquad q;
            q.b0 = (1.0 + c) * 0.5 / a0;
            q.b1 = -(1.0 + c) / a0;
            q.b2 = q.b0;
            q.a1 = -2.0 * c / a0;
            q.a2 = (1.0 - alpha) / a0;
            return q;
        }

        double Run(double x)
        {
            const double y = b0 * x + z1;
            z1 = b1 * x - a1 * y + z2;
            z2 = b2 * x - a2 * y;
            return y;
        }

        void Clear() { z1 = z2 = 0.0; }
    };

    static constexpr double kPi = 3.14159265358979323846;
    static constexpr double kQ = 0.70710678118654752;

    int m_rate = 48000;
    std::vector<float> m_delay;
    size_t m_pos = 0;
    Biquad m_hp;
    Biquad m_lp;
};

} // namespace Xenu

// Standalone harness for the Dolby Surround (first-generation Pro Logic) surround
// stage. Build and run with tests/run_tests.py. Needs no Godot.
//
// What has to be true of the older decoder's surround, and what would be
// silently wrong without a check: ONE channel played from both rears, 100 Hz to
// 7 kHz, 20 ms late - and not one frame gained or lost, because the six voices
// are kept level by counting frames.

#include <cmath>
#include <cstdio>
#include <vector>

#include "FreeSurround/ChannelMaps.h"
#include "FreeSurround/FreeSurroundDecoder.h"
#include "ProLogicSurround.hpp"

using Xenu::ProLogicSurround;

static int g_failures = 0;

static void Check(bool ok, const char* what)
{
    std::printf("  %s  %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) ++g_failures;
}

static const int RATE = 48000;
static const double PI = 3.14159265358979323846;
static const double R2 = 0.70710678118654752;

/// Steady-state RMS of one channel after the stage, the first second discarded
/// so neither the delay line nor the filters' start-up is measured.
static double ToneRms(double hz, double l_amp, double r_amp)
{
    ProLogicSurround pl;
    pl.Configure(RATE);
    const size_t frames = RATE * 2;
    std::vector<float> sl(frames), sr(frames);
    for (size_t k = 0; k < frames; ++k)
    {
        const double s = std::sin(2.0 * PI * hz * static_cast<double>(k) / RATE);
        sl[k] = static_cast<float>(l_amp * s);
        sr[k] = static_cast<float>(r_amp * s);
    }
    pl.Process(sl.data(), sr.data(), frames);
    double sum = 0.0;
    for (size_t k = RATE; k < frames; ++k)
        sum += static_cast<double>(sl[k]) * sl[k];
    return std::sqrt(sum / static_cast<double>(frames - RATE));
}

static double Db(double ratio)
{
    return 20.0 * std::log10(ratio > 1e-12 ? ratio : 1e-12);
}

// ── P1: one surround, both rears, every frame accounted for ─────────────────
static void TestMonoSurround()
{
    std::printf("P1 the two rears come out as one channel, frame for frame\n");
    ProLogicSurround pl;
    pl.Configure(RATE);
    // Different, uncorrelated content in each rear, in uneven batch sizes so the
    // delay line has to wrap across calls.
    const size_t sizes[] = {800, 1024, 37, 4096, 1};
    size_t total = 0;
    bool same = true;
    bool counted = true;
    unsigned seed = 12345;
    for (size_t n : sizes)
    {
        std::vector<float> sl(n), sr(n);
        for (size_t k = 0; k < n; ++k)
        {
            seed = seed * 1103515245u + 12345u;
            sl[k] = static_cast<float>((seed >> 8) & 0xffff) / 65535.0f - 0.5f;
            sr[k] = std::sin(static_cast<float>(total + k) * 0.01f);
        }
        const std::vector<float> before = sl;
        pl.Process(sl.data(), sr.data(), n);
        counted = counted && sl.size() == before.size();
        for (size_t k = 0; k < n; ++k)
            same = same && sl[k] == sr[k];
        total += n;
    }
    Check(counted, "frames in == frames out on every call");
    Check(same, "SL == SR exactly, whatever the decode put in each");
}

// ── P2: the delay ───────────────────────────────────────────────────────────
static void TestDelay()
{
    std::printf("P2 the surround arrives 20 ms late, and not before\n");
    ProLogicSurround pl;
    pl.Configure(RATE);
    // Judged against the specification's 960, never against DelayFrames(): a
    // check that asks the stage how late it is passes whatever it answers.
    const size_t delay = 960;
    Check(pl.DelayFrames() == delay, "20 ms at 48 kHz is 960 frames");

    const size_t n = 4096;
    std::vector<float> sl(n, 0.0f), sr(n, 0.0f);
    // A click from behind, in the anti-phase pair the decoder hands over.
    sl[0] = 1.0f;
    sr[0] = -1.0f;
    pl.Process(sl.data(), sr.data(), n);
    bool silent_before = true;
    for (size_t k = 0; k < delay; ++k)
        silent_before = silent_before && sl[k] == 0.0f;
    size_t peak_at = 0;
    for (size_t k = 0; k < n; ++k)
        if (std::fabs(sl[k]) > std::fabs(sl[peak_at]))
            peak_at = k;
    std::printf("    impulse response peaks at frame %zu\n", peak_at);
    Check(silent_before, "nothing at all inside the first 960 frames");
    // The band-pass smears the impulse a few frames; it must start at the delay.
    Check(peak_at >= delay && peak_at < delay + 16, "the response begins where the delay ends");
}

// ── P3: the passband ────────────────────────────────────────────────────────
static void TestBand()
{
    std::printf("P3 100 Hz - 7 kHz passes, outside it does not\n");
    // Anti-phase, because that is how the decoder hands over a sound from behind
    // (see ProLogicSurround). An in-phase pair would measure nothing at all.
    const double in_rms = R2;
    const double mid = ToneRms(1000.0, 1.0, -1.0);
    const double high = ToneRms(15000.0, 1.0, -1.0);
    const double low = ToneRms(30.0, 1.0, -1.0);
    std::printf("    1 kHz %.2f dB, 15 kHz %.2f dB, 30 Hz %.2f dB\n", Db(mid / in_rms),
                Db(high / in_rms), Db(low / in_rms));
    Check(std::fabs(Db(mid / in_rms)) < 0.5, "a 1 kHz surround keeps its level (within 0.5 dB)");
    Check(Db(high / in_rms) < -10.0, "15 kHz is at least 10 dB down");
    Check(Db(low / in_rms) < -15.0, "30 Hz is at least 15 dB down");
}

// ── P4: a sound in one rear ─────────────────────────────────────────────────
static void TestOneSide()
{
    std::printf("P4 a sound in one rear plays from both, at half the amplitude\n");
    const double one = ToneRms(1000.0, 1.0, 0.0);
    std::printf("    %.2f dB against the input\n", Db(one / R2));
    Check(std::fabs(Db(one / R2) + 6.02) < 0.5, "6 dB down in each rear");
}

// ── P5: reset ───────────────────────────────────────────────────────────────
static void TestReset()
{
    std::printf("P5 a reset empties the delay line\n");
    ProLogicSurround pl;
    pl.Configure(RATE);
    const size_t n = 2048;
    std::vector<float> sl(n), sr(n);
    for (size_t k = 0; k < n; ++k)
        sl[k] = sr[k] = static_cast<float>(std::sin(2.0 * PI * 1000.0 * k / RATE));
    pl.Process(sl.data(), sr.data(), n);
    pl.Reset();
    std::vector<float> zl(n, 0.0f), zr(n, 0.0f);
    pl.Process(zl.data(), zr.data(), n);
    bool silent = true;
    for (size_t k = 0; k < n; ++k)
        silent = silent && zl[k] == 0.0f && zr[k] == 0.0f;
    Check(silent, "silence in after a reset is silence out");
}

// ── P6: through the real decoder ────────────────────────────────────────────
static void TestThroughDecoder()
{
    std::printf("P6 a Dolby Surround-encoded rear tone, decoded then staged\n");
    const unsigned N = 1024;
    DPL2FSDecoder dec;
    dec.Init(cs_5point1, N, RATE);
    const std::vector<channel_id>& order = chn_id[static_cast<unsigned>(cs_5point1)];
    int idx_fl = -1, idx_sl = -1, idx_sr = -1;
    for (unsigned i = 0; i < order.size(); ++i)
    {
        if (order[i] == ci_front_left) idx_fl = static_cast<int>(i);
        if (order[i] == ci_back_left) idx_sl = static_cast<int>(i);
        if (order[i] == ci_back_right) idx_sr = static_cast<int>(i);
    }
    const unsigned stride = static_cast<unsigned>(order.size());
    ProLogicSurround pl;
    pl.Configure(RATE);

    const unsigned blocks = 24;
    std::vector<float> in(N * 2);
    double rear = 0.0, raw_rear = 0.0, front = 0.0, diff = 0.0;
    unsigned counted = 0;
    for (unsigned b = 0; b < blocks; ++b)
    {
        for (unsigned k = 0; k < N; ++k)
        {
            const double t = 2.0 * PI * 1000.0 * static_cast<double>(b * N + k) / RATE;
            // Surround only: +90 degrees in Lt, -90 in Rt.
            in[k * 2 + 0] = static_cast<float>(R2 * std::cos(t));
            in[k * 2 + 1] = static_cast<float>(-R2 * std::cos(t));
        }
        const float* got = dec.decode(&in[0]);
        if (got == nullptr)
            continue;
        std::vector<float> sl(N), sr(N), fl(N);
        for (unsigned k = 0; k < N; ++k)
        {
            sl[k] = got[k * stride + idx_sl];
            sr[k] = got[k * stride + idx_sr];
            fl[k] = got[k * stride + idx_fl];
        }
        const std::vector<float> raw = sl;
        pl.Process(sl.data(), sr.data(), N);
        if (b < 8)
            continue;
        for (unsigned k = 0; k < N; ++k)
        {
            raw_rear += static_cast<double>(raw[k]) * raw[k];
            rear += static_cast<double>(sl[k]) * sl[k];
            front += static_cast<double>(fl[k]) * fl[k];
            diff += std::fabs(static_cast<double>(sl[k]) - sr[k]);
        }
        counted += N;
    }
    const double rear_rms = std::sqrt(rear / counted);
    const double raw_rms = std::sqrt(raw_rear / counted);
    const double front_rms = std::sqrt(front / counted);
    std::printf("    rear %.4f (Pro Logic II's own %.4f, %.2f dB), front left %.4f, |SL-SR| summed %.6f\n",
                rear_rms, raw_rms, Db(rear_rms / raw_rms), front_rms, diff);
    Check(diff == 0.0, "both rears identical");
    // The case a sum instead of a difference fails: the decoder's two rears are
    // in anti-phase, so they cancel to about -55 dB.
    Check(std::fabs(Db(rear_rms / raw_rms)) < 1.0,
          "the surround keeps the level the 5.1 decode gave it (within 1 dB)");
    Check(rear_rms > 10.0 * front_rms, "the tone is in the rears, at least 20 dB over the front");
}

int main()
{
    TestMonoSurround();
    TestDelay();
    TestBand();
    TestOneSide();
    TestReset();
    TestThroughDecoder();
    std::printf("\n%s (%d failure%s)\n", g_failures ? "FAILED" : "ok", g_failures,
                g_failures == 1 ? "" : "s");
    return g_failures ? 1 : 0;
}

// Standalone harness for the matrix decoder. Build and run with
// tests/run_tests.py. Needs no Godot, no core and no audio device.
//
// The point of these cases is to tell a matrix DECODER from anything that
// merely produces six channels. A Dolby Surround encode is synthesised here, so
// what comes out is checked against what went in rather than against a
// screenshot of a spectrum.

#include <cmath>
#include <cstdio>
#include <vector>

#include "FreeSurround/ChannelMaps.h"
#include "FreeSurround/FreeSurroundDecoder.h"

static int g_failures = 0;

static void Check(bool ok, const char* what)
{
    std::printf("  %s  %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) ++g_failures;
}

static const unsigned N = 1024;
static const unsigned RATE = 48000;
static const double TONE = 1000.0;
static const double R2 = 0.70710678118654752;
static const double PI = 3.14159265358979323846;

// Our channel order, and where each one sits in FreeSurround's output.
enum Ch { FL, FR, C, LFE, SL, SR, CH_COUNT };
static const char* k_names[CH_COUNT] = {"FL", "FR", "C", "LFE", "SL", "SR"};
static const channel_id k_wanted[CH_COUNT] = {
    ci_front_left, ci_front_right, ci_front_center, ci_lfe, ci_back_left, ci_back_right,
};
static int g_src[CH_COUNT];

// ── T1: the output order the remap is derived from ──────────────────────────
static void TestChannelOrder()
{
    std::printf("T1 cs_5point1 enumerates its channels where the remap expects\n");

    const std::vector<channel_id>& order = chn_id[static_cast<unsigned>(cs_5point1)];
    Check(order.size() == CH_COUNT, "six channels");
    if (order.size() != CH_COUNT)
        return;

    const channel_id expect[CH_COUNT] = {
        ci_front_left, ci_front_center, ci_front_right, ci_back_left, ci_back_right, ci_lfe,
    };
    bool same = true;
    for (unsigned i = 0; i < CH_COUNT; ++i)
        same = same && order[i] == expect[i];
    Check(same, "in FL, FC, FR, BL, BR, LFE order");

    for (int c = 0; c < CH_COUNT; ++c)
    {
        g_src[c] = -1;
        for (unsigned i = 0; i < order.size(); ++i)
            if (order[i] == k_wanted[c])
                g_src[c] = static_cast<int>(i);
        Check(g_src[c] >= 0, k_names[c]);
    }
}

/// Encode L/C/R/S into Dolby Surround Lt/Rt and run it through the decoder,
/// returning steady-state RMS per channel. The surround feed is phase-shifted
/// 90 degrees, which for a sine is its cosine.
struct Levels
{
    double rms[CH_COUNT];
};

static Levels DecodeTone(double l_amp, double c_amp, double r_amp, double s_amp, bool lfe,
                         double tone = TONE)
{
    DPL2FSDecoder dec;
    dec.Init(cs_5point1, N, RATE);
    dec.set_bass_redirection(lfe);

    const unsigned blocks = 10;
    const unsigned measure_from = 6; // let the overlap-add pipeline fill first

    Levels out = {};
    double sum[CH_COUNT] = {};
    unsigned counted = 0;

    std::vector<float> in(N * 2);
    for (unsigned b = 0; b < blocks; ++b)
    {
        for (unsigned k = 0; k < N; ++k)
        {
            const double t = 2.0 * PI * tone * static_cast<double>(b * N + k) / RATE;
            const double sine = std::sin(t);
            const double shifted = std::cos(t);
            const double lt = l_amp * sine + R2 * c_amp * sine + R2 * s_amp * shifted;
            const double rt = r_amp * sine + R2 * c_amp * sine - R2 * s_amp * shifted;
            in[k * 2 + 0] = static_cast<float>(lt);
            in[k * 2 + 1] = static_cast<float>(rt);
        }
        const float* got = dec.decode(&in[0]);
        if (got == nullptr)
            continue;
        if (b < measure_from)
            continue;
        for (unsigned k = 0; k < N; ++k)
            for (int c = 0; c < CH_COUNT; ++c)
            {
                const double v = got[k * CH_COUNT + g_src[c]];
                sum[c] += v * v;
            }
        counted += N;
    }

    for (int c = 0; c < CH_COUNT; ++c)
        out.rms[c] = counted ? std::sqrt(sum[c] / counted) : 0.0;
    return out;
}

static void Report(const char* label, const Levels& lv)
{
    std::printf("    %-14s", label);
    for (int c = 0; c < CH_COUNT; ++c)
        std::printf(" %s=%.4f", k_names[c], lv.rms[c]);
    std::printf("\n");
}

static double Ratio(double a, double b)
{
    return b > 1e-9 ? a / b : (a > 1e-9 ? 1e9 : 1.0);
}

// ── T2: centre-encoded content lands in the centre ──────────────────────────
static void TestCentre()
{
    std::printf("T2 a centre-encoded tone comes out of the centre\n");
    const Levels lv = DecodeTone(0.0, 1.0, 0.0, 0.0, false);
    Report("centre only", lv);

    // Measured 0.659 against 0.026 in the fronts, i.e. about 28 dB. A passive
    // matrix would manage 3 dB, so 10x is clear of both.
    Check(lv.rms[C] > 0.5, "the centre channel carries it at near unity gain");
    Check(Ratio(lv.rms[C], lv.rms[FL]) > 10.0, "well above the front left");
    Check(Ratio(lv.rms[C], lv.rms[SL]) > 10.0, "well above the left surround");
    Check(Ratio(lv.rms[C], lv.rms[SR]) > 10.0, "well above the right surround");
}

// ── T3: out-of-phase content lands in the surrounds ─────────────────────────
static void TestSurround()
{
    std::printf("T3 a surround-encoded tone comes out of the surrounds\n");
    const Levels lv = DecodeTone(0.0, 0.0, 0.0, 1.0, false);
    Report("surround only", lv);

    const double rear = 0.5 * (lv.rms[SL] + lv.rms[SR]);
    Check(rear > 0.4, "the surround channels carry it");
    Check(Ratio(rear, lv.rms[C]) > 10.0, "well above the centre");
    Check(Ratio(rear, lv.rms[FL]) > 10.0, "well above the front left");
}

// ── T4: a hard-panned tone stays on its own side ────────────────────────────
static void TestHardPan()
{
    std::printf("T4 a hard-left tone stays left\n");
    const Levels lv = DecodeTone(1.0, 0.0, 0.0, 0.0, false);
    Report("left only", lv);

    Check(lv.rms[FL] > 0.5, "the front left carries it");
    Check(Ratio(lv.rms[FL], lv.rms[FR]) > 10.0, "well above the front right");
    Check(Ratio(lv.rms[FL], lv.rms[C]) > 10.0, "well above the centre");
}

// ── T5: the LFE exists only when bass redirection is on ─────────────────────
static void TestLfe()
{
    std::printf("T5 bass redirection is what produces an LFE\n");
    // Init sets the LFE band to 40-90 Hz, so the tone has to sit inside it.
    const Levels off = DecodeTone(1.0, 0.0, 1.0, 0.0, false, 60.0);
    const Levels on = DecodeTone(1.0, 0.0, 1.0, 0.0, true, 60.0);
    const Levels high = DecodeTone(1.0, 0.0, 1.0, 0.0, true, 1000.0);
    Report("60 Hz, off", off);
    Report("60 Hz, on", on);
    Report("1 kHz, on", high);

    Check(off.rms[LFE] < 1e-6, "silent with redirection off");
    Check(on.rms[LFE] > 0.01, "fed once it is on");
    Check(Ratio(on.rms[LFE], high.rms[LFE]) > 10.0, "and only by content in its band");
}

// ── T6: the decoder's own delay is half a block ─────────────────────────────
static void TestLatency()
{
    std::printf("T6 the decoder reports half a block of delay\n");
    DPL2FSDecoder dec;
    dec.Init(cs_5point1, N, RATE);
    Check(dec.buffered() == 0, "nothing buffered before the first block");

    std::vector<float> in(N * 2, 0.0f);
    dec.decode(&in[0]);
    Check(dec.buffered() == N / 2, "N/2 after it");
}

int main()
{
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    TestChannelOrder();
    if (g_failures)
    {
        std::printf("\nFAILED (channel order is the basis of every other case)\n");
        return 1;
    }
    TestCentre();
    TestSurround();
    TestHardPan();
    TestLfe();
    TestLatency();
    std::printf("\n%s (%d failure%s)\n", g_failures ? "FAILED" : "ALL PASS", g_failures,
                g_failures == 1 ? "" : "s");
    return g_failures ? 1 : 0;
}

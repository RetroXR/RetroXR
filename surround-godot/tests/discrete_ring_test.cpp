// Standalone harness for DiscreteRing, the queue and routing matrix that carry
// six decoded channels to a multichannel output device. Build and run with
// tests/run_tests.py. Needs no Godot and no audio device.
//
// Every input channel is given a value of its own, so a check can say which
// input arrived at which output rather than only that something did.

#include <cmath>
#include <cstdio>
#include <vector>

#include "DiscreteRing.hpp"

using Xenu::DiscreteRing;

static int g_failures = 0;

static void Check(bool ok, const char* what)
{
    std::printf("  %s  %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) ++g_failures;
}

static bool Near(float a, float b) { return std::fabs(a - b) < 1e-5f; }

enum In { FL, FR, C, LFE, SL, SR };
enum Out { O_FL, O_FR, O_C, O_LFE, O_BL, O_BR, O_SL, O_SR };

// Input channel `ch` carries the constant (ch + 1) / 10.
static uint32_t PushConstants(DiscreteRing& ring, uint32_t frames)
{
    std::vector<float> planes[DiscreteRing::kInputs];
    const float* ptrs[DiscreteRing::kInputs];
    for (int ch = 0; ch < DiscreteRing::kInputs; ++ch)
    {
        planes[ch].assign(frames, static_cast<float>(ch + 1) / 10.0f);
        ptrs[ch] = planes[ch].data();
    }
    return ring.Push(ptrs, frames);
}

struct Block
{
    std::vector<float> out[DiscreteRing::kOutputs];
    uint32_t read = 0;
};

static Block Mix(DiscreteRing& ring, uint32_t frames)
{
    Block b;
    float* outs[DiscreteRing::kOutputs];
    for (int o = 0; o < DiscreteRing::kOutputs; ++o)
    {
        b.out[o].assign(frames, 0.0f);
        outs[o] = b.out[o].data();
    }
    b.read = ring.MixInto(outs, frames);
    return b;
}

static void Identity51(float* m)
{
    for (int i = 0; i < DiscreteRing::kGains; ++i)
        m[i] = 0.0f;
    m[FL * 8 + O_FL] = 1.0f;
    m[FR * 8 + O_FR] = 1.0f;
    m[C * 8 + O_C] = 1.0f;
    m[LFE * 8 + O_LFE] = 1.0f;
    m[SL * 8 + O_BL] = 1.0f;
    m[SR * 8 + O_BR] = 1.0f;
}

// ── T1: each input reaches the output the matrix names, and only that one ───
static void TestRouting()
{
    std::printf("T1 the matrix routes each channel to its own output\n");
    DiscreteRing ring;
    float m[DiscreteRing::kGains];
    Identity51(m);
    ring.SetMatrix(m);
    // The first block ramps from silence, so a second block is where the matrix
    // is reached in full.
    PushConstants(ring, 512);
    Mix(ring, 256);
    const Block b = Mix(ring, 256);
    Check(b.read == 256, "a full block was read");
    Check(Near(b.out[O_FL][255], 0.1f), "FL on the device's FL");
    Check(Near(b.out[O_FR][255], 0.2f), "FR on FR");
    Check(Near(b.out[O_C][255], 0.3f), "C on the centre");
    Check(Near(b.out[O_LFE][255], 0.4f), "LFE on the LFE");
    Check(Near(b.out[O_BL][255], 0.5f) && Near(b.out[O_BR][255], 0.6f), "SL and SR on the fifth and sixth");
    Check(Near(b.out[O_SL][255], 0.0f) && Near(b.out[O_SR][255], 0.0f), "nothing on a pair the matrix left out");
}

// ── T2: a fold is a sum at the named gain ───────────────────────────────────
static void TestFold()
{
    std::printf("T2 two inputs on one output sum at their gains\n");
    DiscreteRing ring;
    float m[DiscreteRing::kGains] = {};
    m[FL * 8 + O_FL] = 1.0f;
    m[SL * 8 + O_FL] = 0.5f;
    ring.SetMatrix(m);
    PushConstants(ring, 64);
    Mix(ring, 32);
    const Block b = Mix(ring, 32);
    Check(Near(b.out[O_FL][31], 0.1f + 0.5f * 0.5f), "FL + half of SL");
}

// ── T3: the matrix is reached by a ramp, never a step ───────────────────────
static void TestRamp()
{
    std::printf("T3 a new matrix ramps in across one block\n");
    DiscreteRing ring;
    float m[DiscreteRing::kGains];
    Identity51(m);
    ring.SetMatrix(m);
    PushConstants(ring, 100);
    const Block b = Mix(ring, 100);
    Check(b.out[O_C][0] > 0.0f && b.out[O_C][0] < 0.3f * 0.05f, "the first frame is barely open");
    Check(Near(b.out[O_C][99], 0.3f), "the last frame is fully open");
    Check(b.out[O_C][50] > b.out[O_C][10], "it rises in between");
}

// ── T4: depth, overflow, silence and underrun ───────────────────────────────
static void TestQueue()
{
    std::printf("T4 the queue keeps count, drops overflow and pads an underrun\n");
    DiscreteRing ring;
    Check(ring.Queued() == 0, "starts empty");
    Check(ring.PushSilence(300) == 300 && ring.Queued() == 300, "silence counts as depth");
    const uint32_t took = PushConstants(ring, DiscreteRing::kFrames);
    Check(took == DiscreteRing::kFrames - 300, "a push past the end takes only what fits");
    Check(ring.Queued() == DiscreteRing::kFrames, "and leaves it exactly full");

    DiscreteRing short_ring;
    float m[DiscreteRing::kGains];
    Identity51(m);
    short_ring.SetMatrix(m);
    PushConstants(short_ring, 10);
    const Block b = Mix(short_ring, 64);
    Check(b.read == 10, "an underrun reads what there is");
    Check(Near(b.out[O_C][63], 0.0f), "and pads the rest with silence");
    Check(short_ring.Queued() == 0, "leaving the queue empty");
}

// ── T5: a flush is honoured by the consumer ─────────────────────────────────
static void TestFlush()
{
    std::printf("T5 a requested flush empties the queue on the next pull\n");
    DiscreteRing ring;
    PushConstants(ring, 1000);
    ring.RequestFlush();
    Check(ring.Queued() == 1000, "not before the consumer runs");
    const Block b = Mix(ring, 64);
    Check(b.read == 0 && ring.Queued() == 0, "the pull discards it and reads nothing");
}

// ── T6: several sources share one device ────────────────────────────────────
static void TestAccumulate()
{
    std::printf("T6 a mix adds to what is already in the block\n");
    DiscreteRing a, b;
    float m[DiscreteRing::kGains];
    Identity51(m);
    a.SetMatrix(m);
    b.SetMatrix(m);
    PushConstants(a, 64);
    PushConstants(b, 64);
    float outs_mem[DiscreteRing::kOutputs][32] = {};
    float* outs[DiscreteRing::kOutputs];
    for (int o = 0; o < DiscreteRing::kOutputs; ++o)
        outs[o] = outs_mem[o];
    a.MixInto(outs, 32);
    b.MixInto(outs, 32);
    for (int o = 0; o < DiscreteRing::kOutputs; ++o)
        for (int f = 0; f < 32; ++f)
            outs_mem[o][f] = 0.0f;
    a.MixInto(outs, 32);
    b.MixInto(outs, 32);
    Check(Near(outs_mem[O_C][31], 0.6f), "two centres sum");
}

int main()
{
    TestRouting();
    TestFold();
    TestRamp();
    TestQueue();
    TestFlush();
    TestAccumulate();
    if (g_failures)
    {
        std::printf("%d FAILED\n", g_failures);
        return 1;
    }
    std::printf("all passed\n");
    return 0;
}

#include "SurroundOutput.hpp"

#include <godot_cpp/classes/audio_server.hpp>
#include <godot_cpp/classes/audio_stream_generator.hpp>
#include <godot_cpp/classes/audio_stream_player.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/window.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <algorithm>

using namespace godot;

namespace Xenu
{

// ---------------------------------------------------------------------------
// DiscreteSink
// ---------------------------------------------------------------------------

DiscreteSink& DiscreteSink::Get()
{
    static DiscreteSink sink;
    return sink;
}

void DiscreteSink::Register(const std::shared_ptr<DiscreteRing>& ring)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    m_rings.push_back(ring);
}

void DiscreteSink::Unregister(const std::shared_ptr<DiscreteRing>& ring)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    m_rings.erase(std::remove(m_rings.begin(), m_rings.end(), ring), m_rings.end());
}

void DiscreteSink::Pull(uint32_t frames)
{
    // Grown on the audio thread, once, to the AudioServer's block size; every
    // later block reuses it.
    if (m_planes_frames < frames)
    {
        for (auto& plane : m_planes)
            plane.resize(frames);
        m_planes_frames = frames;
    }
    float* outs[DiscreteRing::kOutputs];
    for (int i = 0; i < DiscreteRing::kOutputs; ++i)
    {
        std::fill(m_planes[i].begin(), m_planes[i].begin() + frames, 0.0f);
        outs[i] = m_planes[i].data();
    }
    std::lock_guard<std::mutex> lock(m_mutex);
    for (const auto& ring : m_rings)
        ring->MixInto(outs, frames);
}

void DiscreteSink::Write(int pair, AudioFrame* dst, uint32_t frames) const
{
    if (pair < 0 || pair * 2 + 1 >= DiscreteRing::kOutputs || frames > m_planes_frames)
        return;
    const float* l = m_planes[pair * 2].data();
    const float* r = m_planes[pair * 2 + 1].data();
    for (uint32_t f = 0; f < frames; ++f)
    {
        dst[f].left += l[f];
        dst[f].right += r[f];
    }
}

int DiscreteSink::BusIndex() const
{
    AudioServer* as = AudioServer::get_singleton();
    return as ? as->get_bus_index(kBusName) : -1;
}

bool DiscreteSink::EnsureBus()
{
    AudioServer* as = AudioServer::get_singleton();
    if (as == nullptr)
        return false;
    // Never in the editor: its bus panel mirrors the AudioServer and saves what
    // it shows into default_bus_layout.tres.
    if (Engine::get_singleton()->is_editor_hint())
        return false;

    int idx = as->get_bus_index(kBusName);
    if (idx < 0)
    {
        idx = as->get_bus_count();
        as->add_bus();
        as->set_bus_name(idx, kBusName);
        as->set_bus_send(idx, "Master");
        Ref<SurroundOutputEffect> fx;
        fx.instantiate();
        as->add_bus_effect(idx, fx);
        m_bus_made = true;
    }
    if (m_player_id != 0 && ObjectDB::get_instance(m_player_id) != nullptr)
        return true;
    SceneTree* tree = Object::cast_to<SceneTree>(Engine::get_singleton()->get_main_loop());
    if (tree == nullptr || tree->get_root() == nullptr)
        return true;
    if (m_quiet.is_null())
        m_quiet.instantiate();
    AudioStreamPlayer* player = memnew(AudioStreamPlayer);
    player->set_name("SurroundOutKeepAwake");
    player->set_stream(m_quiet);
    player->set_bus(kBusName);
    m_player_id = static_cast<uint64_t>(player->get_instance_id());
    // Deferred for the reason MetaXRAudioServer::EnsurePlayer gives: a request
    // arriving while the root is still adding its own children is refused.
    tree->get_root()->call_deferred("add_child", player);
    player->call_deferred("play", 0.0);
    return true;
}

void DiscreteSink::Teardown()
{
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_rings.clear();
    }
    if (AudioServer* as = AudioServer::get_singleton())
    {
        const int idx = as->get_bus_index(kBusName);
        if (idx > 0 && m_bus_made)
            as->remove_bus(idx);
    }
    m_bus_made = false;
    // The tree freed the keep-awake player before this runs, which only STOPS its
    // playback: the audio thread still has to mix it once to fade it out and
    // retire it, and that mix reads the generator. The wait buys those mix cycles
    // -- the same tenth of a second MetaXRAudioServer::PrepareForQuit pays -- and
    // is paid once, on the way out, only if the bus was ever made.
    m_player_id = 0;
    if (m_quiet.is_valid())
    {
        if (OS* os = OS::get_singleton())
            os->delay_msec(100);
        m_quiet.unref();
    }
}

// ---------------------------------------------------------------------------
// SurroundOutput
// ---------------------------------------------------------------------------

SurroundOutput::SurroundOutput() : m_ring(std::make_shared<DiscreteRing>())
{
    DiscreteSink::Get().Register(m_ring);
}

SurroundOutput::~SurroundOutput()
{
    DiscreteSink::Get().Unregister(m_ring);
}

int SurroundOutput::Push(const Array& planes)
{
    if (planes.size() != DiscreteRing::kInputs)
        return 0;
    int64_t frames = -1;
    const float* ptrs[DiscreteRing::kInputs];
    for (int ch = 0; ch < DiscreteRing::kInputs; ++ch)
    {
        m_planes[ch] = planes[ch];
        const int64_t n = m_planes[ch].size();
        frames = (frames < 0 || n < frames) ? n : frames;
        ptrs[ch] = m_planes[ch].ptr();
    }
    if (frames <= 0)
        return 0;
    return static_cast<int>(m_ring->Push(ptrs, static_cast<uint32_t>(frames)));
}

int SurroundOutput::PushSilence(int frames)
{
    return frames > 0 ? static_cast<int>(m_ring->PushSilence(static_cast<uint32_t>(frames))) : 0;
}

int SurroundOutput::Queued() const
{
    return static_cast<int>(m_ring->Queued());
}

void SurroundOutput::Flush()
{
    m_ring->RequestFlush();
}

void SurroundOutput::SetMatrix(const PackedFloat32Array& gains)
{
    float m[DiscreteRing::kGains] = {};
    const int64_t n = std::min<int64_t>(gains.size(), DiscreteRing::kGains);
    for (int64_t i = 0; i < n; ++i)
        m[i] = gains[i];
    m_ring->SetMatrix(m);
}

float SurroundOutput::GetGain(int in, int out) const
{
    if (in < 0 || in >= DiscreteRing::kInputs || out < 0 || out >= DiscreteRing::kOutputs)
        return 0.0f;
    return m_ring->TargetGain(in, out);
}

void SurroundOutput::_bind_methods()
{
    ClassDB::bind_method(D_METHOD("push", "planes"), &SurroundOutput::Push);
    ClassDB::bind_method(D_METHOD("push_silence", "frames"), &SurroundOutput::PushSilence);
    ClassDB::bind_method(D_METHOD("queued"), &SurroundOutput::Queued);
    ClassDB::bind_method(D_METHOD("flush"), &SurroundOutput::Flush);
    ClassDB::bind_method(D_METHOD("set_matrix", "gains"), &SurroundOutput::SetMatrix);
    ClassDB::bind_method(D_METHOD("get_gain", "input", "output"), &SurroundOutput::GetGain);
}

// ---------------------------------------------------------------------------
// The bus effect
// ---------------------------------------------------------------------------

void SurroundOutputInstance::_process(const void* p_src_buffer, AudioFrame* p_dst_buffer, int32_t p_frame_count)
{
    if (p_frame_count <= 0)
        return;
    const uint32_t frames = static_cast<uint32_t>(p_frame_count);
    // Whatever else reached the bus carries on through it. In practice that is
    // the keep-awake player's silence.
    const AudioFrame* src = static_cast<const AudioFrame*>(p_src_buffer);
    for (uint32_t f = 0; f < frames; ++f)
        p_dst_buffer[f] = src[f];
    const int pair = GetPair();
    if (pair < 0)
        return;
    DiscreteSink& sink = DiscreteSink::Get();
    // The AudioServer runs a bus's pairs in order, 0 first, every block, so the
    // first instance is the one that drains the rings for the rest.
    if (pair == 0)
        sink.Pull(frames);
    sink.Write(pair, p_dst_buffer, frames);
}

int SurroundOutputInstance::GetPair()
{
    const int known = m_pair.load(std::memory_order_relaxed);
    if (known >= 0)
        return known;
    // A lookup, not a lock: get_bus_effect_instance reads the bus's own table,
    // which is safe from inside the mix that holds the driver lock.
    AudioServer* as = AudioServer::get_singleton();
    if (as == nullptr)
        return -1;
    const int bus = as->get_bus_index(DiscreteSink::kBusName);
    if (bus < 0)
        return -1;
    const int pairs = as->get_bus_channels(bus);
    for (int k = 0; k < pairs; ++k)
    {
        if (as->get_bus_effect_instance(bus, 0, k).ptr() == this)
        {
            m_pair.store(k, std::memory_order_relaxed);
            return k;
        }
    }
    return -1;
}

void SurroundOutputInstance::_bind_methods()
{
    ClassDB::bind_method(D_METHOD("get_pair"), &SurroundOutputInstance::GetPair);
}

Ref<AudioEffectInstance> SurroundOutputEffect::_instantiate()
{
    Ref<SurroundOutputInstance> inst;
    inst.instantiate();
    return inst;
}

} // namespace Xenu

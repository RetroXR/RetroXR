#pragma once

// SurroundAudio - an Engine singleton whose only job is to hand out decoders.
//
// It exists so another extension can reach SurroundDecoder WITHOUT naming its
// class. libretro-godot is built against a trimmed godot-cpp
// (Tools/godot_cpp_profile.json, 53 classes) that does not include
// ClassDBSingleton, and adding a class there forces a full godot-cpp rebuild for
// every extension. Engine is already in that list, so
//
//     Engine::get_singleton()->has_singleton("SurroundAudio")
//
// costs nothing and is the same arm's-length route AudioHandler already takes to
// the Meta XR Audio mixer: optional at runtime, absent without error.
//
// A decoder is NOT a singleton and this is not one in disguise. The STFT carries
// state across blocks, so every source that decodes needs its own - each machine
// and each deck. This object only constructs them.

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/ref_counted.hpp>

namespace Xenu
{

class SurroundAudio : public godot::Object
{
    GDCLASS(SurroundAudio, godot::Object)

public:
    SurroundAudio() = default;
    ~SurroundAudio() override = default;

    /// A decoder, configured and ready, or null when `block_frames` or
    /// `sample_rate` is refused. Returned as RefCounted rather than as the
    /// concrete type so a caller that cannot name SurroundDecoder can still hold
    /// it and call "decode" through Object::call.
    godot::Ref<godot::RefCounted> CreateDecoder(int block_frames, int sample_rate);

    /// What Configure would refuse, so a caller can check before asking.
    static bool BlockIsUsable(int block_frames);

protected:
    static void _bind_methods();
};

} // namespace Xenu

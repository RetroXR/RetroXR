#include "SurroundAudio.hpp"

#include "SurroundDecoder.hpp"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace Xenu
{

bool SurroundAudio::BlockIsUsable(int block_frames)
{
    // The same window Configure accepts. Duplicated deliberately rather than
    // exposed from the decoder: this is the one question a caller wants answered
    // BEFORE it has an object to ask.
    if (block_frames < 64 || block_frames > 16384)
        return false;
    return (block_frames & (block_frames - 1)) == 0;
}

Ref<RefCounted> SurroundAudio::CreateDecoder(int block_frames, int sample_rate)
{
    Ref<SurroundDecoder> dec;
    dec.instantiate();
    if (!dec->Configure(block_frames, sample_rate))
        return Ref<RefCounted>();
    return dec;
}

void SurroundAudio::_bind_methods()
{
    ClassDB::bind_method(D_METHOD("create_decoder", "block_frames", "sample_rate"),
                         &SurroundAudio::CreateDecoder);
    ClassDB::bind_static_method("SurroundAudio", D_METHOD("block_is_usable", "block_frames"),
                                &SurroundAudio::BlockIsUsable);
}

} // namespace Xenu

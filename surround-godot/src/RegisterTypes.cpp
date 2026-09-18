#include "SurroundAudio.hpp"
#include "SurroundDecoder.hpp"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

static Xenu::SurroundAudio* s_singleton = nullptr;

void initialize_surround(ModuleInitializationLevel p_level)
{
    if (p_level != ModuleInitializationLevel::MODULE_INITIALIZATION_LEVEL_SCENE)
        return;

    ClassDB::register_class<Xenu::SurroundDecoder>();
    ClassDB::register_class<Xenu::SurroundAudio>();

    // The factory is a singleton so another extension can reach a decoder through
    // Engine alone -- see SurroundAudio.hpp. Leaked on purpose in the sense that
    // the engine owns it from here; uninitialize_surround takes it back.
    s_singleton = memnew(Xenu::SurroundAudio);
    Engine::get_singleton()->register_singleton("SurroundAudio", s_singleton);
}

void uninitialize_surround(ModuleInitializationLevel p_level)
{
    if (p_level != ModuleInitializationLevel::MODULE_INITIALIZATION_LEVEL_SCENE)
        return;
    if (s_singleton != nullptr)
    {
        Engine::get_singleton()->unregister_singleton("SurroundAudio");
        memdelete(s_singleton);
        s_singleton = nullptr;
    }
}

extern "C"
{
GDExtensionBool GDE_EXPORT surround_library_init(GDExtensionInterfaceGetProcAddress p_gde_get_proc_address,
                                                 const GDExtensionClassLibraryPtr p_library,
                                                 GDExtensionInitialization* r_initialization)
{
    godot::GDExtensionBinding::InitObject init_obj(p_gde_get_proc_address, p_library, r_initialization);
    init_obj.register_initializer(initialize_surround);
    init_obj.register_terminator(uninitialize_surround);
    init_obj.set_minimum_library_initialization_level(godot::ModuleInitializationLevel::MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}
}

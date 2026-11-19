#include "PDFRenderer.hpp"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize(ModuleInitializationLevel p_level)
{
    if (p_level != ModuleInitializationLevel::MODULE_INITIALIZATION_LEVEL_SCENE)
        return;

    Xenu::PDFRenderer::InitLibrary();

    ClassDB::register_class<Xenu::PDFRenderer>();
}

void uninitialize(ModuleInitializationLevel p_level)
{
    if (p_level != ModuleInitializationLevel::MODULE_INITIALIZATION_LEVEL_SCENE)
        return;

    Xenu::PDFRenderer::DestroyLibrary();
}

extern "C"
{
GDExtensionBool GDE_EXPORT godot_pdfium_library_init(GDExtensionInterfaceGetProcAddress p_gde_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization)
{
    godot::GDExtensionBinding::InitObject init_obj(p_gde_get_proc_address, p_library, r_initialization);

    init_obj.register_initializer(initialize);
    init_obj.register_terminator(uninitialize);
    init_obj.set_minimum_library_initialization_level(godot::ModuleInitializationLevel::MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}
}

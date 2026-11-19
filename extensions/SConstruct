# type: ignore

VariantDir('libretro-godot/Temp', 'libretro-godot', duplicate=0)
env = Environment()
output_dir = '#RetroXR/libretro-godot'

SConscript('libretro-godot/Temp/SConscript', exports=['env', 'output_dir'])

# godot-pdfium is built separately — run scons from godot-pdfium/ directory.
# Both extensions share godot-cpp, which can't be in the same SCons invocation.

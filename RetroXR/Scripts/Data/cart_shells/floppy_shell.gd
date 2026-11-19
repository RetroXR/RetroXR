## FloppyShell — the disk a computer's game spawns as: the 3.5-inch disk, or the
## 5.25-inch one for the machines in MediaDimensions.FLOPPY_525_SYSTEMS.
##
## Models from RetroXR-models generic/floppy-3.5 and generic/floppy-5.25, in the
## game's floppy frames (label +Z; the 3.5-inch shutter edge +Y, the 5.25-inch
## label strip +Y), so the tower's seats take them unturned. A disk's label is
## paper: art is laid over it, not in its place (RetroCartridge._apply_label_art).
class_name FloppyShell
extends RefCounted

const BODY_35 := "res://imported-assets/carts/floppy_35/floppy_35.glb"
const BODY_525 := "res://imported-assets/carts/floppy_525/floppy_525.glb"
## The 5.25-inch model's own bounds: ECMA-70's 133.3 mm jacket, 2.11 mm through
## its flaps, label and tab (the game's slab is 1.6 mm).
const SIZE_525 := Vector3(0.1333, 0.1333, 0.00211)


## The floppy systems this shell answers for: those sized as a plain disk (the
## 64DD and the Disk System have disks of their own).
static func systemids() -> Array:
	var out: Array = []
	for systemid: String in MediaDimensions.FLOPPY_SYSTEMS:
		if not MediaDimensions.CART_SIZES.has(systemid):
			out.append(systemid)
	return out


static func is_body(model_path: String) -> bool:
	return model_path == BODY_35 or model_path == BODY_525


static func cart_body(systemid: String, _rom_path: String, _body_region: String,
		_shell_preset: StringName, _pinned: String) -> String:
	var path := BODY_525 if MediaDimensions.uses_floppy_525(systemid) else BODY_35
	return path if ResourceLoader.exists(path) else ""

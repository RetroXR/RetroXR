## ArcadeShadowBudget — takes the shadow away from parts too small for anyone to see one.
##
## A mesh costs a draw in the main pass and another in the shadow pass of EVERY shadow-casting light
## that reaches it (an omni up to six faces, a directional light one per split). A cabinet is about a
## hundred and ninety parts and a room has several such lights: the buttons, the stick, the terminals
## and the chips of a board are most of the casters and cast shadows a few pixels wide. Measured on one
## cabinet with its bay and board (Tools/perf/arcade_mesh_census): 134 shadow draws per light, 71 of
## them in parts under 10 cm. The cabinet's own shell, the deck and the door keep theirs.
class_name ArcadeShadowBudget
extends RefCounted

## A part whose largest side, as it stands in the world, is under this casts no shadow (metres).
const SMALL := 0.10


## Turns shadow casting off on every small mesh under `root`; returns how many it turned off.
## `root` must be in the tree (the size is the world size, so a scaled model is judged as it stands).
static func trim(root: Node, small: float = SMALL) -> int:
	var turned := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		if not mi.is_inside_tree():
			continue
		var size := (mi.global_transform * mi.get_aabb()).size
		if maxf(size.x, maxf(size.y, size.z)) < small:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			turned += 1
	return turned

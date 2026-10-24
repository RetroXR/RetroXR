## Where a cabinet's draw calls and triangles are: every MeshInstance3D of one cabinet, its bay and
## its board, with its triangles, surfaces, size, shadow mode and whether it is blended. Windowed or
## headless both work (nothing is rendered); it only reads the scene.
##
##   "$godot" --headless --path RetroXR res://Tools/perf/arcade_mesh_census.tscn -- \
##       [--model=arcade_cabinet_generic] [--rom=<romset zip>] [--top=25]
##
## A mesh costs 1 draw per surface in the main pass and again in the shadow pass of EVERY shadow-casting
## light that reaches it (an omni up to 6 faces, a directional one per split), so `shadow` ON on a mesh
## that nobody can see the shadow of is the cheap thing to take away.
extends Node3D

const Common := preload("res://Tools/perf/arcade_perf_common.gd")


func _ready() -> void:
	var a := Common.parse_args()
	var model_id := str(a.get("model", "arcade_cabinet_generic"))
	var rom := str(a.get("rom", ""))
	var top := int(a.get("top", 25))
	get_tree().create_timer(60.0).timeout.connect(func() -> void: get_tree().quit(2))
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()
	var sys := Common.spawn_cabinet(self, 0, 1, model_id, "", rom)
	for i in 10:
		await get_tree().process_frame
	if not rom.is_empty() and FileAccess.file_exists(rom):
		await Common.seat_board(self, sys, rom)
	var groups := {"cabinet": sys, "bay": sys.get_bay()}
	var cart: Node = null
	for c in get_children():
		if c is RetroCartridge:
			cart = c
	groups["board"] = cart
	var all_rows: Array = []
	for g: String in groups:
		var root: Node = groups[g]
		if root == null:
			continue
		var rows: Array = []
		var tris := 0
		var surfaces := 0
		var casters := 0
		for n in root.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			if g == "cabinet" and sys.get_bay() != null and sys.get_bay().is_ancestor_of(mi):
				continue
			if g == "cabinet" and cart != null and cart.is_ancestor_of(mi):
				continue
			var t := mi.mesh.get_faces().size() / 3
			var box := mi.get_aabb().size * mi.global_transform.basis.get_scale()
			var blended := false
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s)
				if m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					blended = true
			var casts := mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and mi.is_visible_in_tree()
			tris += t
			surfaces += mi.mesh.get_surface_count()
			casters += mi.mesh.get_surface_count() if casts else 0
			rows.append({"name": str(root.get_path_to(mi)), "tris": t, "surf": mi.mesh.get_surface_count(),
				"size_cm": "%.0fx%.0fx%.0f" % [box.x * 100, box.y * 100, box.z * 100], "shadow": casts, "blend": blended,
				"max_cm": maxf(box.x, maxf(box.y, box.z)) * 100.0})
		rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["tris"] > y["tris"])
		print("[census] %s: %d meshes, %d surfaces (draws), %d triangles, %d surfaces cast shadows" % [g, rows.size(), surfaces, tris, casters])
		for r: Dictionary in rows.slice(0, top):
			print("[census]   %-58s %6d tris %2d surf %-11s shadow=%s%s" % [r["name"], r["tris"], r["surf"], r["size_cm"], "ON " if r["shadow"] else "off", " BLEND" if r["blend"] else ""])
		# What a size rule would take away: casters under a given largest dimension.
		for limit in [10.0, 20.0, 30.0, 50.0]:
			var n_s := 0
			var n_t := 0
			for r: Dictionary in rows:
				if r["shadow"] and float(r["max_cm"]) < limit:
					n_s += int(r["surf"])
					n_t += int(r["tris"])
			print("[census]   shadows off under %2.0f cm: -%d shadow draws, -%d shadow triangles per light" % [limit, n_s, n_t])
		all_rows.append_array(rows)
	get_tree().quit(0)

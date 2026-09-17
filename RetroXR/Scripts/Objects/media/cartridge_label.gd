class_name CartridgeLabel
extends RefCounted
## Set a cartridge's label without modifying the imported/shared material.
## PNG/JPEG/WebP can be decoded at runtime; packaged textures use apply_texture.

static func find_label(cartridge: Node) -> MeshInstance3D:
	if cartridge is MeshInstance3D and cartridge.name == &"Label":
		return cartridge as MeshInstance3D
	for child in cartridge.get_children():
		var found := find_label(child)
		if found != null:
			return found
	return null

static func apply_file(cartridge: Node, image_path: String) -> Error:
	var image := Image.new()
	var error := image.load(image_path)
	if error != OK:
		return error
	if image.is_empty():
		return ERR_INVALID_DATA
	image.generate_mipmaps()
	return apply_texture(cartridge, ImageTexture.create_from_image(image))

static func apply_texture(cartridge: Node, texture: Texture2D) -> Error:
	if texture == null:
		return ERR_INVALID_PARAMETER
	var label := find_label(cartridge)
	if label == null or label.mesh == null or label.mesh.get_surface_count() != 1:
		return ERR_DOES_NOT_EXIST
	var source := label.get_active_material(0) as BaseMaterial3D
	if source == null:
		return ERR_INVALID_DATA
	var material := source.duplicate() as BaseMaterial3D
	material.resource_local_to_scene = true
	material.albedo_color = Color.WHITE
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.texture_repeat = false
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	label.set_surface_override_material(0, material)
	return OK

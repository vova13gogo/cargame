## FlatStyle.gd - Central helper for the "Dumb Ways"-inspired flat look.
##
## Every visual in the game is built from primitives + unshaded or lambert
## StandardMaterial3D with no textures. This class caches materials so we do
## not create thousands of duplicates (important for MultiMesh performance).
class_name FlatStyle
extends RefCounted

static var _mat_cache: Dictionary = {}


## Get (or create) a cached flat material. UNSHADED = pure cartoon color,
## FLAT = keeps a hint of lighting for volume reading on big surfaces.
static func mat(color: Color, unshaded: bool = true) -> StandardMaterial3D:
	var key := "%s_%d" % [color.to_html(), int(unshaded)]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded \
		else BaseMaterial3D.SHADING_MODE_FLAT
	m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	m.roughness = 1.0
	m.metallic = 0.0
	m.specular = 0.0          # no specular highlights at all - toy-like
	_mat_cache[key] = m
	return m


## Translucent variant used for water and ghost previews.
static func mat_transparent(color: Color, alpha: float) -> StandardMaterial3D:
	var key := "T_%s_%f" % [color.to_html(), alpha]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.specular = 0.0
	_mat_cache[key] = m
	return m


## Emissive material for glowing crystals / lamps (Stage 6+ but ready now).
static func mat_glow(color: Color) -> StandardMaterial3D:
	var key := "G_%s" % color.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.6
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = false
	_mat_cache[key] = m
	return m


## Tiny factory: make a MeshInstance3D from a primitive with a flat material.
static func make_part(mesh: Mesh, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO,
		scale_vec: Vector3 = Vector3.ONE, unshaded: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color, unshaded)
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scale_vec
	return mi

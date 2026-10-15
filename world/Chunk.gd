## Chunk.gd - One terrain chunk: heightmap mesh + scatter props + collision.
##
## Performance strategy (Stage 1):
##  - Terrain is a single ArrayMesh per chunk built from the shared Terrain
##    sampler, with vertex colors taken from the zone palette (one draw call).
##  - Collision uses Godot 4.3's create_trimesh_collision() which builds a
##    Convex decomposed shape from the visible mesh (cheap enough at this res).
##  - Trees/rocks are MultiMeshInstance3D (one draw call per prop type).
##  - Chunks far from the player are freed by WorldManager and rebuilt on demand
##    from the same seed, so memory stays bounded.
class_name Chunk
extends Node3D

const RES := 20          # cells per side -> (RES+1)^2 vertices

var cx: int = 0
var cz: int = 0
var size: float = 80.0


func setup(chunk_x: int, chunk_z: int, chunk_size: float) -> void:
	cx = chunk_x
	cz = chunk_z
	size = chunk_size
	position = Vector3(cx * size, 0.0, cz * size)
	name = "Chunk_%d_%d" % [cx, cz]


func build() -> void:
	_build_terrain_mesh()
	_build_scatter()


# ---------------------------------------------------------------------------
# Terrain surface
# ---------------------------------------------------------------------------
func _build_terrain_mesh() -> void:
	var step := size / float(RES)
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	# Vertex grid. Chunk-local origin is (cx*size - half_world ...).
	for iz in RES + 1:
		for ix in RES + 1:
			var lx := float(ix) * step
			var lz := float(iz) * step
			var wx := position.x + lx
			var wz := position.z + lz
			var h := Terrain.get_height(wx, wz)
			verts.append(Vector3(lx, h, lz))
			colors.append(_color_for(wx, wz, h))

	# Two triangles per quad.
	for iz in RES:
		for ix in RES:
			var i0 := iz * (RES + 1) + ix
			var i1 := i0 + 1
			var i2 := i0 + (RES + 1)
			var i3 := i2 + 1
			indices.append_array(PackedInt32Array([i0, i2, i1, i1, i2, i3]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, FlatStyle.mat(Color.WHITE, false))  # FLAT shading, vertex colors

	var mi := MeshInstance3D.new()
	mi.name = "Surface"
	mi.mesh = mesh
	add_child(mi)

	# Static collision derived from the same mesh (trimesh concave shape).
	var body := StaticBody3D.new()
	body.name = "Collision"
	add_child(body)
	var col := CollisionShape3D.new()
	body.add_child(col)
	var shape := ConcavePolygonShape3D.new()
	shape.trimesh = mesh.create_trimesh()   # physics-server trimesh, exact match
	col.shape = shape


## Zone-tinted ground color with slope-based rock blending.
func _color_for(wx: float, wz: float, h: float) -> Color:
	var zone: Dictionary = GameState.get_zone_at(Vector3(wx, h, wz))
	var c: Color = zone["ground_color"]

	# Underwater sand/shelf tint.
	if h < GameState.water_level + 1.2:
		c = c.lerp(Color(0.90, 0.82, 0.55), 0.6)

	# Steep slopes show the zone's rock color instead of grass/sand.
	var n := Terrain.get_normal(wx, wz, 1.5)
	var steep := clampf((0.75 - n.y) / 0.45, 0.0, 1.0)
	c = c.lerp(zone["rock_color"], steep)

	# Snow caps on high mountains regardless of zone rect.
	if h > 18.0:
		c = c.lerp(Color(0.96, 0.98, 1.0), clampf((h - 18.0) / 8.0, 0.0, 1.0))

	# Gentle checker variation so big flat areas don't look dead (toy style).
	var chk := int(floor(wx / 4.0) + floor(wz / 4.0)) % 2
	if chk == 0:
		c = c.lightened(0.045)
	return c


# ---------------------------------------------------------------------------
# Props: trees & rocks as MultiMesh, deterministic per chunk+seed
# ---------------------------------------------------------------------------
func _build_scatter() -> void:
	var rng := GameState.make_rng(cx * 73856093 + cz * 19349663)
	var step := 5.0                       # scatter grid spacing
	var trunk_mesh := CapsuleMesh.new()
	trunk_mesh.radius = 0.28
	trunk_mesh.height = 2.2
	var leaf_mesh := SphereMesh.new()     # rounded blob canopy
	leaf_mesh.radius = 1.4
	leaf_mesh.height = 2.6
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 0.9
	rock_mesh.height = 1.1

	# Reset per-chunk buffers so state is clean even if reused.
	_tree_xforms.clear(); _canopy_xforms.clear(); _rock_xforms.clear()
	_trunk_colors = PackedColorArray(); _leaf_colors = PackedColorArray()
	_rock_colors = PackedColorArray()

	var tree_count := 0
	var rock_count := 0
	var max_props := 60                   # budget per chunk

	for iz in int(size / step):
		for ix in int(size / step):
			if tree_count + rock_count >= max_props:
				break
			var wx := position.x + ix * step + rng.randf_range(-2.0, 2.0)
			var wz := position.z + iz * step + rng.randf_range(-2.0, 2.0)
			var h := Terrain.get_height(wx, wz)
			if h < GameState.water_level + 0.8:
				continue                    # no props in the sea
			var slope := Terrain.get_normal(wx, wz).y
			if slope < 0.72:
				continue                    # too steep for anything
			var roll := rng.randf()
			var zone_id: String = GameState.get_zone_at(Vector3(wx, h, wz))["id"]
			if roll < 0.55:
				_add_tree(zone_id, Vector3(wx, h, wz), rng)
				tree_count += 1
			elif roll < 0.8:
				_add_rock(Vector3(wx, h, wz), rng)
				rock_count += 1

	if tree_count > 0:
		_flush_trees(trunk_mesh, leaf_mesh)
	if rock_count > 0:
		_flush_rocks(rock_mesh)


# Collected transforms are flushed into MultiMeshes at the end of build().
var _tree_xforms: Array[Transform3D] = []
var _canopy_xforms: Array[Transform3D] = []
var _rock_xforms: Array[Transform3D] = []
var _leaf_colors: PackedColorArray = PackedColorArray()
var _trunk_colors: PackedColorArray = PackedColorArray()
var _rock_colors: PackedColorArray = PackedColorArray()


func _add_tree(zone_id: String, base: Vector3, rng: RandomNumberGenerator) -> void:
	var zone: Dictionary = GameState.get_zone_by_id(zone_id)
	var s := rng.randf_range(0.8, 1.6)
	var rot_y := rng.randf_range(0.0, 360.0)
	var trunk := Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(rot_y), 0)) \
		.scaled(Vector3(s, s, s)), base + Vector3(0, 1.1 * s, 0))
	var canopy := Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(rot_y), 0)) \
		.scaled(Vector3(s, s, s)), base + Vector3(0, 2.9 * s, 0))
	_tree_xforms.append(trunk)
	_canopy_xforms.append(canopy)
	# Per-instance color so one MultiMesh serves every zone's palette.
	_trunk_colors.append(zone["trunk_color"])
	_leaf_colors.append(zone["tree_color"])


func _add_rock(base: Vector3, rng: RandomNumberGenerator) -> void:
	var s := rng.randf_range(0.5, 1.4)
	var b := Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0, TAU),
		rng.randf_range(-0.3, 0.3))).scaled(Vector3(s, s * rng.randf_range(0.5, 0.9), s))
	_rock_xforms.append(Transform3D(b, base + Vector3(0, s * 0.25, 0)))
	_rock_colors.append(GameState.get_zone_at(base)["rock_color"])


func _flush_trees(trunk_mesh: Mesh, leaf_mesh: Mesh) -> void:
	add_child(_make_multimesh(trunk_mesh, _tree_xforms, _trunk_colors))
	add_child(_make_multimesh(leaf_mesh, _canopy_xforms, _leaf_colors))


func _flush_rocks(rock_mesh: Mesh) -> void:
	add_child(_make_multimesh(rock_mesh, _rock_xforms, _rock_colors))


static func _make_multimesh(mesh: Mesh, xforms: Array[Transform3D], colors: PackedColorArray) \
		-> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if i < colors.size():
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	# Unshaded material so instance colors pop like flat stickers.
	mmi.material_override = FlatStyle.mat(Color.WHITE, true)
	return mmi

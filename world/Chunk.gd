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
@export var respawn_time: float = 90.0   ## seconds until a mined node regrows


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
# Props: harvestable ResourceNodes (Stage 2). Trees/rocks used to be pure
# MultiMesh decoration; now they are individual ResourceNode instances so the
# player can chop/mine them. Budget is kept small (~45 per chunk) and nodes
# live only while their chunk is loaded, which bounds physics bodies.
# Zone-specific veins (copper/iron/obsidian/rare/sand/ice) spawn according to
# data/nodes.json "zone_nodes" weights.
# ---------------------------------------------------------------------------
func _build_scatter() -> void:
	var rng := GameState.make_rng(cx * 73856093 + cz * 19349663)
	var step := 6.0                       # scatter grid spacing
	var max_props := 45                   # node budget per chunk

	for iz in int(size / step):
		for ix in int(size / step):
			if _nodes.size() >= max_props:
				break
			var wx := position.x + ix * step + rng.randf_range(-2.2, 2.2)
			var wz := position.z + iz * step + rng.randf_range(-2.2, 2.2)
			var h := Terrain.get_height(wx, wz)
			if h < GameState.water_level + 0.8:
				continue                    # no props in the sea
			var slope := Terrain.get_normal(wx, wz).y
			if slope < 0.72:
				continue                    # too steep for anything
			var zone: Dictionary = GameState.get_zone_at(Vector3(wx, h, wz))
			var type_id := _pick_node_type(zone["id"], rng)
			_spawn_node(type_id, Vector3(wx, h, wz), zone, rng)


## Weighted pick between tree/rock and the zone's special nodes.
func _pick_node_type(zone_id: String, rng: RandomNumberGenerator) -> String:
	# Chance of a special zone node instead of plain tree/rock.
	var specials: Array = ItemDB.zone_nodes.get(zone_id, [])
	if not specials.is_empty() and rng.randf() < 0.30:
		var total := 0
		for entry in specials:
			total += int(entry[1])
		var roll := rng.randi_range(0, total - 1)
		for entry in specials:
			roll -= int(entry[1])
			if roll < 0:
				return String(entry[0])
	return "tree" if rng.randf() < 0.6 else "rock"


## Create one ResourceNode child; it is freed together with the chunk.
func _spawn_node(type_id: String, pos: Vector3, zone: Dictionary,
			rng: RandomNumberGenerator) -> void:
	var node := ResourceNode.new()
	node.respawn_time = respawn_time
	add_child(node)
	node.setup(type_id, pos, zone, rng)
	node.add_to_group("resource_node")
	_nodes.append(node)


var _nodes: Array[ResourceNode] = []

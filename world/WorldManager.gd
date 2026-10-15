## WorldManager.gd - Streams terrain chunks around the player.
##
## Keeps a (2*radius+1)^2 window of Chunk nodes centered on the player's chunk.
## Chunks outside the radius are freed; new ones are built one per frame so
## crossing a chunk border never causes a hitch. Water and clouds live here too
## because they must follow the camera around the infinite-ish map.
class_name WorldManager
extends Node3D

@export var load_radius: int = 2          # chunks kept loaded in each direction
@export var cloud_count: int = 14         # low-poly sphere clouds drifting overhead

var _chunks: Dictionary = {}              # Vector2i -> Chunk
var _player: Node3D = null
var _water: MeshInstance3D
var _water_mesh: PlaneMesh
var _t: float = 0.0


func _ready() -> void:
	_build_water()
	_build_clouds()


func _process(delta: float) -> void:
	_t += delta
	_update_water_wave()
	_update_clouds(delta)
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	if _player != null:
		# Keep water under the player so it visually extends to the horizon.
		_water.position.x = _player.global_position.x
		_water.position.z = _player.global_position.z
	_ensure_chunks()


# ---------------------------------------------------------------------------
# Chunk streaming
# ---------------------------------------------------------------------------
func _update_water_wave() -> void:
	# Gentle cartoon swell: bob the whole plane + tilt slightly. A shader-based
	# vertex wave is added in Stage 5 when ships need exact water heights.
	_water.position.y = GameState.water_level + sin(_t * 0.8) * 0.12


func _ensure_chunks() -> void:
	if _player == null:
		return
	var size := GameState.chunk_size
	var pc := Vector2i(floori(_player.global_position.x / size),
					   floori(_player.global_position.z / size))
	var wanted: Array[Vector2i] = []
	for dz in range(-load_radius, load_radius + 1):
		for dx in range(-load_radius, load_radius + 1):
			wanted.append(pc + Vector2i(dx, dz))

	# Free far chunks first.
	var to_free: Array[Vector2i] = []
	for key: Vector2i in _chunks.keys():
		if not key in wanted:
			to_free.append(key)
	for key in to_free:
		_chunks[key].queue_free()
		_chunks.erase(key)

	# Build at most one missing chunk per frame (spread cost).
	for c in wanted:
		if not _chunks.has(c):
			var ch := Chunk.new()
			add_child(ch)
			ch.setup(c.x, c.y, size)
			ch.build()
			_chunks[c] = ch
			break


# ---------------------------------------------------------------------------
# Water plane (flat translucent blue, follows the player)
# ---------------------------------------------------------------------------
func _build_water() -> void:
	_water_mesh = PlaneMesh.new()
	_water_mesh.size = Vector2(GameState.world_size * 1.6, GameState.world_size * 1.6)
	_water_mesh.subdivide_width = 0
	_water_mesh.subdivide_depth = 0
	_water = MeshInstance3D.new()
	_water.name = "Water"
	_water.mesh = _water_mesh
	_water.material_override = FlatStyle.mat_transparent(Color(0.15, 0.55, 0.90), 0.65)
	_water.position.y = GameState.water_level
	add_child(_water)



# ---------------------------------------------------------------------------
# Clouds: clusters of unshaded spheres that drift slowly and wrap around
# ---------------------------------------------------------------------------
var _clouds: Array[Node3D] = []


func _build_clouds() -> void:
	var rng := GameState.make_rng(4242)
	var sphere := SphereMesh.new()
	sphere.radius = 4.0
	sphere.height = 6.0
	for i in cloud_count:
		var cloud := Node3D.new()
		cloud.name = "Cloud%d" % i
		var puffs := rng.randi_range(3, 5)
		for p in puffs:
			var m := MeshInstance3D.new()
			m.mesh = sphere
			m.material_override = FlatStyle.mat(Color(1, 1, 1, 1))
			m.position = Vector3(p * 5.0 - puffs * 2.5, rng.randf_range(-1, 1),
				rng.randf_range(-3, 3))
			m.scale = Vector3.ONE * rng.randf_range(0.7, 1.5)
			cloud.add_child(m)
		cloud.position = Vector3(rng.randf_range(-300, 300), rng.randf_range(55, 85),
			rng.randf_range(-300, 300))
		add_child(cloud)
		_clouds.append(cloud)


func _update_clouds(delta: float) -> void:
	for c in _clouds:
		c.position.x += delta * 1.5            # lazy breeze
		if c.position.x > 320.0:
			c.position.x = -320.0

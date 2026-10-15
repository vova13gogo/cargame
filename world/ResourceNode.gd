## ResourceNode.gd - One minable world prop (Stage 2)
##
## Replaces the purely decorative per-chunk scatter for trees/rocks and adds
## zone-specific ore veins. Each node is a small Area3D (harvest hit detection)
## with a StaticBody3D collider so the player cannot walk through it, built
## from flat primitives in the owning zone's palette.
##
## Harvest rules:
##  - Player swings (LMB). Player raycasts to the nearest node in range.
##  - Node requires a tool tier from data/nodes.json; too-weak tools do nothing
##    but show a hint message.
##  - Each hit shrinks the node slightly; after `hits` hits it collapses,
##    drops resources into the inventory and respawns after a cooldown
##    (regrowth), so the world stays harvestable forever.
class_name ResourceNode
extends Node3D

@export var node_type: String = "rock"     # key into ItemDB.node_types
@export var respawn_time: float = 90.0     ## seconds until regrowth (-1 = never)

var _hits_left: int = 1
var _required_tier: int = 1
var _drop_id: String = ""
var _drop_amount: int = 1
var _base_scale := Vector3.ONE
var _body: StaticBody3D
var _visual: Node3D
var _dead := false


func setup(type_id: String, pos: Vector3, zone: Dictionary, rng: RandomNumberGenerator) -> void:
	node_type = type_id
	global_position = pos
	var def := ItemDB.node_def(type_id)
	_hits_left = int(def.get("hits", 3))
	_required_tier = int(def.get("tier", 1))
	_drop_id = def.get("drop", "stone")
	_drop_amount = int(def.get("amount", 1))
	name = "Node_%s" % type_id
	_build_visual(zone, rng)


# ---------------------------------------------------------------------------
# Flat-style visuals: every node type is 1-3 primitives, unshaded colors.
# ---------------------------------------------------------------------------
func _build_visual(zone: Dictionary, rng: RandomNumberGenerator) -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	match node_type:
		"tree":
			# Trunk capsule + blob canopy; pines (snow) get stacked cones.
			var s := rng.randf_range(0.8, 1.5)
			_base_scale = Vector3.ONE * s
			if zone["id"] == "snow":
				_add(SphereMesh.new(), Color(0.16, 0.16, 0.18), Vector3(0, 0.4, 0),
					Vector3(0.5, 0.35, 0.5))
				for i in 3:
					var cone := PrismMesh.new()
					cone.size = Vector3(2.4 - i * 0.6, 1.6, 2.4 - i * 0.6)
					_add_mesh(cone, zone["tree_color"], Vector3(0, 1.6 + i * 1.1, 0))
			elif zone["id"] == "desert":
				# Cactus: single fat cylinder with two stubby arms.
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.35; cyl.bottom_radius = 0.4; cyl.height = 2.6
				_add_mesh(cyl, zone["tree_color"], Vector3(0, 1.3, 0))
				for side in [-1.0, 1.0]:
					var arm := CylinderMesh.new()
					arm.top_radius = 0.16; arm.bottom_radius = 0.18; arm.height = 0.9
					var m := _add_mesh(arm, zone["tree_color"],
						Vector3(0.5 * side, 1.5, 0))
					m.rotation_degrees = Vector3(0, 0, 60 * side)
			elif zone["id"] == "volcano":
				# Dead tree: bare trunk + one crooked branch.
				_add(CapsuleMesh.new(), zone["trunk_color"], Vector3(0, 1.2, 0),
					Vector3(0.5, 1.1, 0.5))
				var cap := SphereMesh.new()
				_add_mesh(cap, zone["trunk_color"], Vector3(0.7, 2.1, 0))
			else:
				# Plains/ocean palm-ish round tree.
				var tr := CapsuleMesh.new()
				tr.radius = 0.28; tr.height = 2.2
				_add_mesh(tr, zone["trunk_color"], Vector3(0, 1.1, 0))
				var leaf := SphereMesh.new()
				leaf.radius = 1.4; leaf.height = 2.4
				_add_mesh(leaf, zone["tree_color"], Vector3(0, 2.9, 0))
			# Random size is baked into the visual scale; _base_scale stays unit
			# so the hit-shrink animation lerps from the *spawned* size to zero.
			_visual.scale = Vector3.ONE * s
			_base_scale = _visual.scale
		"sand_pile":
			var mound := SphereMesh.new()
			mound.radius = 0.9; mound.height = 1.0
			_add_mesh(mound, zone["ground_color"].lightened(0.08), Vector3(0, 0.15, 0),
				Vector3(1.2, 0.5, 1.2))
		"ice_shard":
			var shard := PrismMesh.new()
			shard.size = Vector3(0.9, 1.8, 0.9)
			var m := _add_mesh(shard, Color(0.75, 0.9, 1.0, 0.9), Vector3(0, 0.9, 0))
			m.rotation_degrees = Vector3(8, rng.randf_range(0, 360), 6)
			var small := PrismMesh.new()
			small.size = Vector3(0.5, 1.0, 0.5)
			var m2 := _add_mesh(small, Color(0.85, 0.95, 1.0, 0.9), Vector3(0.6, 0.5, 0.3))
			m2.rotation_degrees = Vector3(-10, rng.randf_range(0, 360), 14)
		"rock", "copper_vein", "iron_vein", "obsidian_vein", "rare_vein":
			# Base boulder plus colored ore blobs sticking out for veins.
			var r := rng.randf_range(0.6, 1.2)
			_base_scale = Vector3.ONE * r
			var rock_mesh := SphereMesh.new()
			rock_mesh.radius = 0.9; rock_mesh.height = 1.0
			var rm := _add_mesh(rock_mesh, zone["rock_color"], Vector3(0, r * 0.3, 0),
				Vector3(r, r * 0.8, r))
			rm.rotation_degrees = Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0, 360), 0)
			if node_type != "rock":
				# Ore blobs glow faintly so veins read at a distance (cheerful, not realistic).
				var ore_col := ItemDB.item_color(_drop_id)
				for i in 3:
					var blob := SphereMesh.new()
					blob.radius = 0.22; blob.height = 0.4
					var ang := rng.randf_range(0, TAU)
					var m := MeshInstance3D.new()
					m.mesh = blob
					m.material_override = FlatStyle.mat_glow(ore_col)
					m.position = Vector3(cos(ang) * 0.55 * r,
						rng.randf_range(0.3, 1.0) * r, sin(ang) * 0.55 * r)
					m.scale = Vector3.ONE * r
					_visual.add_child(m)

	_build_collision()


func _add(mesh_cls: Mesh, color: Color, pos: Vector3, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	return _add_mesh(mesh_cls, color, pos, scl)


func _add_mesh(mesh: Mesh, color: Color, pos: Vector3, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = FlatStyle.mat(color)
	mi.position = pos
	mi.scale = scl
	_visual.add_child(mi)
	return mi


## Solid collider so you can't walk through; sized to the visual roughly.
func _build_collision() -> void:
	_body = StaticBody3D.new()
	_body.name = "Body"
	add_child(_body)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var tall := 2.6 if node_type == "tree" else 1.2
	shape.size = Vector3(1.4, tall, 1.4) * _base_scale.x
	col.shape = shape
	col.position = Vector3(0, tall * 0.5 * _base_scale.x, 0)
	_body.add_child(col)


# ---------------------------------------------------------------------------
# Harvesting API (called by Player._try_harvest)
# ---------------------------------------------------------------------------
func can_be_mined_with(tier: int) -> bool:
	return tier >= _required_tier


func required_tier() -> int:
	return _required_tier


func drop_item_id() -> String:
	return _drop_id


## Apply one hit. Returns {"done": bool, "got": int} - got>0 only on final hit.
func hit() -> Dictionary:
	if _dead:
		return {"done": true, "got": 0}
	_hits_left -= 1
	# Squash/shrink feedback: cartoonish "melt" toward the ground each hit.
	var frac := clampf(float(_hits_left) / float(maxi(ItemDB.node_def(node_type).get("hits", 3), 1)), 0.0, 1.0)
	_visual.scale = _base_scale.lerp(Vector3(0.05, 0.05, 0.05), 1.0 - frac)
	if _hits_left <= 0:
		_kill_node()
		return {"done": true, "got": _drop_amount}
	return {"done": false, "got": 0}


func _kill_node() -> void:
	_dead = true
	_visual.visible = false
	if _body != null and is_instance_valid(_body):
		_body.queue_free()   # frees the CollisionShape3D child too, instantly disabling it
		_body = null
	if respawn_time > 0.0:
		get_tree().create_timer(respawn_time).timeout.connect(_respawn)
	else:
		queue_free()


func _respawn() -> void:
	if not is_inside_tree():
		return
	_hits_left = int(ItemDB.node_def(node_type).get("hits", 3))
	_dead = false
	_visual.visible = true
	_visual.scale = _base_scale
	# Re-add collision (the old body was freed).
	_build_collision()

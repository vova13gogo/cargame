## DayNightManager.gd - Autoload singleton (Stage 1)
##
## Drives a simple, color-based day/night cycle: no HDR sky textures, just a
## procedural Sky with a flat-colored ShaderMaterial-like look achieved by
## tweening the background color of a RadianceEmptySky... Actually Godot 4's
## ProceduralSkyMaterial already gives us a soft two-color gradient (top/sky
## horizon), which is exactly the "flat gradient" style we want.
##
## The manager owns:
##  - time_of_day: 0.0 = midnight .. 0.5 = noon .. 1.0 = midnight
##  - a DirectionalLight3D (sun) that it rotates and recolors
##  - WorldEnvironment sky colors blended between dawn/day/dusk/night palettes
##  - the current zone tint (mixed in from GameState so zones feel different)
extends Node

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------
@export var day_length_seconds: float = 240.0   ## One full day/night cycle
@export var fast_forward_multiplier: float = 8.0 ## While T is held
@export var sun_light: DirectionalLight3D       ## Assigned at runtime by Main
@export var world_env: WorldEnvironment         ## Assigned at runtime by Main

signal time_updated(hour: float)  # 0..24, used by HUD clock

var time_of_day: float = 0.32     # start mid-morning for a cheerful intro
var _sky_mat: ProceduralSkyMaterial

# Palette keyframes: [t, sky_top, sky_horizon, ground_horizon, sun_color, energy]
const CYCLE_KEYS := [
	{"t": 0.00, "top": Color(0.05, 0.07, 0.20), "hor": Color(0.12, 0.14, 0.30), "sun": Color(0.45, 0.55, 0.90), "energy": 0.10},
	{"t": 0.22, "top": Color(0.16, 0.20, 0.45), "hor": Color(0.95, 0.55, 0.35), "sun": Color(1.00, 0.60, 0.35), "energy": 0.55},
	{"t": 0.28, "top": Color(0.45, 0.70, 0.95), "hor": Color(1.00, 0.80, 0.55), "sun": Color(1.00, 0.85, 0.60), "energy": 1.00},
	{"t": 0.50, "top": Color(0.40, 0.75, 0.98), "hor": Color(0.75, 0.90, 1.00), "sun": Color(1.00, 0.98, 0.88), "energy": 1.25},
	{"t": 0.72, "top": Color(0.45, 0.70, 0.95), "hor": Color(1.00, 0.80, 0.55), "sun": Color(1.00, 0.85, 0.60), "energy": 1.00},
	{"t": 0.78, "top": Color(0.25, 0.25, 0.55), "hor": Color(0.98, 0.45, 0.30), "sun": Color(1.00, 0.50, 0.30), "energy": 0.55},
	{"t": 1.00, "top": Color(0.05, 0.07, 0.20), "hor": Color(0.12, 0.14, 0.30), "sun": Color(0.45, 0.55, 0.90), "energy": 0.10},
]


func _ready() -> void:
	_setup_sky()


## Build a ProceduralSky (flat gradient, no sun disc glow needed) and hand it
## to the WorldEnvironment created by Main.tscn.
func _setup_sky() -> void:
	if world_env == null or world_env.environment == null:
		return
	var sky := Sky.new()
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sky_top_color = CYCLE_KEYS[3]["top"]
	_sky_mat.sky_horizon_color = CYCLE_KEYS[3]["hor"]
	_sky_mat.ground_bottom_color = Color(0.25, 0.25, 0.30)
	_sky_mat.ground_horizon_color = CYCLE_KEYS[3]["hor"]
	sky.sky_material = _sky_mat
	world_env.environment.background_mode = Environment.BG_SKY
	world_env.environment.sky = sky
	world_env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	world_env.environment.ambient_light_energy = 0.6


func _process(delta: float) -> void:
	var mult := fast_forward_multiplier if Input.is_action_pressed("time_fast_forward") else 1.0
	time_of_day += delta * mult / day_length_seconds
	time_of_day = fmod(time_of_day, 1.0)
	_apply_cycle()
	time_updated.emit(time_of_day * 24.0)


## Interpolate between palette keyframes and push values to sun + sky.
func _apply_cycle() -> void:
	# find surrounding keyframes
	var a: Dictionary = CYCLE_KEYS[0]
	var b: Dictionary = CYCLE_KEYS[1]
	for i in CYCLE_KEYS.size() - 1:
		if time_of_day >= CYCLE_KEYS[i]["t"] and time_of_day <= CYCLE_KEYS[i + 1]["t"]:
			a = CYCLE_KEYS[i]
			b = CYCLE_KEYS[i + 1]
			break
	var span: float = maxf(b["t"] - a["t"], 0.0001)
	var f: float = clampf((time_of_day - a["t"]) / span, 0.0, 1.0)

	var top: Color = a["top"].lerp(b["top"], f)
	var hor: Color = a["hor"].lerp(b["hor"], f)
	var sun_col: Color = a["sun"].lerp(b["sun"], f)
	var energy: float = lerpf(a["energy"], b["energy"], f)

	# Blend the local zone ambient tint over the time-of-day sky color so each
	# zone feels different even under the same sun (subtle, 20% mix).
	var zone: Dictionary = GameState.get_zone_at(_player_pos())
	var tint: Color = zone["ambient"]
	top = top.lerp(tint, 0.2)
	hor = hor.lerp(tint, 0.2)

	if _sky_mat != null:
		_sky_mat.sky_top_color = top
		_sky_mat.sky_horizon_color = hor
		_sky_mat.ground_horizon_color = hor
	if world_env != null and world_env.environment != null:
		world_env.environment.ambient_light_energy = 0.35 + energy * 0.35

	if sun_light != null:
		# Sun orbit: pitch from -20deg at midnight to +60deg at noon, plus a
		# slow yaw so light direction drifts east->west over the day.
		var pitch := -20.0 + 80.0 * maxf(0.0, sin(time_of_day * TAU - PI * 0.5) * 0.5 + 0.5)
		var yaw := time_of_day * 180.0
		sun_light.rotation_degrees = Vector3(-pitch, yaw, 0.0)
		sun_light.light_color = sun_col
		sun_light.light_energy = maxf(energy, 0.05)


func _player_pos() -> Vector3:
	var p := get_tree().get_first_node_in_group("player")
	return p.global_position if p else Vector3.ZERO

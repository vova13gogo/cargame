## HUD.gd - Minimal flat HUD for Stage 1 (CanvasLayer built entirely in code).
##
## Shows: current zone name, clock + day/night indicator, controls hint and a
## simple compass strip pointing north. Later stages add health, resources,
## disaster timer and quest markers to this same layer.
class_name HUD
extends CanvasLayer

var _zone_label: Label
var _clock_label: Label
var _compass_label: Label
var _player: Node3D = null


func _ready() -> void:
	layer = 10
	_build_ui()
	DayNightManager.time_updated.connect(_on_time_updated)


func _process(_delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	if _player != null:
		_zone_label.text = GameState.zone_name_at(_player.global_position)
		# Compass: player's facing yaw -> cardinal letter.
		var yaw := fmod(_player.rotation.y, TAU)
		var deg := rad_to_deg(yaw)
		_compass_label.text = "Compass: " + _cardinal(deg)


func _cardinal(deg: float) -> String:
	# Godot: -Z is north when yaw=0; rotation.y positive turns left (towards W).
	var d := fposmod(-deg + 360.0, 360.0)
	var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return names[int((d + 22.5) / 45.0) % 8]


func _on_time_updated(hour: float) -> void:
	var h := int(hour)
	var m := int(fmod(hour, 1.0) * 60.0)
	var icon := "Sun" if (h >= 6 and h < 19) else "Moon"
	_clock_label.text = "%02d:%02d  (%s)" % [h, m, icon]


# ---------------------------------------------------------------------------
# UI construction: flat rounded panels via StyleBoxFlat, one default font.
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	var root := Control.new()
	root.name = "HUDRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- top-left: zone name --------------------------------------------------
	_zone_label = _make_label(Vector2(24, 18), Vector2(360, 44), 26)
	_zone_label.add_theme_color_override("font_color", Color(1, 1, 1))
	root.add_child(_wrap_panel(_zone_label, Vector2(16, 10), Vector2(380, 60)))

	# --- top-right: clock ------------------------------------------------------
	_clock_label = _make_label(Vector2(0, 0), Vector2(220, 40), 24)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var clock_panel := _wrap_panel(_clock_label, Vector2(0, 0), Vector2(240, 56))
	clock_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	clock_panel.offset_left = -260
	clock_panel.offset_right = -20
	clock_panel.offset_top = 16
	clock_panel.offset_bottom = 72
	root.add_child(clock_panel)

	# --- bottom-center: compass + hints ---------------------------------------
	_compass_label = _make_label(Vector2(0, 0), Vector2(420, 36), 20)
	_compass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hint := _make_label(Vector2(0, 38), Vector2(620, 30), 16)
	hint.text = "WASD move | Shift sprint | Space jump | C camera | T fast-forward time"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	var bottom := _wrap_panel(hint, Vector2(-10, -4), Vector2(640, 92))
	bottom.add_child(_compass_label)
	_compass_label.position = Vector2(110, 4)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.offset_left = 320
	bottom.offset_top = -110
	root.add_child(bottom)


func _make_label(pos: Vector2, size: Vector2, font_size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = size
	l.add_theme_font_size_override("font_size", font_size)
	return l


## Wrap a control into a rounded translucent panel (flat UI style).
func _wrap_panel(inner: Control, inner_pos: Vector2, panel_size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.size = panel_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.16, 0.25, 0.55)     # dark soft glassy plate
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	panel.add_theme_stylebox_override("panel", sb)
	inner.position = inner_pos
	panel.add_child(inner)
	return panel

## InventoryPanel.gd - Flat inventory + crafting UI (Stage 2)
##
## Built entirely in code (no .tscn). Toggled with I. Shows:
##  - a grid of item slots with count labels and primitive "icons"
##  - the selected slot highlighted; clicking a slot selects it
##  - a crafting list from ItemDB.recipes: shows cost, greys out unaffordable
##    recipes, crafts on click (e.g. upgrade pickaxes from gathered ore).
## Also draws the always-visible hotbar (first 9 slots) at the bottom.
class_name InventoryPanel
extends CanvasLayer

const SLOT_SIZE := 64.0
const SLOT_GAP := 8.0

var _root: Control
var _panel: Panel
var _grid: GridContainer
var _slot_nodes: Array[Panel] = []
var _craft_rows: Dictionary = {}     # recipe result id -> row container
var _visible_now := false


func _ready() -> void:
	layer = 12
	_build_ui()
	refresh()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		toggle()


func toggle() -> void:
	_visible_now = not _visible_now
	_panel.visible = _visible_now
	if _visible_now:
		# Release the mouse so slots can be clicked; re-capture when closing.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	refresh()


func refresh() -> void:
	if GameState.inventory == null:
		return
	_fill_grid()
	_fill_crafting()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# --- center panel ---------------------------------------------------------
	_panel = Panel.new()
	_panel.name = "InventoryPanel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.16, 0.25, 0.92)
	sb.corner_radius_top_left = sb.corner_radius_top_right = 18
	sb.corner_radius_bottom_left = sb.corner_radius_bottom_right = 18
	sb.content_margin_left = sb.content_margin_right = 24.0
	sb.content_margin_top = sb.content_margin_bottom = 20.0
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.size = Vector2(760, 460)
	_panel.position = Vector2(260, 130)
	_panel.visible = false
	_root.add_child(_panel)

	var title := Label.new()
	title.text = "Backpack & Workbench (I closes)"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	title.position = Vector2(24, 14)
	_panel.add_child(title)

	# Left column: slot grid.
	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", int(SLOT_GAP))
	_grid.add_theme_constant_override("v_separation", int(SLOT_GAP))
	_grid.position = Vector2(24, 60)
	_panel.add_child(_grid)
	for i in GameState_slot_count():
		var slot := _make_slot(i)
		_grid.add_child(slot)

	# Right column: crafting.
	var craft_title := Label.new()
	craft_title.text = "Crafting"
	craft_title.add_theme_font_size_override("font_size", 22)
	craft_title.position = Vector2(470, 56)
	_panel.add_child(craft_title)

	var craft_box := VBoxContainer.new()
	craft_box.name = "CraftBox"
	craft_box.add_theme_constant_override("separation", 10)
	craft_box.position = Vector2(470, 92)
	craft_box.size = Vector2(260, 340)
	_panel.add_child(craft_box)


func GameState_slot_count() -> int:
	return 24   # matches Inventory.slot_count default


func _make_slot(index: int) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.25, 0.36, 0.9)
	sb.corner_radius_top_left = sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = sb.corner_radius_bottom_right = 10
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_STOP

	var count := Label.new()
	count.name = "Count"
	count.position = Vector2(4, SLOT_SIZE - 22)
	count.add_theme_font_size_override("font_size", 15)
	count.add_theme_color_override("font_color", Color(1, 1, 1))
	p.add_child(count)

	var icon := ColorRect.new()
	icon.name = "Icon"
	icon.color = Color(0, 0, 0, 0)
	icon.position = Vector2(14, 12)
	icon.size = Vector2(36, 36)
	p.add_child(icon)

	var pressed := Button.new()
	pressed.name = "Click"
	pressed.flat = true
	pressed.focus_mode = Control.FOCUS_NONE
	pressed.position = Vector2.ZERO
	pressed.size = Vector2(SLOT_SIZE, SLOT_SIZE)
	pressed.pressed.connect(_on_slot_clicked.bind(index))
	p.add_child(pressed)

	_slot_nodes.append(p)
	return p


func _on_slot_clicked(index: int) -> void:
	GameState.inventory.selected_index = index
	refresh()


# ---------------------------------------------------------------------------
# Data -> widgets
# ---------------------------------------------------------------------------
func _fill_grid() -> void:
	var inv: Inventory = GameState.inventory
	for i in _slot_nodes.size():
		var p: Panel = _slot_nodes[i]
		var icon: ColorRect = p.get_node("Icon")
		var count: Label = p.get_node("Count")
		var s: Dictionary = inv.slots[i] if i < inv.slots.size() else {}
		if s.is_empty():
			icon.color = Color(0, 0, 0, 0)
			count.text = ""
		else:
			icon.color = ItemDB.item_color(s["id"])
			count.text = str(s["count"]) if s["count"] > 1 else ""
		# Selection highlight.
		var sb := p.get_theme_stylebox("panel").duplicate()
		sb.bg_color = Color(0.95, 0.75, 0.3, 0.95) if i == inv.selected_index \
			else Color(0.2, 0.25, 0.36, 0.9)
		p.add_theme_stylebox_override("panel", sb)


func _fill_crafting() -> void:
	var inv: Inventory = GameState.inventory
	var box := _panel.get_node_or_null("CraftBox")
	if box == null:
		return
	for c in box.get_children():
		box.remove_child(c)     # rebuild rows each refresh (children stay queued)
		c.queue_free()

	for result_id in ItemDB.recipes.keys():
		var recipe: Dictionary = ItemDB.recipes[result_id]
		var cost: Dictionary = recipe.get("cost", {})
		var affordable := inv.has_items(cost)

		var row := Panel.new()
		var rsb := StyleBoxFlat.new()
		rsb.bg_color = Color(0.16, 0.2, 0.3, 0.9)
		rsb.corner_radius_top_left = rsb.corner_radius_top_right = 10
		rsb.corner_radius_bottom_left = rsb.corner_radius_bottom_right = 10
		rsb.content_margin_left = rsb.content_margin_right = 10
		rsb.content_margin_top = rsb.content_margin_bottom = 8
		row.add_theme_stylebox_override("panel", rsb)
		row.custom_minimum_size = Vector2(260, 74)
		box.add_child(row)

		var lbl := Label.new()
		lbl.text = "%s\n%s" % [ItemDB.item_name(result_id), _cost_text(cost)]
		lbl.add_theme_font_size_override("font_size", 15)
		lbl.add_theme_color_override("font_color",
			Color(1, 1, 1) if affordable else Color(1, 1, 1, 0.45))
		lbl.position = Vector2(10, 6)
		row.add_child(lbl)

		var btn := Button.new()
		btn.text = "Make"
		btn.disabled = not affordable
		btn.focus_mode = Control.FOCUS_NONE
		btn.position = Vector2(186, 22)
		btn.size = Vector2(64, 32)
		btn.pressed.connect(_on_craft.bind(result_id, cost))
		row.add_child(btn)


func _cost_text(cost: Dictionary) -> String:
	var parts := []
	for id in cost:
		parts.append("%d %s" % [cost[id], ItemDB.item_name(id)])
	return ", ".join(parts)


func _on_craft(result_id: String, cost: Dictionary) -> void:
	var inv: Inventory = GameState.inventory
	if inv.pay_cost(cost):
		var added := inv.add_item(result_id, 1)
		if added > 0:
			GameState.toast("Crafted %s!" % ItemDB.item_name(result_id))
		else:
			GameState.toast("No free slot for %s!" % ItemDB.item_name(result_id))
	refresh()

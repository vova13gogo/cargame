## Inventory.gd - Stack-based inventory model (Stage 2)
##
## Plain data container (RefCounted): a fixed number of slots, each holding
## {id, count}. Tools are single-count items that occupy one slot each.
## Emits signals so the HUD / inventory panel can react without polling.
## No visual nodes here - UI reads this model.
class_name Inventory
extends RefCounted

signal inventory_changed

@export var slot_count: int = 24

var slots: Array[Dictionary] = []   # each: {"id": String, "count": int}


func _init() -> void:
	slots.resize(slot_count)
	for i in slot_count:
		slots[i] = {}


# ---------------------------------------------------------------------------
# Adding / removing
# ---------------------------------------------------------------------------

## Add `count` of item id. Respects max stacks; overflow is dropped (returns
## the number actually added). Stacks existing slots first, then free slots.
func add_item(id: String, count: int = 1) -> int:
	if count <= 0 or not ItemDB.items.has(id):
		return 0
	var maxc := ItemDB.max_stack(id)
	var added := 0

	if ItemDB.is_tool(id):
		# Tools never stack: one per free slot.
		for i in slot_count:
			if slots[i].is_empty() and added < count:
				slots[i] = {"id": id, "count": 1}
				added += 1
	else:
		# Top up partial stacks...
		for i in slot_count:
			if added >= count:
				break
			var s: Dictionary = slots[i]
			if s.get("id", "") == id and s["count"] < maxc:
				var room := maxc - s["count"]
				var take := mini(room, count - added)
				s["count"] += take
				added += take
		# ...then fill empty slots.
		for i in slot_count:
			if added >= count:
				break
			if slots[i].is_empty():
				var take := mini(maxc, count - added)
				slots[i] = {"id": id, "count": take}
				added += take

	if added > 0:
		inventory_changed.emit()
	return added


## Remove `count` of item id spread over stacks. Returns true if enough was there.
func remove_item(id: String, count: int = 1) -> bool:
	if count_of(id) < count:
		return false
	var remaining := count
	for i in slot_count:
		if remaining <= 0:
			break
		var s: Dictionary = slots[i]
		if s.get("id", "") == id:
			var take := mini(remaining, s["count"])
			s["count"] -= take
			remaining -= take
			if s["count"] <= 0:
				slots[i] = {}
	inventory_changed.emit()
	return true


func count_of(id: String) -> int:
	var total := 0
	for s in slots:
		if s.get("id", "") == id:
			total += s["count"]
	return total


func has_items(cost: Dictionary) -> bool:
	for id in cost:
		if count_of(id) < int(cost[id]):
			return false
	return true


## Pay a crafting cost dict like {"wood": 5, "stone": 5}. Fails atomically.
func pay_cost(cost: Dictionary) -> bool:
	if not has_items(cost):
		return false
	for id in cost:
		remove_item(id, int(cost[id]))
	return true


# ---------------------------------------------------------------------------
# Hotbar / selection (slot index based)
# ---------------------------------------------------------------------------
var selected_index: int = 0 : set = _set_selected

func _set_selected(v: int) -> void:
	selected_index = clampi(v, 0, slot_count - 1)
	inventory_changed.emit()


func selected_id() -> String:
	return slots[selected_index].get("id", "")


func selected_tool_tier() -> int:
	var id := selected_id()
	return ItemDB.tool_tier(id) if ItemDB.is_tool(id) else 0


# ---------------------------------------------------------------------------
# Serialization (used by SaveSystem in Stage 10 already compatible now)
# ---------------------------------------------------------------------------
func to_dict() -> Dictionary:
	var arr := []
	for s in slots:
		arr.append(s.duplicate())
	return {"slots": arr, "selected": selected_index}


func from_dict(d: Dictionary) -> void:
	for i in slot_count:
		slots[i] = {}
	var arr: Array = d.get("slots", [])
	for i in mini(arr.size(), slot_count):
		var s: Dictionary = arr[i]
		if typeof(s) == TYPE_DICTIONARY and s.has("id"):
			slots[i] = {"id": String(s["id"]), "count": int(s.get("count", 1))}
	selected_index = clampi(int(d.get("selected", 0)), 0, slot_count - 1)
	inventory_changed.emit()

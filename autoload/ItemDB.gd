## ItemDB.gd - Autoload singleton (Stage 2)
##
## Loads the JSON item/node databases from res://data/ at startup so all game
## content (items, tool tiers, crafting recipes, harvestable node types) lives
## in editable data files instead of hardcoded scripts. Provides typed accessors
## with safe fallbacks so a malformed JSON never crashes the game.
extends Node

var items: Dictionary = {}        # id -> item definition
var tools: Array = []             # ordered list of tool ids (default slot order)
var recipes: Dictionary = {}      # result id -> {"cost": {...}, "desc": String}
var node_types: Dictionary = {}   # node type id -> drop/hits/tier definition
var zone_nodes: Dictionary = {}   # zone id -> [[node_type, weight], ...]


func _ready() -> void:
	var data := _load_json("res://data/items.json")
	items = data.get("items", {})
	tools = data.get("tools", ["pickaxe_wood"])
	recipes = data.get("recipes", {})

	var nd := _load_json("res://data/nodes.json")
	node_types = nd.get("node_types", {})
	zone_nodes = nd.get("zone_nodes", {})

	# --- sanity fallbacks: the game must run even if a data file is missing ---
	if items.is_empty():
		push_warning("ItemDB: items.json empty/missing, using built-in defaults.")
		items = {
			"wood": {"name": "Wood", "type": "resource", "color": "#8a5a30", "max_stack": 999},
			"stone": {"name": "Stone", "type": "resource", "color": "#9aa0a8", "max_stack": 999},
			"pickaxe_wood": {"name": "Wooden Pickaxe", "type": "tool", "tier": 1, "color": "#b07a45"},
		}
	if node_types.is_empty():
		push_warning("ItemDB: nodes.json empty/missing, using built-in defaults.")
		node_types = {
			"tree": {"drop": "wood", "amount": 4, "hits": 3, "tier": 1},
			"rock": {"drop": "stone", "amount": 3, "hits": 3, "tier": 1},
		}


## Parse a JSON file into a Dictionary; returns {} on any error.
func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("ItemDB: missing data file %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var txt := f.get_as_text()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("ItemDB: bad JSON in %s" % path)
		return {}
	return parsed


# ---------------------------------------------------------------------------
# Typed accessors
# ---------------------------------------------------------------------------
func item_name(id: String) -> String:
	return items.get(id, {}).get("name", id)


func item_color(id: String) -> Color:
	var hex: String = items.get(id, {}).get("color", "#ffffff")
	return Color(hex) if hex.begins_with("#") else Color.WHITE


func item_type(id: String) -> String:
	return items.get(id, {}).get("type", "resource")


func max_stack(id: String) -> int:
	return int(items.get(id, {}).get("max_stack", 99))


func tool_tier(id: String) -> int:
	return int(items.get(id, {}).get("tier", 0))


func is_tool(id: String) -> bool:
	return item_type(id) == "tool"


func recipe_for(result_id: String) -> Dictionary:
	return recipes.get(result_id, {})


func node_def(type_id: String) -> Dictionary:
	return node_types.get(type_id, {})

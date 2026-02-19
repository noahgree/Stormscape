extends Node
## The autoload responsible for caching all items in the game. Provides methods for said access.

var cached_items: Dictionary[StringName, ItemStats] = {} ## All items keyed by their unique item id.
var item_to_recipes: Dictionary[StringName, Array] = {} ## Maps items to the list of recipes that include them.
var tag_to_recipes: Dictionary[StringName, Array] = {} ## Maps tags to the list of recipes that include them.
var tag_to_items: Dictionary[StringName, Array] = {} ## Maps tags to the list of items that have that tag.


func _ready() -> void:
	_cache_recipes(Globals.item_dir)

## This caches the items by their recipe ID at the start of the game.
func _cache_recipes(folder: String) -> void:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		push_error("Items cacher couldn't open the folder: " + folder)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()

	while file_name != "":
		if dir.current_is_dir():
			if file_name != "." and file_name != "..":
				_cache_recipes(folder + "/" + file_name)
		elif file_name.ends_with(".tres"):
			var file_path: String = folder + "/" + file_name
			var item_resource: ItemStats = load(file_path)
			cached_items[item_resource.get_cache_key()] = item_resource

			for tag: StringName in item_resource.tags:
				if not tag_to_items.has(tag):
					tag_to_items[tag] = []
				tag_to_items[tag].append(item_resource)

			for ingredient: CraftingIngredient in item_resource.recipe:
				if ingredient.type == CraftingIngredient.Type.ITEM:
					if ingredient.stats == null:
						push_error(item_resource.get_cache_key() + " has a recipe with an ingredient that is missing a stats definition.")
						continue
					var ingredient_recipe_id: StringName = ingredient.stats.get_cache_key()
					if ingredient_recipe_id not in item_to_recipes:
						item_to_recipes[ingredient_recipe_id] = []
					item_to_recipes[ingredient_recipe_id].append(item_resource.get_cache_key())
				elif ingredient.type == CraftingIngredient.Type.TAGS:
					for tag: StringName in ingredient.tags:
						if tag not in tag_to_recipes:
							tag_to_recipes[tag] = []
						tag_to_recipes[tag].append(item_resource.get_cache_key())
		file_name = dir.get_next()
	dir.list_dir_end()

## Gets and returns an item resource by its id.
func get_item_by_id(item_cache_id: StringName, block_error_messages: bool = false) -> ItemStats:
	var item_resource: ItemStats = cached_items.get(item_cache_id, null)
	if item_resource == null and not block_error_messages:
		push_error("The Items cacher did not have \"" + item_cache_id + "\" in its cache.")
	return item_resource

## Gets a dictionary of all item mods, keyed by item id. Note that this is not a copy, it directly references
## the original items in the cache.
func get_all_wpn_mods() -> Dictionary[StringName, WeaponModStats]:
	var results: Dictionary[StringName, WeaponModStats]
	for item_id: StringName in cached_items:
		var item: ItemStats = cached_items[item_id]
		if item is WeaponModStats:
			results[item_id] = item
	return results

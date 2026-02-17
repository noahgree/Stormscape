extends CenterContainer
class_name CraftingManager
## Manages crafting actions like checking and caching recipes, consuming ingredients, and
## granting successful crafts.

@onready var output_slot: CraftingSlot = %OutputSlot ## The slot where the result will appear in.
@onready var input_slots_container: GridContainer = %InputSlots ## The container holding the input slots as children.
@onready var crafting_down_arrow: TextureRect = %CraftingDownArrow ## The arrow symbol.
@onready var craft_btn_margins: MarginContainer = %CraftBtnMargins ## The container for the entire craft button.
@onready var craft_btn: Button = %CraftBtn ## The button to press when attempting a craft.

var can_output: bool = false ## When true, there is an outputtable item in the output slot from a valid recipe.
var input_slots: Array[CraftingSlot] = [] ## The slots that are used as inputs to craft.
var is_crafting: bool = false ## When true, we shouldn't update the output slot since a craft is in progress.
var item_details_panel: ItemDetailsPanel ## The item viewer panel that shows item details.


func _ready() -> void:
	_on_output_slot_output_changed(false)
	output_slot.output_changed.connect(_on_output_slot_output_changed)
	SignalBus.ui_focus_closed.connect(_on_ui_focus_closed)

func setup_slots_and_signals(inventory_ui: PlayerInvUI) -> void:
	_setup_crafting_input_slots(inventory_ui)
	_setup_crafting_output_slot(inventory_ui)
	_setup_item_viewer_signals(inventory_ui)

## Sets up the input slots with their needed data.
func _setup_crafting_input_slots(inventory_ui: PlayerInvUI) -> void:
	for input_slot: CraftingSlot in input_slots_container.get_children():
		input_slot.name = "Input_Slot_" + str(inventory_ui.index_counter)
		input_slot.synced_inv = inventory_ui.synced_inv_src_node.inv
		input_slot.index = inventory_ui.assign_next_slot_index()
		input_slot.item_changed.connect(_on_input_item_changed)
		input_slots.append(input_slot)

## Sets up the crafting output slot with its needed data.
func _setup_crafting_output_slot(inventory_ui: PlayerInvUI) -> void:
	output_slot.name = "Output_Slot"
	output_slot.synced_inv = inventory_ui.synced_inv_src_node.inv
	output_slot.index = inventory_ui.assign_next_slot_index()

## Sets up the item viewer node reference and the signals needed to respond to changes.
func _setup_item_viewer_signals(inventory_ui: PlayerInvUI) -> void:
	item_details_panel = inventory_ui.item_details_panel
	item_details_panel.item_viewer_slot.item_changed.connect(_on_viewed_item_changed)

## Shows or hides the main craft button depending on whether a valid output is present.
func _on_output_slot_output_changed(is_craftable: bool) -> void:
	can_output = is_craftable
	if is_craftable:
		craft_btn_margins.modulate = Color.WHITE
		craft_btn_margins.modulate.a = 1.0
		craft_btn.disabled = false
		crafting_down_arrow.modulate.a = 0.65
	else:
		craft_btn_margins.modulate = Color.LIGHT_GRAY
		craft_btn_margins.modulate.a = 0.5
		craft_btn.disabled = true
		crafting_down_arrow.modulate.a = 0.2

## This processes the items in the input slots so that they can be worked with faster by
## the other crafting functions.
func _preprocess_input_items(use_cache_id_in_keys: bool) -> Dictionary[StringName, Dictionary]:
	var item_quantities: Dictionary[StringName, Array] = {}
	var tag_quantities: Dictionary[StringName, Array] = {}

	for slot: CraftingSlot in input_slots:
		if slot.item == null:
			continue

		var inv_item: InvItemResource = slot.item
		var item_id: StringName = inv_item.stats.id if not use_cache_id_in_keys else inv_item.stats.get_cache_key()

		if item_id in item_quantities:
			item_quantities[item_id].append([inv_item.quantity, inv_item.stats.rarity])
		else:
			item_quantities[item_id] = [[inv_item.quantity, inv_item.stats.rarity]]

		for tag: StringName in inv_item.stats.tags:
			if tag in tag_quantities:
				tag_quantities[tag].append([inv_item.quantity, inv_item.stats.rarity])
			else:
				tag_quantities[tag] = [[inv_item.quantity, inv_item.stats.rarity]]

	return {&"items": item_quantities, &"tags": tag_quantities}

## This checks to see if a passed-in item is craftable based on what we have in our input slots.
func _is_item_craftable(item: ItemResource) -> bool:
	var recipe: Array[CraftingIngredient] = item.recipe
	var quantities: Dictionary[StringName, Dictionary] = _preprocess_input_items(false) # Use item ids as keys, not item cache ids. We we will check rarity conditions down below on our own.
	var item_quantities: Dictionary[StringName, Array] = quantities.items
	var tag_quantities: Dictionary[StringName, Array] = quantities.tags

	for ingredient: CraftingIngredient in recipe:
		var total_quantity: int = 0

		if ingredient.type == "Item":
			var str_ingredient: StringName = ingredient.item.id
			if str_ingredient in item_quantities:
				for entry: Array in item_quantities[str_ingredient]:
					if _check_rarity_condition(ingredient.rarity_match, ingredient.item.rarity, entry[1]):
						total_quantity += entry[0]
		elif ingredient.type == "Tags":
			for tag: StringName in ingredient.tags:
				if tag in tag_quantities:
					for entry: Array in tag_quantities[tag]:
						total_quantity += entry[0]

		if total_quantity < ingredient.quantity:
			return false

	if not _verify_exact_match(item):
		return false

	return true

## This verifies that rarities match for ingredients if they are required to do so.
func _check_rarity_condition(rarity_cond: String, req_rarity: Globals.ItemRarity,
							item_rarity: Globals.ItemRarity) -> bool:
	match rarity_cond:
		"No":
			return true
		"Equal":
			return item_rarity == req_rarity
		"GEQ":
			return item_rarity >= req_rarity
	return false

## This verifies that each slot contains something that contributes to the recipe.
func _verify_exact_match(stats_of_item_to_craft: ItemResource) -> bool:
	var recipe: Array[CraftingIngredient] = stats_of_item_to_craft.recipe
	var occupied_slots: int = 0

	for slot: CraftingSlot in input_slots:
		if slot.item == null:
			continue
		occupied_slots += 1

		var allowed: bool = false
		for ingredient: CraftingIngredient in recipe:
			if ingredient.type == "Item":
				if _check_rarity_condition(ingredient.rarity_match, ingredient.item.rarity, slot.item.stats.rarity) and slot.item.stats.id == ingredient.item.id:
					allowed = true
					break
			elif ingredient.type == "Tags":
				for tag: StringName in ingredient.tags:
					if tag in slot.item.stats.tags:
						allowed = true
						break
				if allowed:
					break

		if not allowed:
			return false

	if stats_of_item_to_craft.exact_input_match and occupied_slots > recipe.size():
		return false

	return true

## Checks if an item resource is a valid ingredient in another item's recipe. Does not consider counts.
func check_if_item_in_ingredient_list(item_to_check: ItemResource, stats_of_item_to_craft: ItemResource) -> bool:
	if item_to_check == null:
		return false
	var recipe: Array[CraftingIngredient] = stats_of_item_to_craft.recipe

	for ingredient: CraftingIngredient in recipe:
		if ingredient.type == "Item":
			if (item_to_check.id == ingredient.item.id) and _check_rarity_condition(ingredient.rarity_match, ingredient.item.rarity, item_to_check.rarity):
				return true
		elif ingredient.type == "Tags":
			for tag: StringName in ingredient.tags:
				if tag in item_to_check.tags:
					return true

	return false

## Use the inverted lookups to get candidate recipes from the current items in the input.
func _get_candidate_recipes() -> Array:
	var quantities: Dictionary[StringName, Dictionary] = _preprocess_input_items(true)
	var candidates: Dictionary[StringName, bool] = {}

	for item_cache_id: StringName in quantities[&"items"].keys():
		if Items.item_to_recipes.has(item_cache_id):
			for recipe_id: StringName in Items.item_to_recipes[item_cache_id]:
				candidates[recipe_id] = true

	for tag: StringName in quantities[&"tags"].keys():
		if Items.tag_to_recipes.has(tag):
			for recipe_id: StringName in Items.tag_to_recipes[tag]:
				candidates[recipe_id] = true

	return candidates.keys()

## When any of the input slot items change, we try and populate the previews once again just in case the mismatches
## were just removed. We also update the crafting result to see if our input items can result in a craft.
func _on_input_item_changed(_slot: CraftingSlot, _old_item: InvItemResource, _new_item: InvItemResource) -> void:
	await get_tree().process_frame
	_populate_previews(item_details_panel.item_viewer_slot.item)
	_update_crafting_result()

## Use candidate recipes for efficiency to only test the recipes that are even potentially craftable.
func _update_crafting_result() -> void:
	if is_crafting:
		return

	var candidates: Array[StringName] = _get_candidate_recipes()
	for recipe_cache_id: StringName in candidates:
		var item_resource: ItemResource = Items.get_item_by_id(recipe_cache_id)
		if _is_item_craftable(item_resource):
			output_slot.set_item(
				InvItemResource.new(item_resource.duplicate_deep(), item_resource.output_quantity
			).assign_unique_suid())

			if output_slot.item.stats.upgrade_recipe and output_slot.item.stats is WeaponResource:
				var upgrade_origin_stats: ItemResource = get_upgrade_source(output_slot.item.stats)
				output_slot.item.stats.migrate_from_rarity_upgrade(upgrade_origin_stats, Globals.player_node, false)
			return

	output_slot.set_item(null)

## Consumes the ingredient from the input slots based on the target amount needed, returning false if it failed.
func _consume_ingredient(ingredient: CraftingIngredient, target_count: int) -> bool:
	var needed: int = ingredient.quantity * target_count

	for slot: CraftingSlot in input_slots:
		if slot.item == null:
			continue
		elif ingredient.type == "Item":
			if slot.item.stats.id == ingredient.item.id:
				if _check_rarity_condition(ingredient.rarity_match, ingredient.item.rarity, slot.item.stats.rarity):
					var available: int = slot.item.quantity
					var remove_amount: int = min(available, needed)
					slot.set_item(InvItemResource.new(slot.item.stats, available - remove_amount))
					needed -= remove_amount
		elif ingredient.type == "Tags":
			for tag: StringName in ingredient.tags:
				if tag in slot.item.stats.tags:
					var available: int = slot.item.quantity
					var remove_amount: int = min(available, needed)
					slot.set_item(InvItemResource.new(slot.item.stats, available - remove_amount))
					needed -= remove_amount
					break

		if needed <= 0:
			break

	return needed <= 0

## This consumes the ingredients in the recipe once the item is claimed.
## If the target amount is greater than 1, it must be able to craft that amount or it won't craft any at all.
## The target amount should be -1 if you want to craft as many as possible.
## If it fails, it restores all quantities and returns 0 as well as the backups.
func _consume_recipe(stats_of_item_to_craft: ItemResource, target_count: int) -> Dictionary[StringName, Variant]:
	var backups: Array[int] = _get_slot_quantities()
	var recipe: Array[CraftingIngredient] = stats_of_item_to_craft.recipe
	var result: Dictionary[StringName, Variant] = { &"successful_crafts" : 0, &"saved_items" : {} }

	var max_can_craft: int = _get_max_amount_craftable(stats_of_item_to_craft)
	if max_can_craft < 1:
		return result

	result.successful_crafts = max_can_craft if target_count == -1 else min(target_count, max_can_craft)

	if stats_of_item_to_craft.upgrade_recipe and stats_of_item_to_craft is WeaponResource:
		result.saved_items[&"upgrade_origin_stats"] = get_upgrade_source(stats_of_item_to_craft)

	for ingredient: CraftingIngredient in recipe:
		if not _consume_ingredient(ingredient, result.successful_crafts):
			_restore_input_slot_quantities(backups)
			return result

	for slot: CraftingSlot in input_slots:
		if slot.item and slot.item.quantity <= 0:
			slot.set_item(null)

	return result

## If we are upgrading a weapon as this craft, this will find the first weapon in the inputs that matches the
## recipe and return its stats. This acts as the source for the upgrade.
func get_upgrade_source(stats_of_item_to_craft: ItemResource) -> ItemResource:
	for slot: CraftingSlot in input_slots:
		if slot.item and check_if_item_in_ingredient_list(slot.item.stats, stats_of_item_to_craft) and slot.item.stats is WeaponResource:
			return slot.item.stats
	return null

## Gets an array of the quantities for each input slot.
func _get_slot_quantities() -> Array[int]:
	var quants: Array[int] = []
	for slot: CraftingSlot in input_slots:
		if slot.item:
			quants.append(slot.item.quantity)
		else:
			quants.append(-1)
	return quants

## Gets a total count of a given ingredient in all input slots.
func _get_total_ingredient_count(ingredient: CraftingIngredient) -> int:
	var total: int = 0
	for slot: CraftingSlot in input_slots:
		if slot.item == null:
			continue
		elif ingredient.type == "Item":
			if slot.item.stats.id == ingredient.item.id:
				if _check_rarity_condition(ingredient.rarity_match, ingredient.item.rarity, slot.item.stats.rarity):
					total += slot.item.quantity
		elif ingredient.type == "Tags":
			for tag: StringName in ingredient.tags:
				if tag in slot.item.stats.tags:
					total += slot.item.quantity
					break
	return total

## Gets the max amount of times we can craft the given recipe based on what is in the input slots.
func _get_max_amount_craftable(stats_of_item_to_craft: ItemResource) -> int:
	var recipe: Array[CraftingIngredient] = stats_of_item_to_craft.recipe

	var max_can_craft: int = 10000
	for ingredient: CraftingIngredient in recipe:
		var available_ingredient_count: int = _get_total_ingredient_count(ingredient)
		var max_craftable_for_this_ingredient: int = floori(float(available_ingredient_count) / float(ingredient.quantity))
		max_can_craft = min(max_can_craft, max_craftable_for_this_ingredient)

	if stats_of_item_to_craft.upgrade_recipe:
		return min(1, max_can_craft)
	return max_can_craft

## Puts a saved array of quantities back into the input slots after a failed craft.
func _restore_input_slot_quantities(backup_array: Array[int]) -> void:
	for i: int in range(input_slots.size()):
		if input_slots[i].item:
			input_slots[i].item.quantity = backup_array[i]

## This attempts to craft what is shown in the output slot by consuming the ingredients and
## granting the output item. Normally triggered by the craft button in the player inventory UI.
func attempt_craft() -> void:
	is_crafting = true

	var amount: int = 1
	if Input.is_action_pressed("sprint"):
		amount = -1

	var consumption_result: Dictionary[StringName, Variant] = _consume_recipe(output_slot.item.stats, amount)
	var output_quant_per_craft: int = output_slot.item.stats.output_quantity
	if consumption_result.successful_crafts > 0:
		output_slot.set_item(InvItemResource.new(output_slot.item.stats, consumption_result.successful_crafts * output_quant_per_craft))

		if output_slot.item.stats.upgrade_recipe and output_slot.item.stats is WeaponResource:
			output_slot.item.stats.migrate_from_rarity_upgrade(consumption_result.saved_items.upgrade_origin_stats, Globals.player_node)

		MessageManager.add_msg_preset(output_slot.item.get_pretty_string() + " Crafted", MessageManager.Presets.SUCCESS, 3.0, true)
		AudioManager.play_ui_sound(&"craft_button")

		Globals.player_node.inv.insert_from_inv_item(output_slot.item, false, false)

	is_crafting = false
	_update_crafting_result()

## When the main viewed item is changed, we wait for it to be set for a frame and then populate the previews
## with its recipe if we can.
func _on_viewed_item_changed(_slot: Slot, _old_item: InvItemResource, new_item: InvItemResource) -> void:
	await get_tree().process_frame
	_populate_previews(new_item)

## This gets the array of compatible items for each crafting ingredient in a recipe. Each ingredient can have
## more than one matching item if it is a "tag" ingredient. This is an array of arrays of Dictionaries, where
## the keys are the InvItemResources and the values are the minimum rarities. -1 min rarity means no min rarity.
func _get_preview_array(item: InvItemResource) -> Array[Array]:
	var preview_array: Array[Array] = []
	var recipe: Array[CraftingIngredient] = item.stats.recipe
	for ingredient: CraftingIngredient in recipe:
		var items_to_preview: Array[Dictionary]
		if ingredient.type == "Tags":
			for tag: StringName in ingredient.tags:
				var items_with_tag: Array = Items.tag_to_items.get(tag, [])
				for item_with_tag: ItemResource in items_with_tag:
					items_to_preview.append({ InvItemResource.new(item_with_tag, ingredient.quantity, true) : 0 })
		elif ingredient.type == "Item":
			var min_rarity: int = 0
			if ingredient.rarity_match in ["Equal", "GEQ"]:
				min_rarity = ingredient.item.rarity
			items_to_preview.append({ InvItemResource.new(ingredient.item, ingredient.quantity, true) : min_rarity })

		preview_array.append(items_to_preview)

	return preview_array

## Updates the UI on the input slots based on the preview assignment.
## For each ingredient from the recipe (in order), its assigned slot will either show the preview items
## (if empty), or update its quantity text (if filled).
func _update_preview_ui() -> void:
	var viewed_item: InvItemResource = item_details_panel.item_viewer_slot.item
	if viewed_item == null:
		_clear_crafting_previews()
		return

	var assignment: Dictionary[int, int] = _get_preview_assignment(viewed_item)
	if assignment.is_empty():
		_remove_altered_quantity_texts()
		return

	var preview_array: Array = _get_preview_array(viewed_item)

	for ingredient_index: int in range(preview_array.size()):
		var slot_idx: int = assignment.get(ingredient_index, -1)
		if slot_idx == -1:
			continue

		var candidates: Array[Dictionary] = preview_array[ingredient_index]
		var slot: CraftingSlot = input_slots[slot_idx]

		if slot.item: # If the slot already has an item, update its quantity text
			for candidate_dict: Dictionary[int, int] in candidates:
				var candidate_item: InvItemResource = candidate_dict.keys()[0]
				var min_rarity: int = candidate_dict.values()[0]
				if slot.item.stats.id == candidate_item.stats.id and slot.item.stats.rarity >= min_rarity:
					var required_qty: int = candidate_item.quantity
					slot.quantity.text = str(slot.item.quantity) + "/" + str(required_qty)
					slot.quantity.self_modulate.a = 1.0
					break
		else: # Empty slot, assign the candidate previews
			slot.preview_items = candidates
			if not candidates.is_empty():
				var candidate_item: InvItemResource = candidates[0].keys()[0]
				slot.quantity.text = "0/" + str(candidate_item.quantity)
				slot.quantity.self_modulate.a = 0.7

## Determines an assignment between the recipe’s ingredients (the preview array) and the input slots.
## Returns a Dictionary mapping recipe ingredient index → input slot index.
## If any filled slot holds an item that is not needed (i.e. unassignable), the function returns an empty dict.
func _get_preview_assignment(viewed_item: InvItemResource) -> Dictionary[int, int]:
	var preview_array: Array = _get_preview_array(viewed_item)
	var assignment: Dictionary[int, int] = {} # Mapping: recipe ingredient index → slot index
	var used_slots: Array = []

	# Pass 1: assign slots that already have an item matching one of the ingredient candidates
	for ingredient_index: int in range(preview_array.size()):
		var candidates: Array[Dictionary] = preview_array[ingredient_index]
		for slot_index: int in range(input_slots.size()):
			if slot_index in used_slots:
				continue

			var slot: CraftingSlot = input_slots[slot_index]
			if slot.item != null:
				for candidate_dict: Dictionary[int, int] in candidates:
					var candidate_item: InvItemResource = candidate_dict.keys()[0]
					var min_rarity: int = candidate_dict.values()[0]
					if slot.item.stats.id == candidate_item.stats.id and slot.item.stats.rarity >= min_rarity:
						assignment[ingredient_index] = slot_index
						used_slots.append(slot_index)
						break
				if assignment.has(ingredient_index):
					break
	# Pass 2: for unassigned ingredients, assign the first available (empty) slot
	for ingredient_index: int in range(preview_array.size()):
		if not assignment.has(ingredient_index):
			for slot_index: int in range(input_slots.size()):
				if slot_index in used_slots:
					continue
				if input_slots[slot_index].item == null:
					assignment[ingredient_index] = slot_index
					used_slots.append(slot_index)
					break
			# If no empty slot is found, assignment is incomplete
			if not assignment.has(ingredient_index):
				return {}

	# Final pass: if any input slot is filled but was not assigned to any ingredient, the recipe is invalid
	for slot_index: int in range(input_slots.size()):
		if input_slots[slot_index].item:
			var found: bool = false
			for ingredient_index: int in assignment:
				if assignment[ingredient_index] == slot_index:
					found = true
					break
			if not found:
				return {}

	return assignment

## Clears all the previews from all input slots.
func _clear_crafting_previews() -> void:
	for slot: CraftingSlot in input_slots:
		slot.preview_items = []
		if slot.item == null:
			slot.quantity.text = ""

## Removes the altered quantity text provided by the crafting previews from all input slots.
func _remove_altered_quantity_texts() -> void:
	for slot: CraftingSlot in input_slots:
		if slot.item != null:
			slot.quantity.self_modulate.a = 1.0
			var index: int = slot.quantity.text.rfind("/")
			if index != -1:
				slot.quantity.text = slot.quantity.text.substr(0, index)

## Updated populate previews function to use our new preview assignment & UI update functions.
func _populate_previews(item: InvItemResource) -> void:
	_clear_crafting_previews()
	var viewed_item: InvItemResource = item_details_panel.item_viewer_slot.item
	if viewed_item == null:
		_remove_altered_quantity_texts()
		return
	if not viewed_item.stats.recipe_unlocked:
		_remove_altered_quantity_texts()
		return
	_update_preview_ui()

## When the focused UI is closed, we should empty out the crafting input slots and drop them on the
## ground if the inventory is now full.
func _on_ui_focus_closed(_node: Node) -> void:
	for slot: CraftingSlot in input_slots:
		if slot.item != null:
			Globals.player_node.inv.insert_from_inv_item(slot.item, false, false)
			slot.set_item(null)

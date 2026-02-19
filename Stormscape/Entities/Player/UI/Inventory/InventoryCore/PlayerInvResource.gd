extends InvResource
class_name PlayerInvResource
## A subclass of InvResource that defines Player inventory specifics.

var ammo_slot_manager: AmmoSlotManager ## A reference to the ammo slot manager in the player's inv UI.
var currency_slot_manager: CurrencySlotManager ## A reference to the currency slot manager in the player's inv UI.


## Must be called after this inventory resource is created to set it up.
func initialize_inventory(source: Node2D) -> void:
	source_node = source
	auto_decrementer.inv = self
	auto_decrementer.owning_entity_is_player = true
	if drop_on_death:
		source_node.tree_exiting.connect(drop_entire_inventory)

	total_inv_size = Globals.MAIN_PLAYER_INV_SIZE + (1 + Globals.HOTBAR_SIZE) + Globals.AMMO_BAR_SIZE + Globals.CURRENCY_BAR_SIZE
	max_fill_index = total_inv_size - 1
	inv.resize(total_inv_size)
	clear_inventory()

	call_deferred("fill_inventory", starting_inv)

## Handles the logic needed for adding an item to the inventory when picked up from the ground. Respects stack size.
## Any extra quantity that does not fit will be left on the ground as a physical item.
func add_item_from_world(original_item: WorldItem) -> void:
	var original_quantity: int = original_item.q
	var remaining: int = 0
	if original_item.stats is ProjAmmoStats:
		remaining = _fill_ammo(original_item)
		if remaining != 0:
			original_item.respawn_item_after_quantity_change()
			MessageManager.add_msg_preset(original_item.stats.name + " Storage Full", MessageManager.Presets.FAIL, 3.0)
	elif original_item.stats is CurrencyStats:
		remaining = _fill_currency(original_item)
		if remaining != 0:
			original_item.respawn_item_after_quantity_change()
			MessageManager.add_msg_preset(original_item.stats.name + " Storage Full", MessageManager.Presets.FAIL, 3.0)
	else:
		remaining = _fill_hotbar(original_item)
		if remaining != 0:
			remaining = _fill_main_inventory(original_item)
		if remaining != 0:
			original_item.respawn_item_after_quantity_change()
			MessageManager.add_msg_preset("Inventory Full", MessageManager.Presets.FAIL, 3.0)

	var picked_up_quantity: int = original_quantity - remaining
	if picked_up_quantity > 0:

		MessageManager.add_msg("[color=white]+" + str(picked_up_quantity) + "[/color] " + original_item.stats.name, Globals.rarity_colors.ui_text.get(original_item.stats.rarity), original_item.stats.inv_icon, Color.WHITE, MessageManager.default_display_time, true)

## Handles the logic needed for adding an item to the inventory from a given inventory item resource.
## Respects stack size. By default, any extra quantity that does not fit will be ignored and deleted.
## Can optionally specify to fill the hotbar before filling the main inventory slots.
func insert_from_inv_item(original_ii: II, delete_extra: bool = true, hotbar_first: bool = false) -> void:
	var remaining: int = 0
	if original_ii.stats is ProjAmmoStats:
		remaining = _fill_ammo(original_ii)
	elif original_ii.stats is CurrencyStats:
		remaining = _fill_currency(original_ii)
	else:
		if hotbar_first:
			remaining = _fill_hotbar(original_ii)
		else:
			remaining = _fill_main_inventory(original_ii)

		if remaining != 0:
			if hotbar_first:
				remaining = _fill_main_inventory(original_ii)
			else:
				remaining = _fill_hotbar(original_ii)

	if not delete_extra and remaining != 0:
		var ii: II
		if original_ii.stats is WeaponStats:
			ii = original_ii.stats.create_ii(original_ii.q)
		else:
			ii = original_ii.duplicate()
		WorldItem.spawn_on_ground(ii, Globals.player_node.global_position, 8, false, true)

## Attempts to fill the hotbar with the item passed in. Can either be an WorldItem or an II.
## Returns any leftover quantity that did not fit.
func _fill_hotbar(original_item: Variant) -> int:
	return _do_add_item_checks(original_item, Globals.MAIN_PLAYER_INV_SIZE, Globals.MAIN_PLAYER_INV_SIZE + Globals.HOTBAR_SIZE)

## Attempts to fill the main inventory with the item passed in. Can either be an WorldItem or an II.
## Returns any leftover quantity that did not fit.
func _fill_main_inventory(original_item: Variant) -> int:
	return _do_add_item_checks(original_item, 0, Globals.MAIN_PLAYER_INV_SIZE)

## Attempts to fill the ammo slots in the inventory with the passed in ammo. Can either be an WorldItem or
## an II. Returns any leftover quantity that did not fit.
func _fill_ammo(original_item: Variant) -> int:
	var relative_index: int = ammo_slot_manager.type_order.find(original_item.stats.ammo_type)
	var placement_index: int = ammo_slot_manager.starting_index + relative_index
	return _do_add_item_checks(original_item, placement_index, placement_index + 1)

## Attempts to fill the currency slots in the inventory with the passed in currency. Can either be an WorldItem or
## an II. Returns any leftover quantity that did not fit.
func _fill_currency(original_item: Variant) -> int:
	var relative_index: int = currency_slot_manager.type_order.find(original_item.stats.currency_type)
	var placement_index: int = currency_slot_manager.starting_index + relative_index
	return _do_add_item_checks(original_item, placement_index, placement_index + 1)

#region Sorting
## This auto stacks and compacts items into their stack sizes.
func activate_auto_stack() -> void:
	for i: int in range(Globals.MAIN_PLAYER_INV_SIZE):
		if inv[i] == null:
			continue
		for j: int in range(i + 1, Globals.MAIN_PLAYER_INV_SIZE):
			if inv[j] == null:
				continue
			elif inv[i].stats.is_same_as(inv[j].stats):
				var total_quantity: int = inv[i].q + inv[j].q
				if total_quantity <= inv[i].stats.stack_size:
					inv[i].q = total_quantity
					inv[j] = null
				else:
					inv[i].q = inv[i].stats.stack_size
					inv[j].q = total_quantity - inv[i].stats.stack_size

	_emit_changes_for_all_indices()

## Called in order to start sorting by rarity of items in the inventory. Does not sort hotbar if present.
func activate_sort_by_rarity() -> void:
	var arr: Array[II] = inv.slice(0, Globals.MAIN_PLAYER_INV_SIZE)
	arr.sort_custom(_rarity_sort_logic)
	for i: int in range(Globals.MAIN_PLAYER_INV_SIZE):
		inv[i] = arr[i]
	_emit_changes_for_all_indices()

## Called in order to start sorting by type of items in the inventory. Does not sort hotbar if present.
func activate_sort_by_type() -> void:
	var arr: Array[II] = inv.slice(0, Globals.MAIN_PLAYER_INV_SIZE)
	arr.sort_custom(_type_sort_logic)
	for i: int in range(Globals.MAIN_PLAYER_INV_SIZE):
		inv[i] = arr[i]
	_emit_changes_for_all_indices()

## Called in order to start sorting by name of items in the inventory. Does not sort hotbar if present.
func activate_sort_by_name() -> void:
	var arr: Array[II] = inv.slice(0, Globals.MAIN_PLAYER_INV_SIZE)
	arr.sort_custom(_name_sort_logic)
	for i: int in range(Globals.MAIN_PLAYER_INV_SIZE):
		inv[i] = arr[i]
	_emit_changes_for_all_indices()

## Implements the comparison logic for sorting by rarity.
func _rarity_sort_logic(a: II, b: II) -> bool:
	if a == null and b == null: return false
	if a == null: return false
	if b == null: return true

	if a.stats.rarity != b.stats.rarity:
		return a.stats.rarity > b.stats.rarity
	elif a.stats.item_type != b.stats.item_type:
		return a.stats.item_type > b.stats.item_type
	else:
		return a.stats.name < b.stats.name

## Implements the comparison logic for sorting by item type.
func _type_sort_logic(a: II, b: II) -> bool:
	if a == null and b == null: return false
	if a == null: return false
	if b == null: return true

	if a.stats.item_type != b.stats.item_type:
		return a.stats.item_type > b.stats.item_type
	elif a.stats.rarity != b.stats.rarity:
		return a.stats.rarity > b.stats.rarity
	elif a.stats.name != b.stats.name:
		return a.stats.name < b.stats.name
	else:
		return a.q > b.q

## Implements the comparison logic for sorting by name.
func _name_sort_logic(a: II, b: II) -> bool:
	if a == null and b == null: return false
	if a == null: return false
	if b == null: return true

	if a.stats.name != b.stats.name:
		return a.stats.name < b.stats.name
	elif a.stats.rarity != b.stats.rarity:
		return a.stats.rarity > b.stats.rarity
	else:
		return a.q > b.q
#endregion

#region Weapon Helpers
## Consumes ammo from this inventory and returns the amount back to the caller. Only for player inv.
func get_more_ammo(max_amount_needed: int, take_from_inventory: bool,
					ammo_type: ProjWeaponStats.ProjAmmoType) -> int:
	var ammount_collected: int = 0
	var starting_index: int = ammo_slot_manager.starting_index

	for i: int in range(starting_index, starting_index + Globals.AMMO_BAR_SIZE):
		var item: II = inv[i]
		if item != null and (item.stats is ProjAmmoStats) and (item.stats.ammo_type == ammo_type):
			var amount_in_slot: int = item.q
			var amount_still_needed: int = max_amount_needed - ammount_collected
			var amount_to_take_from_slot: int = min(amount_still_needed, amount_in_slot)
			if take_from_inventory:
				remove_item(i, amount_to_take_from_slot)
			ammount_collected += amount_to_take_from_slot

			if ammount_collected == max_amount_needed:
				break

	return ammount_collected
#endregion

#region Debug
## Grants an amount of an item given the item's cache ID.
func grant_from_item_id(item_cache_id: StringName, count: int = 1) -> void:
	var item_stats: ItemStats = Items.get_item_by_id(item_cache_id, true)
	if item_stats == null:
		printerr("The request to grant the item \"" + item_cache_id + "\" failed because it does not exist.")
		return
	insert_from_inv_item(item_stats.create_ii(count), true, true)
#endregion

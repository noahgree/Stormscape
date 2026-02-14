extends Resource
class_name InvResource
## The data resource for an inventory.

signal inv_data_updated(index: int, item: InvItemResource) ## Emitted anytime the item in an inv index is changed.

@export var title: String = "CHEST" ## The title to be used if opened in an alternate inv.
@export var drop_on_death: bool = false ## When true, this entity will drop everything in its inventory when it dies.
@export var starting_inv: Array[InvItemResource] = [] ## The inventory that should be loaded when this scene is instantiated.
@export var inv_size_override: int = -1 ## When anything besides -1, this will override the inv size, regardless of the number of elements in starting_inv. Does not affect the main Player inventory. If the number of manually added slots added outside of any main slot grid exceed this value (or the size of the starting_inv), those indices in the source of truth inventory data will never be shown and live on forever in the array.

var inv: Array[InvItemResource] = [] ## The current inventory. Main source of truth.
var source_node: Node2D ## The node that this inventory is owned by. Could be a physics entity or a chest of sorts.
var total_inv_size: int ## Number of all slots, including main slots, hotbar slots, and the potential trash slot.
var max_fill_index: int ## The max index the inv can fill to.
var auto_decrementer: AutoDecrementer = AutoDecrementer.new() ## The script controlling the cooldowns, warmups, overheats, and recharges for this entity's inventory items.


## Must be called after this inventory resource is created to set it up.
func initialize_inventory(source: Entity) -> void:
	source_node = source
	auto_decrementer.inv = self
	if drop_on_death:
		source_node.tree_exiting.connect(drop_entire_inventory)
	if source.is_object:
		auto_decrementer = null

	total_inv_size = inv_size_override if inv_size_override > -1 else starting_inv.size()
	max_fill_index = total_inv_size
	inv.resize(total_inv_size)
	clear_inventory()

	call_deferred("fill_inventory", starting_inv)

## Clears the entire inventory and emits all changes.
func clear_inventory() -> void:
	inv.fill(null)
	_emit_changes_for_all_indices()

## Changes the core inv size by the passed in amount and returns the new size.
func change_size(change_amount: int) -> int:
	total_inv_size += change_amount
	inv.resize(total_inv_size)
	return total_inv_size

## Fills the inventory from an array of inventory items. If an item exceeds stack size, the
## quantity that does not fit into one slot is instantiated on the ground as a physical item.
## This method respects null spots in the list.
func fill_inventory(inv_to_fill_from: Array[InvItemResource]) -> void:
	inv.fill(null)
	for i: int in range(min(inv_to_fill_from.size(), max_fill_index)):
		if inv_to_fill_from[i] != null:
			var inv_item: InvItemResource = InvItemResource.new(
				inv_to_fill_from[i].stats.duplicate_deep(Resource.DEEP_DUPLICATE_INTERNAL), inv_to_fill_from[i].quantity,
				false
				).assign_unique_suid() # Need to ensure it is new and not the same as the inv to fill from

			if inv_item.quantity > inv_item.stats.stack_size:
				Item.spawn_on_ground(inv_item.stats, inv_item.quantity - inv_item.stats.stack_size, source_node.global_position, 14.0, true, false, true)
				inv_item.quantity = inv_item.stats.stack_size

			inv[i] = inv_item

	_emit_changes_for_all_indices()

## Fills the inventory from an array of inventory items. Calls another method to check
## stack size conditions, filling iteratively. It does not drop excess items on the ground,
## and anything that does not fit will be ignored.
func fill_inventory_with_checks(inv_to_fill_from: Array[InvItemResource]) -> void:
	inv.fill(null)
	for i: int in range(min(inv_to_fill_from.size(), max_fill_index)):
		if inv_to_fill_from[i] != null:
			insert_from_inv_item(InvItemResource.new(
				inv_to_fill_from[i].stats.duplicate_deep(Resource.DEEP_DUPLICATE_INTERNAL), inv_to_fill_from[i].quantity,
				false
				).assign_unique_suid(), true, false)

	_emit_changes_for_all_indices()

## Handles the logic needed for adding an item to the inventory when picked up from the ground. Respects stack size.
## Any extra quantity that does not fit will be left on the ground as a physical item.
func add_item_from_world(original_item: Item) -> void:
	if _fill_all_slots_in_order(original_item) != 0:
		original_item.respawn_item_after_quantity_change()

## Handles the logic needed for adding an item to the inventory from a given inventory item resource.
## Respects stack size. By default, any extra quantity that does not fit will be ignored and deleted.
## Can optionally specify to fill the hotbar before filling the main inventory slots.
func insert_from_inv_item(original_item: InvItemResource, delete_extra: bool = true,
							_hotbar_first: bool = false) -> void:
	var remaining: int = _fill_all_slots_in_order(original_item)

	if not delete_extra and remaining != 0:
		Item.spawn_on_ground(original_item.stats, original_item.quantity, Globals.player_node.global_position, 8, false, false, true)

## Attempts to fill the main inventory with the item passed in. Can either be an Item or an InvItemResource.
## Returns any leftover quantity that did not fit.
func _fill_all_slots_in_order(original_item: Variant) -> int:
	return _do_add_item_checks(original_item, 0, max_fill_index)

## Wrapper function to let child functions check whether to add quantity to an item slot.
## Checks between the indices give by the start index and the stop index.
func _do_add_item_checks(original_item: Variant, start_i: int, stop_i: int) -> int:
	var inv_item: InvItemResource = InvItemResource.new(original_item.stats, original_item.quantity)

	for i: int in range(start_i, stop_i):
		if inv[i] != null and inv[i].stats.is_same_as(inv_item.stats):
			if (inv_item.quantity + inv[i].quantity) <= inv_item.stats.stack_size:
				_combine_item_count_in_occupied_index(i, inv_item, original_item)
				return 0
			else:
				_add_what_fits_to_occupied_index_and_continue(i, inv_item, original_item)
				inv_item = InvItemResource.new(inv_item.stats, original_item.quantity)
		if inv[i] == null:
			if inv_item.quantity <= inv_item.stats.stack_size:
				_put_entire_quantity_in_empty_index(i, inv_item, original_item)
				return 0
			else:
				_put_what_fits_in_empty_index_and_continue(i, inv_item, original_item)
				inv_item = InvItemResource.new(inv_item.stats, original_item.quantity)

	return original_item.quantity

## Combines the item into a slot that has space for that kind of item.
func _combine_item_count_in_occupied_index(index: int, inv_item: InvItemResource, original_item: Variant) -> void:
	inv[index].quantity += inv_item.quantity
	if original_item is Item:
		original_item.remove_from_world()
	inv_data_updated.emit(index, inv[index])

## Adds what fits to an occupied slot of the same kind of item and passes the remainder to the next iteration.
func _add_what_fits_to_occupied_index_and_continue(index: int, inv_item: InvItemResource,
													original_item: Variant) -> void:
	var amount_that_fits: int = max(0, inv_item.stats.stack_size - inv[index].quantity)
	inv[index].quantity = inv_item.stats.stack_size
	inv_item.quantity -= amount_that_fits
	original_item.quantity -= amount_that_fits
	inv_data_updated.emit(index, inv[index])

## Puts the entire quantity of the given item into an empty slot. This means it was less than or equal
## to stack size.
func _put_entire_quantity_in_empty_index(index: int, inv_item: InvItemResource, original_item: Variant) -> void:
	inv[index] = inv_item
	if original_item is Item:
		original_item.remove_from_world()
	inv_data_updated.emit(index, inv[index])

## This puts what fits of an item type into an empty slot and passes the remainder to the next iteration.
func _put_what_fits_in_empty_index_and_continue(index: int, inv_item: InvItemResource,
												original_item: Variant) -> void:
	var leftover: int = max(0, inv_item.quantity - inv_item.stats.stack_size)
	inv_item.quantity = inv_item.stats.stack_size
	inv[index] = inv_item
	original_item.quantity = leftover
	inv_data_updated.emit(index, inv[index])

## This removes a certain amount of an item at the target index slot. If it removes everything, it deletes it.
func remove_item(index: int, amount: int) -> void:
	if inv[index] == null:
		return
	var updated_item: InvItemResource = InvItemResource.new(inv[index].stats, inv[index].quantity)
	updated_item.quantity = max(0, updated_item.quantity - amount)
	if updated_item.quantity <= 0:
		inv[index] = null
	else:
		inv[index] = updated_item
	inv_data_updated.emit(index, inv[index])

## Drops all items in the inventory on to the ground.
func drop_entire_inventory() -> void:
	var i: int = 0
	for item: InvItemResource in inv:
		if item != null:
			Item.spawn_on_ground(item.stats, item.quantity, source_node.global_position, 30, true, true, false)
			inv[i] = null
		i += 1

	_emit_changes_for_all_indices()

## Updates an item at an index and emits the changes.
func update_index_and_emit_changes(index: int, new_item: InvItemResource) -> void:
	inv[index] = new_item
	inv_data_updated.emit(index, inv[index])

## This updates all connected slots in order to reflect the UI properly.
func _emit_changes_for_all_indices() -> void:
	for i: int in range(total_inv_size):
		inv_data_updated.emit(i, inv[i])

#region Weapon Helpers
## Consumes ammo from this inventory and returns the amount back to the caller. Only for non-players, as the
## player has special ammo slots.
func get_more_ammo(max_amount_needed: int, take_from_inventory: bool,
					ammo_type: ProjWeaponResource.ProjAmmoType) -> int:
	var ammount_collected: int = 0
	var count: int = total_inv_size

	for i: int in range(count):
		var item: InvItemResource = inv[i]
		if item != null and (item.stats is ProjAmmoResource) and (item.stats.ammo_type == ammo_type):
			var amount_in_slot: int = item.quantity
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
## Custom method for printing the rich details of all inventory array spots.
func print_inv(include_null_spots: bool = false) -> void:
	var to_print: String = "[b]-----------------------------------------------------------------------------------------------------------------------------------[/b]\n"

	for i: int in range(total_inv_size):
		if inv[i] == null and not include_null_spots:
			continue

		if inv[i] != null:
			to_print = to_print + str(inv[i])
		else:
			to_print = to_print + "NULL"

		if (i + 1) % 5 == 0 and i != total_inv_size - 1:
			to_print += "\n"
		elif i != total_inv_size - 1:
			to_print += "  |  "

	if to_print.ends_with("\n"):
		to_print = to_print.substr(0, to_print.length() - 1)
	elif to_print.ends_with("|  "):
		to_print = to_print.substr(0, to_print.length() - 3)

	print_rich(to_print + "\n[b]-----------------------------------------------------------------------------------------------------------------------------------[/b]")
#endregion

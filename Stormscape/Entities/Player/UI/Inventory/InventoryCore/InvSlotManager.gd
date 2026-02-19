extends Control
class_name InvSlotManager
## The manager for any inventory UI that has a series of connected item slots.
##
## This handles indexing the slots as well as filling them with items once initialized.

static var slot_scene: PackedScene = preload("uid://m4ur3n2hwsp8") ## The slot scene to use to load slots according to the slot count of the synced inv.

@export var synced_inv_src_node: Node2D ## The node holding the inventory to connect to and reflect.
@export var main_slot_grid: GridContainer ## The main container for all normal inventory slots. Can be null. Used when linking general purpose inventories (like from world chests) to this UI. Do not use if you have manually added any preexisting slots.

var slots: Array[Slot] = [] ## The array of slots that this populator fills.
var index_counter: int = 0 ## Counts up every time a slot is assigned an index.


func _ready() -> void:
	reset_and_link_new_inv_source_node(synced_inv_src_node)
	if synced_inv_src_node:
		fill_slots_from_synced_inv()

## Resets and links a new source node and its inventory signals to this UI.
func reset_and_link_new_inv_source_node(new_source_node: Node2D) -> void:
	slots.clear()
	_clear_main_slot_grid()
	index_counter = 0

	if synced_inv_src_node != null and is_instance_valid(synced_inv_src_node):
		if synced_inv_src_node.inv.inv_data_updated.is_connected(_on_inv_data_updated):
			synced_inv_src_node.inv.inv_data_updated.disconnect(_on_inv_data_updated)
	synced_inv_src_node = new_source_node
	if synced_inv_src_node:
		synced_inv_src_node.inv.inv_data_updated.connect(_on_inv_data_updated)

## Sets up the main slot grid (if one exists) with the total inv size and then fills all slots with items.
func fill_slots_from_synced_inv() -> void:
	_setup_main_slot_grid(synced_inv_src_node.inv.total_inv_size)
	call_deferred("fill_slots_with_items")

## Returns the current index counter and then increments it to prepare for the next slot.
func assign_next_slot_index() -> int:
	var index: int = index_counter
	index_counter += 1
	return index

## Clears out all the children slots of the main slot grid (if it exists).
func _clear_main_slot_grid() -> void:
	if main_slot_grid:
		for slot: Slot in main_slot_grid.get_children():
			slot.call_deferred("queue_free")

## Sets up the main slots of this inventory if a main_slot_grid is connected.
func _setup_main_slot_grid(main_slot_grid_size: int) -> void:
	if not main_slot_grid:
		return
	if not slots.is_empty():
		push_error("You cannot have manually added preexisting slots AND a main slot grid. A main slot grid is meant for ease of use with no script, so if you have a script adding manual slots, assign them there.")
	for i: int in range(main_slot_grid_size):
		var slot: Slot = slot_scene.instantiate()
		slot.name = "MainSlot_" + str(index_counter)
		slot.index = assign_next_slot_index()
		slot.synced_inv = synced_inv_src_node.inv
		slots.append(slot)
		main_slot_grid.add_child(slot)

## Assigns an index and a synced inventory to a given slot that was already instantiated (usually in editor).
## The source of truth inv resource will assign in order of these preexisting slots first, then to any main
## slot grid second.
func assign_preexitsing_slot(slot: Slot) -> void:
	slot.index = assign_next_slot_index()
	slot.synced_inv = synced_inv_src_node.inv
	slots.append(slot)

## Fills the inventory slots with whatever the inventory has in its data. If the number of slots in the UI don't
## match the number of slots in the source of truth inv resource, an error is displayed.
func fill_slots_with_items() -> void:
	if slots.size() != synced_inv_src_node.inv.total_inv_size:
		push_error(synced_inv_src_node.name + " has a different number of spots in its inv resource than the number of slots in the UI trying to display them. \nInvResource size: " + str(synced_inv_src_node.inv.total_inv_size) + " | InvSlotManager slots count: " + str(slots.size()) + ".\nYou need to either add a main slot grid or sync up the number of manually added slots (through code) with the inventory size.")
	var i: int = 0
	for slot: Slot in slots:
		if i >= synced_inv_src_node.inv.total_inv_size:
			break
		slot.set_item(synced_inv_src_node.inv.inv[i])
		i += 1

## When an index gets updated in the inventory, this is received via signal in order to update a slot here.
func _on_inv_data_updated(index: int, item: InvItemResource) -> void:
	slots[index].set_item(item)
	if item and synced_inv_src_node is Player:
		synced_inv_src_node.hands.active_slot_info.calculate_inv_ammo()

#region Debug
## Custom printing method to show the items inside the slots populated by this node.
func print_slots(include_null_spots: bool = false) -> void:
	var to_print: String = "[b]-----------------------------------------------------------------------------------------------------------------------------------[/b]\n"
	for i: int in range(slots.size()):
		if slots[i].item == null and not include_null_spots:
			continue
		to_print = to_print + str(slots[i])
		if (i + 1) % 5 == 0 and i != slots.size() - 1: to_print += "\n"
		elif i != slots.size() - 1: to_print += "  |  "
	if to_print.ends_with("\n"): to_print = to_print.substr(0, to_print.length() - 1)
	elif to_print.ends_with("|  "): to_print = to_print.substr(0, to_print.length() - 3)
	print_rich(to_print + "\n[b]-----------------------------------------------------------------------------------------------------------------------------------[/b]")
#endregion

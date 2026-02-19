extends MarginContainer
class_name AmmoSlotManager
## Handles the storing and displaying of ammo for the player inside the player's inv UI.

@export var type_order: Array[ProjWeaponStats.ProjAmmoType] ## Defines ordering of ammo slots by type.

@onready var ammo_slots_grid: HBoxContainer = %AmmoSlotsGrid ## Reference to the grid of slots.

var starting_index: int ## The index of the first ammo slot in the player's slot indices.
var pulse_tween: Tween


## Sets up the ammo slots with their needed data and syncs itself to the PlayerInvResource.
func setup_slots(inventory_ui: PlayerInvUI) -> void:
	inventory_ui.synced_inv_src_node.inv.ammo_slot_manager = self

	var i: int = 0
	for slot: AmmoSlot in ammo_slots_grid.get_children():
		inventory_ui.assign_preexitsing_slot(slot)
		if i == 0:
			starting_index = slot.index
		i += 1

## Pulses the ammo type that the currently viewed projectile weapon requires.
func pulse_ammo_type(_slot: Slot, _old_item: InvItemStats, new_item: InvItemStats) -> void:
	for child: AmmoSlot in ammo_slots_grid.get_children():
		child.get_node("OverlayMargins/OverlayTexture").modulate = Color.WHITE
	if pulse_tween and pulse_tween.is_valid():
		pulse_tween.kill()
	if new_item == null or new_item.stats is not ProjWeaponStats:
		return

	pulse_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_loops()

	var match_index: int = type_order.find(new_item.stats.ammo_type)
	if match_index == -1:
		pulse_tween.kill()
		return
	var border: TextureRect = ammo_slots_grid.get_child(match_index).get_node("OverlayMargins/OverlayTexture")
	pulse_tween.tween_property(border, "modulate", Color(2.454, 2.454, 2.454), 1.0)
	pulse_tween.tween_interval(0.1)
	pulse_tween.tween_property(border, "modulate", Color.WHITE, 1.0)
	pulse_tween.tween_interval(0.1)

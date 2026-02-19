@icon("res://Utilities/Debug/EditorIcons/slot.svg")
extends Slot
class_name FuelSlot
## A child class of Slot that changes the conditions for which data can be dropped.


## Determines if the slot we are hovering over during a drag can accept drag data on mouse release.
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if data.item == null or not synced_inv:
		CursorManager.update_tooltip("Invalid!", Globals.ui_colors.ui_glow_strong_fail)
		return false
	if is_same_slot_as(data):
		return false
	if data.item.stats is not WorldResourceStats:
		CursorManager.update_tooltip("Must be Fuel!", Globals.ui_colors.ui_glow_strong_fail)
		return false
	elif data.item.stats is WorldResourceStats and data.item.stats.fuel_amount <= 0:
		CursorManager.update_tooltip("Must be Fuel!", Globals.ui_colors.ui_glow_strong_fail)
		return false

	CursorManager.update_tooltip("Deposit Fuel", Globals.ui_colors.ui_glow_strong_success)
	return true

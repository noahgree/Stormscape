@icon("res://Utilities/Debug/EditorIcons/slot.svg")
extends Slot
class_name WearableSlot
## A child class of Slot that changes the conditions for which data can be dropped.

var wearable_slot_index: int ## The index within the grid of wearable slots.


## Determines if the slot we are hovering over during a drag can accept drag data on mouse release.
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if data.ii == null or not synced_inv or not data.ii.stats is WearableStats:
		CursorManager.update_tooltip("Invalid!", Globals.ui_colors.ui_glow_strong_fail)
		return false
	if is_same_slot_as(data):
		return false
	if not WearablesManager.check_wearable_compatibility(Globals.player_node, data.item.stats):
		CursorManager.update_tooltip("Incompatible!", Globals.ui_colors.ui_glow_strong_fail)
		return false
	if WearablesManager.has_wearable(Globals.player_node, data.ii.stats.id):
		if data is not WearableSlot:
			CursorManager.update_tooltip("Already Used!", Globals.ui_colors.ui_glow_strong_fail)
			return false

	CursorManager.update_tooltip("Equip WearableStats", Globals.ui_colors.ui_glow_strong_success)
	return true

## An override for _drop_data that limits dropping a max quantity of 1.
func _drop_data(at_position: Vector2, data: Variant) -> void:
	super._drop_data(at_position, data)

	if ii != null:
		if ii.q > 1:
			var extra_items: II = ii.stats.create_ii(ii.q - 1)
			synced_inv.insert_from_inv_item(extra_items, false, false)
			ii.q = 1
			pause_changed_signals = true
			set_ii(ii)
			pause_changed_signals = false

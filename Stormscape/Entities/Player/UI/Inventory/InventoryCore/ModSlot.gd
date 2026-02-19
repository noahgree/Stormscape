@icon("res://Utilities/Debug/EditorIcons/slot.svg")
extends Slot
class_name ModSlot
## A child class of Slot that changes the conditions for which data can be dropped.

var is_hidden: bool = true: ## When true, the slot cannot de dropped onto as it is hidden and disabled.
	set(new_value):
		is_hidden = new_value
		visible = not is_hidden
var mod_slot_index: int ## The index within the grid of mod slots.
var item_viewer_slot: Slot ## A reference to the item viewer slot that determines which mods should display.


func _ready() -> void:
	super._ready()
	if not Engine.is_editor_hint(): # So they don't keep hiding in the editor
		is_hidden = true

## Determines if the slot we are hovering over during a drag can accept drag data on mouse release.
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if data.item == null or not synced_inv or not data.item.stats is WeaponModStats or is_hidden:
		CursorManager.update_tooltip("Invalid!", Globals.ui_colors.ui_glow_strong_fail)
		return false
	if is_same_slot_as(data):
		return false
	if not WeaponModsManager.check_mod_compatibility(item_viewer_slot.item.stats, data.item.stats):
		CursorManager.update_tooltip("Incompatible!", Globals.ui_colors.ui_glow_strong_fail)
		return false
	if item_viewer_slot.item.stats.has_mod(data.item.stats.id):
		if data is not ModSlot:
			CursorManager.update_tooltip("Already Used!", Globals.ui_colors.ui_glow_strong_fail)
			return false

	CursorManager.update_tooltip("Insert Mod", Globals.ui_colors.ui_glow_strong_success)
	return true

## An override for _drop_data that limits dropping a max quantity of 1.
func _drop_data(at_position: Vector2, data: Variant) -> void:
	super._drop_data(at_position, data)

	if item != null:
		if item.quantity > 1:
			var extra_items: InvItemResource = InvItemResource.new(item.stats, item.quantity - 1)
			synced_inv.insert_from_inv_item(extra_items, false, false)
			item.quantity = 1
			pause_changed_signals = true
			set_item(item)
			pause_changed_signals = false

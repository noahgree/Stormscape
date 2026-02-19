@icon("res://Utilities/Debug/EditorIcons/inventory_ui.svg")
extends InvSlotManager
class_name PlayerInvUI
## An child class of the inventory UI that adds functions specific to the player inventory.

@export_group("Textures")
@export var btn_up_texture: Texture2D ## The texture for buttons when not pressed.
@export var btn_down_texture: Texture2D ## The texture for buttons when pressed.

@onready var hotbar_grid: HBoxContainer = %HotbarGrid ## The container that holds the hotbar slots.
@onready var hotbar_hud_grid: HBoxContainer = %HotbarHUDGrid ## The container that holds the HUD-only hotbar slots.
@onready var trash_slot: Slot = %TrashSlot ## The trash slot.
@onready var item_details_panel: ItemDetailsPanel = %ItemDetailsPanel ## The item viewer in the inventory.
@onready var crafting_manager: CraftingManager = %CraftingManager ## The crafting manager panel.
@onready var wearables_panel: WearablesPanel = %WearablesPanel ## The wearables panel.
@onready var side_panel_mgr: SidePanelManager = %SidePanelManager ## The side panel manager.
@onready var ammo_slot_manager: AmmoSlotManager = %AmmoSlotManager ## The manager handling ammo slots.
@onready var currency_slot_manager: CurrencySlotManager = %CurrencySlotManager ## The manager handling currency slots.
@onready var trash_slot_container: MarginContainer = %TrashSlotPanelMargins ## The trash slot's margin container.
@onready var lvl_up_inner_margin: MarginContainer = %LvlUpInnerMargin ## The lvl up button's inner margin container.

@onready var sort_by_name_btn: NinePatchRect = %SortByName ## The sort by name button.
@onready var sort_by_type_btn: NinePatchRect = %SortByType ## The sort by type button.
@onready var sort_by_rarity_btn: NinePatchRect = %SortByRarity ## The sort by rarity button.
@onready var auto_stack_btn: NinePatchRect = %AutoStack ## The autostacking button.
@onready var craft_btn: NinePatchRect = %CraftBackground ## The craft button.
@onready var lvl_up_btn: NinePatchRect = %LvlUpBackground ## The lvl up button.

var is_open: bool = false: set = _toggle_inventory_ui ## True when the inventory is open and showing.
var side_panel_active: bool = false: set = _toggle_side_panel ## When true, the alternate inv is open and the wearable & crafting panels should be hidden.


## Returns true or false based on whether a slot is being dragged at the moment.
static func is_dragging_slot(viewport: Viewport) -> bool:
	var drag_data: Variant
	if viewport.gui_is_dragging():
		drag_data = viewport.gui_get_drag_data()

	if drag_data != null and drag_data is Slot:
		return true
	return false


func _ready() -> void:
	hide()
	if not Globals.player_node:
		await SignalBus.player_ready
	gui_input.connect(_on_blank_space_input_event)

	super() # Assigns first indices to main backpack grid.
	_setup_hotbar_slots() # Assigns hotbar slots next
	ammo_slot_manager.setup_slots(self) # Then ammo slots
	currency_slot_manager.setup_slots(self) # Then currency slots
	_setup_trash_slot() # Then trash slot
	item_details_panel.setup_slots(self) # Then item details panel (mod slots and item viewer slot)
	crafting_manager.setup_slots_and_signals(self) # Then crafting panel (input slots and output slot)
	wearables_panel.setup_slots(self) # Then wearables slots

## Overrides the parent function to specify that the main slot grid for the player has a Global value to use.
func fill_slots_from_synced_inv() -> void:
	_setup_main_slot_grid(Globals.MAIN_PLAYER_INV_SIZE)
	call_deferred("fill_slots_with_items")

## Sets up the in-inventory hotbar slots with their needed data. They are considered core slots
## and tracked by the inventory resource.
func _setup_hotbar_slots() -> void:
	var i: int = 0
	for slot: Slot in hotbar_grid.get_children():
		slot.name = "HotSlot_" + str(index_counter)
		slot.index = assign_next_slot_index()
		slot.synced_inv = synced_inv_src_node.inv
		slot.mirrored_hud_slot = hotbar_hud_grid.get_child(i)
		slots.append(slot)
		i += 1

## Sets up the trash slot with its needed data. It is considered a core slot and is tracked by the
## inventory resource.
func _setup_trash_slot() -> void:
	trash_slot.name = "Trash_Slot"
	trash_slot.index = assign_next_slot_index()
	trash_slot.synced_inv = synced_inv_src_node.inv
	trash_slot.is_trash_slot = true
	slots.append(trash_slot)
	trash_slot_container.hide()
	trash_slot.item_changed.connect(_on_trash_slot_item_changed)

## Checks when we open and close the player inventory based on certain key inputs.
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("player_inventory"):
		is_open = not is_open
	elif event.is_action_pressed("esc"):
		is_open = false
	elif event.is_action_pressed("interact"):
		if is_open:
			is_open = false
			accept_event() # Otherwise it just reopens it again after an external open request

	# If we are dragging when we press any key, end the drag.
	if get_viewport().gui_is_dragging():
		var drag_end_event: InputEventMouseButton = InputEventMouseButton.new()
		drag_end_event.button_index = MOUSE_BUTTON_LEFT
		drag_end_event.position = position
		drag_end_event.pressed = false
		Input.parse_input_event(drag_end_event)

## Handles the opening and closing of the entire player inventory based on the is_open var.
func _toggle_inventory_ui(open: bool) -> void:
	AudioManager.block_sound(&"slot_drop")
	is_open = open
	visible = open
	Globals.ui_focus_open = is_open
	if not is_open:
		side_panel_active = false
	Globals.change_focused_ui_state(is_open, self)
	var index: int = get_node("%HotbarHUD").get_active_hotbar_index()
	hotbar_grid.get_child(index).selected_texture.visible = open
	AudioManager.unblock_sound(&"slot_drop")

## Handles the opening and closing of the side panel based on the value of the side_panel_active var.
func _toggle_side_panel(new_value: bool) -> void:
	side_panel_active = new_value
	side_panel_mgr.delete(not new_value)
	crafting_manager.visible = not side_panel_active
	wearables_panel.visible = not side_panel_active

## When a side panel wants to open, open the inventory screen with the side panel active.
func open_with_side_panel() -> void:
	is_open = true
	side_panel_active = true

#region Dropping On Ground
## When we click the empty space around this player inventory, change needed visibilities.
func _on_blank_space_input_event(event: InputEvent) -> void:
	if event.is_action_released("primary"):
		is_open = false
		accept_event()

## Determines if this control node can have item slot data dropped into it.
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if (data != null) and ("item" in data) and (data.item != null):
		CursorManager.update_tooltip("Drop", Globals.ui_colors.ui_light_tan)
		return true
	else:
		return false

## Runs the logic for what to do when we can drop an item slot's data at the current moment.
## Creates physical items on the ground.
func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var ground_item_res: ItemStats = data.item.stats
	var ground_item_quantity: int = 1
	if ground_item_res and data:
		if data.dragging_only_one:
			ground_item_quantity = 1
			if data.item.quantity < 2:
				data.set_item(null)
			else:
				data.item.quantity -= 1
				data.set_item(data.item)
		elif data.dragging_half_stack:
			var half_quantity: int = int(floor(data.item.quantity / 2.0))
			var remainder: int = data.item.quantity - half_quantity
			ground_item_quantity = half_quantity

			data.item.quantity = remainder
			data.set_item(data.item)
		else:
			ground_item_quantity = data.item.quantity
			data.set_item(null)

		Item.spawn_on_ground(ground_item_res, ground_item_quantity, Globals.player_node.global_position, 15, true, false, true)
		MessageManager.add_msg("[color=white]Dropped " + str(ground_item_quantity) + "[/color] " + ground_item_res.name, Globals.rarity_colors.ui_text.get(ground_item_res.rarity), MessageManager.default_icon, Color.WHITE, MessageManager.default_display_time, true)

		if ground_item_res is ProjAmmoStats:
			synced_inv_src_node.hands.active_slot_info.calculate_inv_ammo()

	data._on_mouse_exited()

## When mouse stops hovering over drop zone, hide the tooltip.
func _on_mouse_exited() -> void:
	_hide_tooltip()
#endregion

## Received when any drag starts and ends to show and hide the trash slot.
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and trash_slot.item == null:
		trash_slot_container.hide()
	if what == NOTIFICATION_DRAG_BEGIN and PlayerInvUI.is_dragging_slot(get_viewport()):
		trash_slot_container.show()

## When the item in the trash slot changes, if we detect that it holds something now, re-show it.
func _on_trash_slot_item_changed(_slot: Slot, _old_item: InvItemResource, new_item: InvItemResource) -> void:
	if new_item != null:
		trash_slot_container.show()

#region Buttons
## Activates sorting this inventory by name.
func _on_sort_by_name_btn_pressed() -> void:
	Globals.player_node.inv.activate_sort_by_name()
	MessageManager.add_msg_preset("Items Sorted By Name", MessageManager.Presets.NEUTRAL, 2.0)
func _on_sort_by_name_btn_button_down() -> void:
	sort_by_name_btn.texture = btn_down_texture
func _on_sort_by_name_btn_button_up() -> void:
	sort_by_name_btn.texture = btn_up_texture

## Activates sorting this inventory by rarity.
func _on_sort_by_rarity_btn_pressed() -> void:
	Globals.player_node.inv.activate_sort_by_rarity()
	MessageManager.add_msg_preset("Items Sorted By Rarity", MessageManager.Presets.NEUTRAL, 2.0)
func _on_sort_by_rarity_btn_button_down() -> void:
	sort_by_rarity_btn.texture = btn_down_texture
func _on_sort_by_rarity_btn_button_up() -> void:
	sort_by_rarity_btn.texture = btn_up_texture

## Activates sorting this inventory by count.
func _on_sort_by_type_btn_pressed() -> void:
	Globals.player_node.inv.activate_sort_by_type()
	MessageManager.add_msg_preset("Items Sorted By Type", MessageManager.Presets.NEUTRAL, 2.0)
func _on_sort_by_type_btn_button_down() -> void:
	sort_by_type_btn.texture = btn_down_texture
func _on_sort_by_type_btn_button_up() -> void:
	sort_by_type_btn.texture = btn_up_texture

## Activates auto-stacking this inventory.
func _on_auto_stack_btn_pressed() -> void:
	Globals.player_node.inv.activate_auto_stack()
	MessageManager.add_msg_preset("Items Autostacked", MessageManager.Presets.NEUTRAL, 2.0)
func _on_auto_stack_btn_button_down() -> void:
	auto_stack_btn.texture = btn_down_texture
func _on_auto_stack_btn_button_up() -> void:
	auto_stack_btn.texture = btn_up_texture

## Attempts to craft whatever is shown in the output slot of the crafting UI.
func _on_craft_btn_pressed() -> void:
	get_node("%CraftingManager").attempt_craft()
func _on_craft_btn_button_down() -> void:
	craft_btn.texture = btn_down_texture
func _on_craft_btn_button_up() -> void:
	craft_btn.texture = btn_up_texture

## Handling the tooltip and button pressing of the level up button.
func _on_lvl_up_btn_pressed() -> void:
	var item_stats: WeaponStats = item_details_panel.item_viewer_slot.item.stats
	if item_stats.level_up() >= item_stats.allowed_lvl:
		lvl_up_inner_margin.hide()
	item_details_panel.manually_set_item_viewer_slot(item_details_panel.item_viewer_slot, true)
func _on_lvl_up_btn_mouse_entered() -> void:
	if not get_viewport().gui_is_dragging():
		CursorManager.update_tooltip("Level Up (" + str(item_details_panel.item_viewer_slot.item.stats.level + 1) + ")")
func _on_lvl_up_btn_button_down() -> void:
	lvl_up_btn.texture = btn_down_texture
func _on_lvl_up_btn_button_up() -> void:
	lvl_up_btn.texture = btn_up_texture


## Showing and hiding sort & stack tooltips.
func _on_sort_btn_mouse_entered(sort_method: String) -> void:
	if not get_viewport().gui_is_dragging():
		CursorManager.update_tooltip("Sort by " + sort_method)
func _on_auto_stack_btn_mouse_entered() -> void:
	if not get_viewport().gui_is_dragging():
		CursorManager.update_tooltip("Autostack Items")
func _on_craft_btn_mouse_entered() -> void:
	if not get_viewport().gui_is_dragging():
		var success: bool = crafting_manager.can_output
		var color: Color = Globals.ui_colors.ui_glow_strong_success if success else Globals.ui_colors.ui_light_tan
		CursorManager.update_tooltip("Craft" if success else "Nothing to Craft", color)
func _hide_tooltip() -> void:
	CursorManager.hide_tooltip()
#endregion

@icon("res://Utilities/Debug/EditorIcons/active_slot_info.svg")
extends Control
## Updates the info for the player's UI that shows the active slot item and any extra necessary info.

@onready var item_name: Label = %ItemName ## The label that shows the item name.
@onready var mag_ammo: Label = %MagAmmo ## The label that shows the mag ammo.
@onready var inv_ammo: Label = %InvAmmo ## The label that shows the inventory ammo.
@onready var mag_ammo_margin: MarginContainer = %MagAmmoMargin

func _ready() -> void:
	item_name.text = ""
	mag_ammo.text = ""
	inv_ammo.text = ""

	SignalBus.ui_focus_opened.connect(func(_node: Node) -> void: visible = not Globals.ui_focus_open)
	SignalBus.ui_focus_closed.connect(func(_node: Node) -> void: visible = not Globals.ui_focus_open)

	if not Globals.player_node:
		await Globals.ready

	SignalBus.ui_focus_closed.connect(func(_node: Node) -> void: calculate_inv_ammo())
	Globals.player_node.stamina_component.max_stamina_changed.connect(func(_new_max_stamina: float) -> void: calculate_inv_ammo())

## Updates the name portion of the current equipped item info.
func update_item_name(item_name_string: String) -> void:
	await get_tree().process_frame
	item_name.text = item_name_string.to_upper()

## Updates the magazine ammo portion of the current equipped item info.
func update_mag_ammo_ui(mag_count: String) -> void:
	await get_tree().process_frame
	mag_ammo.text = mag_count

## Updates the inventory ammo portion of the current equipped item info.
func update_inv_ammo_ui(inv_count: String) -> void:
	await get_tree().process_frame
	inv_ammo.text = inv_count
	if inv_count == "":
		mag_ammo_margin.add_theme_constant_override("margin_right", -3)
	else:
		mag_ammo_margin.remove_theme_constant_override("margin_right")

## Gets the cumulative total of the ammo that corresponds to the currently equipped item.
func calculate_inv_ammo() -> void:
	if Globals.player_node.hands.equipped_item == null:
		update_inv_ammo_ui("")
		return
	var current_item_stats: ItemStats = Globals.player_node.hands.equipped_item.stats
	if current_item_stats is WeaponStats and current_item_stats.hide_ammo_ui:
		update_inv_ammo_ui("")
		return

	var count_str: String
	if current_item_stats is ProjWeaponStats:
		if current_item_stats.ammo_type not in [ProjWeaponStats.ProjAmmoType.NONE, ProjWeaponStats.ProjAmmoType.STAMINA, ProjWeaponStats.ProjAmmoType.SELF, ProjWeaponStats.ProjAmmoType.CHARGES]:
			var count: int = 0
			var start_index: int = Globals.player_node.inv.ammo_slot_manager.starting_index
			for i: int in range(start_index, start_index + Globals.AMMO_BAR_SIZE):
				var item: InvItemStats = Globals.player_node.inv.inv[i]
				if item != null and (item.stats is ProjAmmoStats) and (item.stats.ammo_type == current_item_stats.ammo_type):
					count += item.quantity
			count_str = str(count)
		elif current_item_stats.ammo_type in [ProjWeaponStats.ProjAmmoType.NONE, ProjWeaponStats.ProjAmmoType.CHARGES]:
			count_str = "∞"
		elif current_item_stats.ammo_type == ProjWeaponStats.ProjAmmoType.SELF:
			var count: int = 0
			for i: int in range(0, Globals.MAIN_PLAYER_INV_SIZE + Globals.HOTBAR_SIZE):
				var item: InvItemStats = Globals.player_node.inv.inv[i]
				if item != null and (item.stats.id == current_item_stats.id):
					count += item.quantity
			var equipped_inv_item: InvItemStats = Globals.player_node.inv.inv[Globals.player_node.hands.equipped_item.inv_index]
			count -= equipped_inv_item.quantity if equipped_inv_item else 0
			count_str = str(count) if count != 0 else ""
	update_inv_ammo_ui(count_str)

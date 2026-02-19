@tool
extends StaticEntity
class_name StormBase
## The main storm-controlling entity, providing the functionality for the core gameplay element of controlling
## the storm.

@export var level: int = 1 ## The current level of the storm base.
@export var default_transform: StormTransform ## The transform that the storm will start at, responsive to when this entity is moved in-editor. The starting radius in this resource defines the default radius for when the base has 100% fuel.
@export var side_panel: PackedScene ## The side panel to pass along when the player opens the storm base UI.

@onready var interaction_area: InteractionArea = $InteractionArea ## The interaction area that offers an interaction to the nearby player.

var storm: Storm ## A reference to the storm node.
var level_progress: int = 0 ## The progress leading up to the next level.
var fuel: int: set = _set_fuel ## The current amount of fuel left.
var max_fuel: int = 100 ## The max fuel the base can have.
var fuel_change_resize_factor: float = 15.0 ## The greater the value, the faster the zone will change size.
var fuel_change_move_factor: float = 40.0 ## The greater the value, the faster the zone will move locations.


func _ready() -> void:
	if Engine.is_editor_hint():
		default_transform.new_location = global_position
	else:
		storm = Globals.storm
		if global_position != default_transform.new_location:
			push_error("The default transform of the storm base has not automatically updated to the correct position of the storm base.")

		interaction_area.set_accept_callable(func() -> void: SignalBus.side_panel_open_request.emit(side_panel, self))

	super()

func link_fuel_slot(fuel_slot: Slot) -> void:
	fuel_slot.item_changed.connect(_on_fuel_slot_item_changed)

func _on_fuel_slot_item_changed(slot: Slot, _old_item: InvItemResource, new_item: InvItemResource) -> void:
	if new_item:
		var total_new_fuel: int = new_item.quantity * new_item.stats.fuel_amount
		var fuel_space: int = max_fuel - fuel
		var extra_fuel: int = total_new_fuel - fuel_space
		if extra_fuel > 0:
			var extra_item_quant: int = floori(extra_fuel / new_item.stats.fuel_amount)
			var extra_items: InvItemResource = InvItemResource.new(new_item.stats, extra_item_quant)
			Globals.player_node.inv.insert_from_inv_item(extra_items, false, false)
		fuel += total_new_fuel

		# Otherwise it never deletes the item since the one just dropped is still being set
		slot.call_deferred("set_item", null)

func _set_fuel(new_fuel: int) -> void:
	fuel = mini(new_fuel, max_fuel)
	var fuel_left_pct: float = float(fuel) / max_fuel
	var new_radius: float = default_transform.new_radius * fuel_left_pct
	var pos_change_time: float = abs(storm.global_position.distance_to(global_position)) / fuel_change_move_factor
	var rad_change_time: float = abs(storm.current_radius - new_radius) / fuel_change_resize_factor

	var new_transform: StormTransform = StormTransform.create(global_position, false, new_radius, false, 0, pos_change_time, rad_change_time, false)
	if not ((global_position == storm.global_position) and (new_radius == storm.current_radius)):
		storm.replace_current_queue([new_transform])
		storm.force_start_next_phase()

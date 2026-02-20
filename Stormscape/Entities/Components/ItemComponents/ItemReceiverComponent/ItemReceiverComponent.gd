@icon("res://Utilities/Debug/EditorIcons/item_receiver_component.svg")
extends Area2D
class_name ItemReceiverComponent
## When attached to an entity, this gives it the ability to pick up items when overlapping with this collision box.

@export var pickup_range: int = 12: ## How big the collision shape is in px that is detected by items to enable pickup.
	set(new_range):
		pickup_range = new_range
		if collision_shape:
			collision_shape.shape.radius = pickup_range
@export var interaction_offer: InteractionOffer ## The offer to display when an item can be picked up.

@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var items_in_range: Array[WorldItem] = [] ## The items in range of being picked up.
var synced_inv: InvResource ## The inventory to add to.
const PICKUP_PROMPT_UI_OFFSET: Vector2i = Vector2i(0, -30)


func _ready() -> void:
	if not get_parent().is_node_ready():
		await get_parent().ready
	synced_inv = get_parent().inv

	collision_layer = 0b10000000

## Adds an item to the in range queue.
func add_to_in_range_queue(world_item: WorldItem) -> void:
	items_in_range.append(world_item)
	_update_all_old_item_outlines(true)
	_update_player_item_interact_hud()

## Removes an item from the in range queue.
func remove_from_in_range_queue(world_item: WorldItem) -> void:
	_remove_item_outline(world_item)
	items_in_range.erase(world_item)
	_update_all_old_item_outlines(false)
	_update_player_item_interact_hud()

## When used on a player, this method notifies the interaction handler of item pickup item changes.
func _update_player_item_interact_hud() -> void:
	Globals.player_node.interaction_handler.revoke_offer(interaction_offer)

	if not items_in_range.is_empty():
		var world_item: WorldItem = items_in_range.back()
		var wi_stats: ItemStats = world_item.ii.stats

		interaction_offer.accept_callable = _pickup_item_from_queue
		interaction_offer.ui_offset = PICKUP_PROMPT_UI_OFFSET
		interaction_offer.ui_anchor_node = world_item
		if world_item.ii.q > 1:
			interaction_offer.title = (wi_stats.name + " (" + str(world_item.ii.q) + ")").to_upper()
		else:
			interaction_offer.title = wi_stats.name.to_upper()
		interaction_offer.title_color = Globals.ui_colors.ui_glow_light_tan
		interaction_offer.info = wi_stats.get_rarity_string() + " " + wi_stats.get_item_type_string()
		if wi_stats is WeaponStats and not wi_stats.no_levels:
			interaction_offer.info += " (Lvl. " + str(world_item.ii.level) + ")"
		interaction_offer.info_color = Globals.rarity_colors.ui_text.get(wi_stats.rarity)

		Globals.player_node.interaction_handler.offer_interaction(interaction_offer)

## Adds the highlight outline to the passed in item.
func _add_item_highlight_outline(world_item: WorldItem) -> void:
	world_item.icon.material.set_shader_parameter("outline_color", Color.WHITE)
	world_item.icon.material.set_shader_parameter("width", 0.82)

## Removes the highlight outline from the passed in item.
func _remove_item_outline(world_item: WorldItem) -> void:
	world_item.icon.material.set_shader_parameter("outline_color", Globals.rarity_colors.outline_color.get(world_item.ii.stats.rarity))
	world_item.icon.material.set_shader_parameter("width", 0.5)

## Updates the outlines for all items in the in range queue depending on whether we just added or removed from it.
func _update_all_old_item_outlines(after_item_added: bool) -> void:
	if items_in_range.is_empty():
		return

	if after_item_added:
		for world_item: WorldItem in items_in_range:
			world_item.icon.material.set_shader_parameter("outline_color", Globals.rarity_colors.outline_color.get(world_item.ii.stats.rarity))
			world_item.icon.material.set_shader_parameter("width", 0.5)

	_add_item_highlight_outline(items_in_range.back())

## Attempts to pick up the first item in the items in range queue. The method it calls will drop what doesn't
## fit back on the ground with the appropriate updated quantity.
func _pickup_item_from_queue() -> void:
	if not items_in_range.is_empty():
		if items_in_range[items_in_range.size() - 1].can_be_picked_up_at_all:
			synced_inv.add_item_from_world(items_in_range.pop_back())

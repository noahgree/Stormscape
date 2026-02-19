@tool
extends Area2D
class_name Item
## Base class for all items in the game. Defines logic for interacting with entities that can pick it up.

static var item_scene: PackedScene = preload("res://Entities/Items/ItemCore/Item.tscn") ## The item scene to be instantiated when items are dropped onto the ground.

@export_storage var stats: ItemStats = null: set = _set_item ## The item resource driving the stats and type of item.
@export_storage var quantity: int = 1: ## The quantity associated with the physical item.
	set(new_quantity):
		quantity = new_quantity
		_update_multiple_indicator_sprite()

@onready var collision_shape: CollisionShape2D = $CollisionShape2D ## The active collision shape for the item to be interacted with.
@onready var icon: Sprite2D = $Sprite ## The sprite that shows the item's texture.
@onready var multiple_indicator_sprite: Sprite2D = $MultipleIndicatorSprite ## The sprite that shows when this has a quantity greater than 1.
@onready var ground_glow: Sprite2D = $GroundGlowScaler/GroundGlow ## The fake light that immitates a glowing effect on the ground.
@onready var particles: CPUParticles2D = $Particles ## The orb particles that spawn on higher rarity items.
@onready var line_particles: CPUParticles2D = $LineParticles ## The line particles that spawn on the highest rarity items.
@onready var anim_player: AnimationPlayer = $AnimationPlayer ## The animation player controlling the hover, spawn, and remove anims.

const ITEM_LIFETIME_MIN_MAX: Vector2i = Vector2i(290, 310) ## Range of how long the item should live for in seconds.
const BLINK_DURATION: int = 25 ## How long at the end of the item's lifetime should the blink sequence last.
const BLINK_INTERVAL_MIN_MAX: Vector2 = Vector2(0.085, 0.6) ## The min, max tween duration for the blinking.
var can_be_auto_picked_up: bool = false ## Whether the item can currently be auto picked up by walking over it.
var can_be_picked_up_at_all: bool = true ## When false, the item is in a state where it cannot be picked up by any means.
var lifetime_timer: Timer = TimerHelpers.create_one_shot_timer(self, -1, _start_blink_sequence) ## The timer tracking how long the item has left to be on the ground before blinking starts.
var blink_tween: Tween
var final_seconds_timer: Timer = TimerHelpers.create_one_shot_timer(self, BLINK_DURATION, remove_from_world)
var is_tweening_up: bool = true


func _set_item(item_stats: ItemStats) -> void:
	stats = item_stats
	if stats and icon:
		$CollisionShape2D.shape.radius = stats.pickup_radius
		icon.texture = stats.ground_icon
		icon.position.y = -icon.texture.get_height() / 2.0
		_update_multiple_indicator_sprite()

		if ground_glow:
			ground_glow.scale.x = 0.05 * (icon.texture.get_width() / 16.0)
			ground_glow.scale.y = 0.05 * (icon.texture.get_height() / 32.0)
			ground_glow.position.y = ceil(icon.texture.get_height() / 2.0) + ceil(7.0 / 2.0) - 2 + icon.position.y

## Spawns an item with the passed in details on the ground. Keep suid means we should duplicate
## the item's stats and pass the old session uid along to it. Can also choose to let items spawn with
## higher than stack quantities.
static func spawn_on_ground(item_stats: ItemStats, quant: int, location: Vector2,
							location_range: float, keep_suid: bool = true, respect_max_stack: bool = false,
							auto_pickup_delay: bool = true) -> void:
	var quantity_count: int = quant
	while quantity_count > 0:
		var item_to_spawn: Item = item_scene.instantiate()
		item_to_spawn.stats = item_stats.duplicate_with_suid() if keep_suid else item_stats.duplicate()

		if respect_max_stack:
			var quant_to_use: int = min(quantity_count, item_stats.stack_size)
			item_to_spawn.quantity = quant_to_use
			quantity_count -= quant_to_use
		else:
			item_to_spawn.quantity = quantity_count
			quantity_count = 0

		if location_range != -1:
			item_to_spawn.global_position = location + Vector2(randf_range((-location_range - 6) / 2.0, (location_range - 6) / 2.0) + 6, randf_range(0, (location_range - 6)) + 6)
		else:
			item_to_spawn.global_position = location

		if not auto_pickup_delay:
			item_to_spawn.can_be_auto_picked_up = true

		var spawn_callable: Callable = Globals.world_root.get_node("WorldItemsManager").add_item.bind(item_to_spawn)
		spawn_callable.call_deferred()

#region Save & Load
func _on_save_game(save_data: Array[SaveData]) -> void:
	var data: ItemData = ItemData.new()
	data.scene_path = scene_file_path
	data.position = global_position
	data.stats = stats
	data.quantity = quantity

	save_data.append(data)

func _on_before_load_game() -> void:
	queue_free()

func _is_instance_on_load_game(item_data: ItemData) -> void:
	global_position = item_data.position
	stats = item_data.stats
	quantity = item_data.quantity

	Globals.world_root.get_node("WorldItemsManager").add_item(self)

func _on_load_game() -> void:
	pass
#endregion

func _ready() -> void:
	_set_item(stats)

	if Engine.is_editor_hint():
		return

	add_to_group("items_on_ground")
	collision_mask = 0b10000000

	particles.emitting = false
	_set_rarity_colors()
	icon.set_instance_shader_parameter("random_start_offset", randf() * 2.0)

	lifetime_timer.start(VectorHelpers.randi_between_xy(ITEM_LIFETIME_MIN_MAX) - BLINK_DURATION)

	if not can_be_auto_picked_up:
		await get_tree().create_timer(1.0, false, false, false).timeout
		can_be_auto_picked_up = true

## Updates the visibility of the extra sprite that shows when the quantity is higher than 1.
func _update_multiple_indicator_sprite() -> void:
	if multiple_indicator_sprite == null:
		return

	if quantity > 1:
		multiple_indicator_sprite.texture = stats.ground_icon
		multiple_indicator_sprite.show()
	else:
		multiple_indicator_sprite.hide()
	multiple_indicator_sprite.position.y = (-icon.texture.get_height() / 2.0) - 1.0

## Sets the rarity FX using the colors associated with that rarity, given by the dictionary in the Globals.
func _set_rarity_colors() -> void:
	icon.material.set_shader_parameter("width", 0.5)
	ground_glow.self_modulate = Globals.rarity_colors.ground_glow.get(stats.rarity)
	icon.material.set_shader_parameter("outline_color", Globals.rarity_colors.outline_color.get(stats.rarity))
	icon.material.set_shader_parameter("tint_color", Globals.rarity_colors.tint_color.get(stats.rarity))

	var gradient_texture: GradientTexture1D = GradientTexture1D.new()
	gradient_texture.gradient = Gradient.new()
	gradient_texture.gradient.add_point(0, Globals.rarity_colors.glint_color.get(stats.rarity))
	icon.material.set_shader_parameter("color_gradient", gradient_texture)

	if stats.rarity in [Globals.ItemRarity.LEGENDARY, Globals.ItemRarity.SINGULAR]:
		particles.color = Globals.rarity_colors.ground_glow.get(stats.rarity)
		particles.emitting = true
	if stats.rarity == Globals.ItemRarity.SINGULAR:
		particles.amount *= 3

## When the spawn animation finishes, start hovering and emitting particles if needed.
func _on_spawn_anim_completed() -> void:
	anim_player.play("hover")
	if stats.rarity in [Globals.ItemRarity.LEGENDARY, Globals.ItemRarity.SINGULAR]:
		line_particles.color = Globals.rarity_colors.tint_color.get(stats.rarity)
		line_particles.emitting = true

## Starts the blinking out sequence that eventually removes the item from the world when it ends.
func _start_blink_sequence() -> void:
	final_seconds_timer.start()
	_do_blink()

## Called each time the blink happens to tween the shader property.
func _do_blink() -> void:
	if not final_seconds_timer.is_stopped():
		var progress: float = 1.0 - (final_seconds_timer.time_left / BLINK_DURATION)
		var curr_blink_dur: float = lerp(BLINK_INTERVAL_MIN_MAX.y, BLINK_INTERVAL_MIN_MAX.x, progress)
		var target_value: float = 0.25 if is_tweening_up else 0.0
		is_tweening_up = not is_tweening_up

		if blink_tween:
			blink_tween.kill()

		blink_tween = create_tween()
		blink_tween.tween_property(icon.material, "shader_parameter/override_color:a", target_value, curr_blink_dur)
		blink_tween.tween_callback(_do_blink)

## Ends any lifetime timers and blink sequences and starts the lifetime timer over again.
func restart_lifetime_timer_and_cancel_any_blink_sequence() -> void:
	final_seconds_timer.stop()
	lifetime_timer.stop()
	if blink_tween:
		blink_tween.kill()
	icon.set_instance_shader_parameter("override_color", Color.TRANSPARENT)
	lifetime_timer.start()

## Removes the item from the world
func remove_from_world() -> void:
	anim_player.play("remove")

## When the animation of the item being removed from the world is done, we queue free the item.
func _on_remove_anim_completed() -> void:
	queue_free()

func _on_area_entered(area: Area2D) -> void:
	if not can_be_picked_up_at_all:
		return

	if area is ItemReceiverComponent and area.get_parent() is Player:
		if stats.auto_pickup and can_be_auto_picked_up:
			area.synced_inv.add_item_from_world(self)
		else:
			area.add_to_in_range_queue(self)

func _on_area_exited(area: Area2D) -> void:
	if area is ItemReceiverComponent and area.get_parent() is Player:
		area.remove_from_in_range_queue(self)

## After the quantity of the in-game item changes, we respawn it in the same spot with its updated quantity.
## This helps retrigger the pickup HUD with the new quantity.
func respawn_item_after_quantity_change() -> void:
	can_be_picked_up_at_all = false
	Item.spawn_on_ground(stats, quantity, global_position, -1, true, false, true)
	queue_free()

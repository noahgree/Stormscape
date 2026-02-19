@icon("res://Utilities/Debug/EditorIcons/consumable.png")
extends EquippableItem
class_name Consumable
## The base class for all consumables, which are items that can be eaten or used up in some way to provide effects
## and/or hunger bars, stamina, etc.

@onready var consumption_timer: Timer = $ConsumptionTimer ## The time it takes to consume the consumable and trigger its effects.
@onready var food_particles: CPUParticles2D = $FoodParticles ## The particles that fire off when the consumable is consumed.


func _set_stats(new_stats: ItemStats) -> void:
	super._set_stats(new_stats)

	if sprite:
		sprite.texture = stats.in_hand_icon

func _process(_delta: float) -> void:
	_update_cursor_cooldown_ui()

## When activate is triggered, try and consume the item.
func activate() -> void:
	consume()

## Consumes the consumable, assuming the previous consumption timer is stopped and we aren't on cooldown.
func consume() -> void:
	if not consumption_timer.is_stopped():
		return

	if source_entity.inv.auto_decrementer.get_cooldown(stats.get_cooldown_id()) == 0:
		food_particles.global_position = source_entity.hands.global_position + source_entity.hands.mouth_pos
		food_particles.lifetime = max(0.2, stats.consumption_time / 2.0)
		food_particles.color = stats.particles_color
		food_particles.emitting = true

		consumption_timer.start(stats.consumption_time)
		await consumption_timer.timeout

		source_entity.inv.auto_decrementer.add_cooldown(stats.get_cooldown_id(), stats.consumption_cooldown)

		var stamina_component: StaminaComponent = source_entity.get_node_or_null("StaminaComponent")
		if stamina_component != null:
			stamina_component.gain_hunger_bars(stats.hunger_bar_gain)
			stamina_component.use_hunger_bars(stats.hunger_bar_deduction)

		source_entity.effect_receiver.handle_effect_source(stats.effect_source, source_entity, null)

		source_entity.inv.remove_item(inv_index, 1)

## Updates the mouse cursor's cooldown progress based on active cooldowns.
func _update_cursor_cooldown_ui() -> void:
	if not source_entity is Player or not stats.show_cursor_cooldown:
		return

	if source_entity.inv.auto_decrementer.get_cooldown_source_title(stats.get_cooldown_id()) in stats.shown_cooldown_fills:
		var tint_progress: float = source_entity.inv.auto_decrementer.get_cooldown_percent(stats.get_cooldown_id(), true)
		CursorManager.update_vertical_tint_progress(tint_progress * 100.0)

@tool
extends EquippableItem
class_name Weapon
## The base class for all equippable weapons in the game.

@export var particle_emission_extents: Vector2:
	set(new_value):
		particle_emission_extents = new_value
		if debug_emission_box:
			_debug_update_particle_emission_box()
@export var particle_emission_origin: Vector2:
	set(new_value):
		particle_emission_origin = new_value
		if debug_emission_box:
			_debug_update_particle_emission_box()

@onready var anim_player: AnimationPlayer = $AnimationPlayer ## The animation controller for this weapon.
@onready var debug_emission_box: Polygon2D = get_node_or_null("DebugEmissionBox")

var pullout_delay_timer: Timer = TimerHelpers.create_one_shot_timer(self) ## The timer managing the delay after a weapon is equipped before it can be used.
var overhead_ui: PlayerOverheadUI ## The UI showing the overhead stat changes (like reloading/charging) in progress. Only applicable and non-null for players.
var preloaded_sounds: Array[StringName] = [] ## The sounds kept in memory while this weapon scene is alive that must be dereferenced upon exiting the tree.
var hold_time: float = 0 ## How long we have been holding down the trigger for.


func _ready() -> void:
	super._ready()

	if source_entity is Player:
		overhead_ui = source_entity.overhead_ui

## When this scene is ultimately freed, unregister any preloaded audio references.
func _exit_tree() -> void:
	AudioPreloader.unregister_sounds_from_ids(preloaded_sounds)

## Decrements the current hold time for the weapon.
func decrement_hold_time(delta: float) -> void:
	hold_time = max(0, (hold_time - (delta * stats.charge_loss_mult)))

## Gets a current cooldown level from the auto decrementer based on the cooldown id.
func get_cooldown() -> float:
	return source_entity.inv.auto_decrementer.get_cooldown(stats.get_cooldown_id())

## Adds a cooldown to the auto decrementer for the current cooldown id.
func add_cooldown(duration: float, title: String = "default") -> void:
	source_entity.inv.auto_decrementer.add_cooldown(stats.get_cooldown_id(), duration, title)

## Updates the charge bar over the entity's head with the current charge progress.
func _update_overhead_charge_ui() -> void:
	if not overhead_ui:
		return

	var fraction: float = clampf(hold_time / stats.s_mods.get_stat("min_charge_time"), 0, 1)
	var progress: int = int(fraction * 100)

	overhead_ui.update_charge_progress(progress)

## Resets the visual animation state of the weapon scene to its default.
func reset_animation_state(reset_anim_name: StringName = &"RESET") -> void:
	anim_player.play(reset_anim_name)
	anim_player.stop()

#region Debug
## Edits warnings for the editor for easier debugging.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	for sprite_node: Node2D in sprites_to_tint:
		if not sprite_node.material is ShaderMaterial:
			warnings.append("Weapon sprites in the \"sprites_to_tint\" must have the \"TintAndGlow\" shader applied.")
			break
	return warnings

func _debug_update_particle_emission_box() -> void:
	if debug_emission_box == null or not Engine.is_editor_hint():
		return
	var top_left: Vector2 = particle_emission_origin - particle_emission_extents
	var bottom_right: Vector2 = particle_emission_origin + particle_emission_extents
	var points: Array[Vector2] = [
		top_left, Vector2(bottom_right.x, top_left.y), bottom_right, Vector2(top_left.x, bottom_right.y)
		]
	debug_emission_box.polygon = points
#endregion

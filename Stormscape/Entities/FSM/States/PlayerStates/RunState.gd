extends State
class_name RunState
## Handles when the dynamic entity is moving, including both running and sprinting.

@export_subgroup("Animation Constants")
@export var default_run_anim_time_scale: float = 1.5 ## How fast the run anim should play before stat mods.
@export var max_run_anim_time_scale: float = 4.0 ## How fast the run anim can play at most.

const PLAYER_SPRINT_SOUND_THRESHOLD: int = 25 ## The extra speed above the "max_speed" stat the player must be moving to trigger the sprint sound.
var sprint_audio_inst: AudioPlayerInstance ## A reference to the current sprint audio player (if player).
var previous_pos: Vector2 ## The previous position of the entity as of the last frame. Used for speed calculations to determine if sprint audio should play for the player.
var actual_movement_speed: float = 0 ## The movement speed determined by change in distance over time.


func _init() -> void:
	state_id = "run"

func enter() -> void:
	previous_pos = entity.global_position
	entity.facing_component.travel_anim_tree("run")

func exit() -> void:
	_stop_sprint_sound()

func state_physics_process(delta: float) -> void:
	_do_entity_run(delta)
	_animate()

## Besides appropriately applying velocity to the parent entity, this checks and potentially activates sprinting
## as well as calculates what vector the animation state machine should receive to play
## the matching directional anim.
func _do_entity_run(delta: float) -> void:
	var stats: StatModsCache = entity.stats
	actual_movement_speed = (entity.global_position - previous_pos).length() / (delta * (1.0 / Engine.time_scale))
	previous_pos = entity.global_position

	# Check if we should stop the sprint sound based on movement speed
	if ceil(actual_movement_speed) <= floor(stats.get_stat("max_speed")):
		_stop_sprint_sound()

	StateFunctions.handle_run_logic(delta, entity, controller, stats, max_run_anim_time_scale, default_run_anim_time_scale)

	# Do sprinting sounds if we are moving fast enough afterwards
	if (entity is Player) and (actual_movement_speed > (stats.get_stat("max_speed") + PLAYER_SPRINT_SOUND_THRESHOLD)):
		_play_sprint_sound()

func _animate() -> void:
	entity.facing_component.update_blend_position("run")

func _play_sprint_sound() -> void:
	if not AudioManager.is_inst_valid(sprint_audio_inst):
		sprint_audio_inst = AudioManager.play_global("player_sprint_wind", 0.45, false, -1, entity)

func _stop_sprint_sound() -> void:
	if AudioManager.is_inst_valid(sprint_audio_inst):
		AudioManager.stop_audio_player(sprint_audio_inst.player, 0.3, true)

@tool
extends Entity
class_name DynamicEntity
## An entity that has vitals stats and can move.
##
## This should be used by things like players, enemies, moving environmental entities, etc.
## This should not be used by things like weapons or trees.

@onready var fsm: StateMachine = $StateMachine ## The FSM controlling the entity.
@onready var stamina_component: StaminaComponent = get_node_or_null("StaminaComponent") ## The component in charge of entity stamina and hunger.
@onready var anim_tree: AnimationTree = $AnimationTree ## The animation tree controlling this entity's animation states.
@onready var facing_component: FacingComponent = $FacingComponent ## The component in charge of choosing the entity animation directions.
@onready var step_dust_particles: CPUParticles2D = get_node_or_null("StepDustParticles") ## The optional particles that could spawn when taking a step.

var time_snare_counter: float = 0 ## The ticker that slows down delta when under a time snare.
var snare_factor: float = 0 ## Multiplier for delta time during time snares.
var snare_timer: Timer ## A reference to a timer that might currently be tracking a time snare instance.


## Edits editor warnings for easier debugging.
func _get_configuration_warnings() -> PackedStringArray:
	if get_node_or_null("%EntitySprite") == null or not %EntitySprite is EntitySprite:
		return ["This entity must have an EntitySprite typed sprite node. Make sure its name is unique with a %."]
	return []

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	super(delta)

	fsm.controller.controller_process(delta)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if snare_factor > 0:
		time_snare_counter += delta * snare_factor
		while time_snare_counter > delta:
			time_snare_counter -= delta
			fsm.controller.controller_physics_process(delta)
	else:
		fsm.controller.controller_physics_process(delta)

## Sends a request to the move fsm for entering the stun state using a given duration.
func request_stun(duration: float) -> void:
	fsm.controller.notify_requested_stun(duration)

## Requests changing the knockback vector using the incoming knockback.
func request_knockback(knockback: Vector2) -> void:
	fsm.controller.notify_requested_knockback(knockback)

## Requests to start a time snare effect on the entity.
func request_time_snare(factor: float, snare_time: float) -> void:
	if snare_timer != null and is_instance_valid(snare_timer) and not snare_timer.is_stopped():
		snare_timer.stop()
		snare_timer.wait_time = max(0.001, snare_time)
		snare_timer.start()
	else:
		var timeout_callable: Callable = Callable(func() -> void:
			snare_factor = 0
			snare_timer.queue_free()
			)
		snare_timer = TimerHelpers.create_one_shot_timer(self, max(0.001, snare_time), timeout_callable)
		snare_timer.start()

	snare_factor = factor

## Requests performing whatever dying logic is given in the move fsm.
func die() -> void:
	fsm.controller.die()

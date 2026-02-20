extends State
class_name KnockbackState
## Handles when an entity is only being knocked back.


func _init() -> void:
	state_id = "knockback"

func enter() -> void:
	entity.facing_component.travel_anim_tree("idle")

func exit() -> void:
	pass

func state_physics_process(delta: float) -> void:
	_do_entity_knockback(delta)
	_animate()

func _do_entity_knockback(delta: float) -> void:
	var stats: StatModsCache = entity.stats

	if controller.knockback_vector.length() > 0:
		entity.velocity = controller.knockback_vector

	if entity.velocity.length() > (stats.get_stat("friction") * delta): # Slowing down
		var slow_rate_vector: Vector2 = entity.velocity.normalized() * (stats.get_stat("friction") * delta)
		entity.velocity -= slow_rate_vector
	else: # No motion
		controller.knockback_vector = Vector2.ZERO
		entity.velocity = Vector2.ZERO
		controller.notify_knockback_ended()

	entity.move_and_slide()
	StateFunctions.handle_rigid_entity_collisions(entity, controller)

func _animate() -> void:
	entity.facing_component.update_blend_position("idle")

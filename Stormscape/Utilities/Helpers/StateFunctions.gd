class_name StateFunctions
## Functions that are common to several states that can be easily reused.


## Handles the decision logic for choosing run vs sprint and moves the entity accordingly.
static func handle_run_logic(delta: float, entity: Entity, controller: DynamicController,
								stats: StatModsCache, max_anim_scale: float, default_anim_scale: float,
								extra_run_mult: float = 1.0, extra_sprint_mult: float = 1.0) -> void:
	if controller.knockback_vector.length() > 0:
		entity.velocity = controller.knockback_vector

	if controller.get_movement_vector() == Vector2.ZERO: # We have no input and should slow to a stop
		if entity.velocity.length() > (stats.get_stat("friction") * delta): # No input, still slowing
			var slow_rate_vector: Vector2 = entity.velocity.normalized() * (stats.get_stat("friction") * delta)
			entity.velocity -= slow_rate_vector
		else: # No input, stopped
			controller.knockback_vector = Vector2.ZERO
			entity.velocity = Vector2.ZERO
			controller.notify_stopped_moving()
	elif controller.knockback_vector.length() == 0: # We have input and there is no knockback
		if controller.get_should_sprint() and entity.stamina_component.use_stamina(entity.stats.get_stat("sprint_stamina_usage") * delta):
			apply_sprint_movement(delta, entity, controller, stats, max_anim_scale, default_anim_scale, extra_sprint_mult)
		else:
			apply_non_sprint_movement(delta, entity, controller, stats, max_anim_scale, default_anim_scale, extra_run_mult)

	entity.move_and_slide()
	StateFunctions.handle_rigid_entity_collisions(entity, controller)

## Applies sprint movement to the entity's velocity.
static func apply_sprint_movement(delta: float, entity: Entity, controller: DynamicController,
									stats: StatModsCache, max_anim_scale: float, default_anim_scale: float,
									extra_multiplier: float = 1.0) -> void:
	# Update anim speed multiplier
	var sprint_mult: float = stats.get_stat("sprint_multiplier")
	var max_speed: float = stats.get_stat("max_speed")
	var max_speed_change_factor: float = max_speed / stats.get_original_stat("max_speed")
	var anim_speed_mult: float = sprint_mult * (max_speed_change_factor)
	var final_anim_time_scale: float = min(max_anim_scale, default_anim_scale * anim_speed_mult)
	entity.facing_component.update_time_scale("run", final_anim_time_scale)

	var acceleration: float = stats.get_stat("acceleration")
	entity.velocity += (controller.get_movement_vector() * acceleration * sprint_mult * delta * extra_multiplier)
	entity.velocity = entity.velocity.limit_length(max_speed * sprint_mult)

## Applies non-sprint movement to the entity's velocity.
static func apply_non_sprint_movement(delta: float, entity: Entity, controller: DynamicController,
										stats: StatModsCache, max_anim_scale: float,
										default_anim_scale: float, extra_multiplier: float = 1.0) -> void:
	var anim_time_scale: float = min(max_anim_scale, default_anim_scale * (stats.get_stat("max_speed") / stats.get_original_stat("max_speed")))
	entity.facing_component.update_time_scale("run", anim_time_scale)

	var acceleration: float = stats.get_stat("acceleration")
	entity.velocity += (controller.get_movement_vector() * acceleration * delta * extra_multiplier)
	entity.velocity = entity.velocity.limit_length(stats.get_stat("max_speed"))

## Handles moving rigid entities that we collided with in the last frame. Returns if we did collide.
static func handle_rigid_entity_collisions(entity: Entity, controller: DynamicController) -> bool:
	var hit_rigid_entity: bool = false
	for i: int in entity.get_slide_collision_count():
		var c: KinematicCollision2D = entity.get_slide_collision(i)
		var collider: Object = c.get_collider()
		if collider is RigidEntity:
			collider.apply_central_impulse(-c.get_normal().normalized() * entity.velocity.length() / (10 / (entity.stats.get_stat("run_collision_impulse_factor"))))
			hit_rigid_entity = true

		# End any knockback if we ran into something
		if i == 0:
			controller.knockback_vector = Vector2.ZERO

	return hit_rigid_entity

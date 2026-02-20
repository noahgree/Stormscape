extends Line2D
class_name Hitscan
## The base class for all hitscan objects. These emit as beams or rays from the source weapon instead of traveling along a path.

@export var effect_source: EffectSource ## The effect to be applied when this ray hits an effect receiver.
@export var source_entity: Entity ## The entity that the effect was produced by.

@onready var start_particles: CPUParticles2D = $StartParticles ## The particles emitting at the source point (at the weapon).
@onready var impact_particles: CPUParticles2D = $ImpactParticles ## The particles emitting at each impact site.
@onready var beam_particles: CPUParticles2D = $BeamParticles ## The particles emitting along the beam or ray of the hitscan.

var stats: HitscanStats ## The stats driving this hitscan.
var sc: StatModsCache ## The stat mods resource used to retrieve modified, updated stats for calculations and logic.
var source_ii: ProjWeaponII ## The weapon item instance that produced this hitscan.
var rotation_offset: float ## The offset to rotate the hitscan by, determined by the source weapon.
var lifetime_timer: Timer = TimerHelpers.create_one_shot_timer(self, -1, queue_free) ## The timer tracking lifetime left before freeing.
var effect_tick_timer: Timer = TimerHelpers.create_one_shot_timer(self) ## The timer delaying the intervals of applying the effect source.
var debug_rays: Array[Dictionary] = [] ## The debug arrays collected during each hit.
var end_point: Vector2 ## The end point of the hitscan ray and visuals. Updated by the ray scan.
var is_hitting_something: bool = false: ## Whether at any point along the hitscan we are hitting something.
	set(new_value):
		is_hitting_something = new_value
		impact_particles.emitting = new_value
var impacted_nodes: Dictionary[Node, CPUParticles2D] = {} ## The nodes being hit at current moment along with their hit particles.
var multishot_id: int = 0 ## The id passed in on creation that relates the sibling hitscans spawned on the same multishot barrage.


## Creates a hitscan scene, assigns its passed in parameters, then returns it.
static func create(source_wpn: ProjectileWeapon, rot_offset: float) -> Hitscan:
	var hitscan: Hitscan = source_wpn.stats.hitscan_scn.instantiate()
	hitscan.global_position = source_wpn.proj_origin_node.global_position
	hitscan.rotation_offset = rot_offset
	hitscan.effect_source = source_wpn.stats.effect_source
	hitscan.source_entity = source_wpn.source_entity
	hitscan.stats = source_wpn.stats.hitscan_logic
	hitscan.sc = source_wpn.ii.sc

	hitscan.source_ii = source_wpn.ii
	return hitscan

func _draw() -> void:
	if not DebugFlags.show_hitscan_rays:
		return

	for ray: Dictionary[String, Variant] in debug_rays:
		var from_pos: Vector2 = to_local(ray["from"])
		var to_pos: Vector2 = to_local(ray["to"])
		if ray["hit"]:
			to_pos = to_local(ray["hit_position"])
		var color: Color = Color(0, 1, 0, 0.4) if ray["hit"] else Color(1, 0, 0, 0.25)

		draw_line(from_pos, to_pos, color, 1)

		if ray["hit"]:
			draw_circle(to_pos, 2, color)

func _ready() -> void:
	if not stats.continuous_beam:
		var dur_stat: float = source_ii.stats.firing_duration
		lifetime_timer.start(max(0.05, dur_stat))

	start_particles.emitting = true
	_set_up_visual_fx()

func _set_up_visual_fx() -> void:
	if not stats.override_vfx_defaults:
		return

	width = stats.hitscan_max_width
	width_curve = stats.hitscan_width_curve
	start_particles.color_ramp.set_color(0, stats.start_particle_color)
	start_particles.color_ramp.set_color(1, stats.start_particle_color)
	start_particles.color = stats.start_particle_color * (stats.glow_amount + 1.0)
	start_particles.amount = int(start_particles.amount * stats.start_particle_mult)
	impact_particles.color_ramp.set_color(0, stats.impact_particle_color)
	impact_particles.color_ramp.set_color(1, stats.impact_particle_color)
	impact_particles.color = stats.impact_particle_color * (stats.glow_amount + 1.0)
	impact_particles.amount = int(impact_particles.amount * stats.impact_particle_mult)
	beam_particles.color_ramp.set_color(0, stats.beam_particle_color)
	beam_particles.color_ramp.set_color(1, stats.beam_particle_color)
	beam_particles.color = stats.beam_particle_color * (stats.glow_amount + 1.0)
	beam_particles.amount = int(beam_particles.amount * stats.beam_particle_mult)
	default_color = stats.beam_color * (stats.glow_amount + 1.5)

func _physics_process(_delta: float) -> void:
	var equipped_item: EquippableItem = null
	if is_instance_valid(source_entity.hands.equipped_item):
		equipped_item = source_entity.hands.equipped_item

	if equipped_item != null and equipped_item.ii == source_ii:
		global_position = equipped_item.proj_origin_node.global_position.rotated(equipped_item.rotation)
		global_rotation = equipped_item.global_rotation + rotation_offset

		_find_target_receivers()

		if points.size() > 1:
			points[1] = end_point
			beam_particles.position = points[1] * 0.5
			beam_particles.emission_rect_extents.x = points[1].length() * 0.5
			beam_particles.emitting = true
		else:
			points = [points[0], end_point]
	else:
		queue_free()

	if DebugFlags.show_hitscan_rays:
		queue_redraw()

## Talks to the physics server to cast collider shapes forward to look for receivers.
func _find_target_receivers() -> void:
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var cast_direction: Vector2 = Vector2.RIGHT.rotated(rotation)
	var candidates: Array[Node] = []
	var contact_positions: Array[Vector2] = []

	if DebugFlags.show_hitscan_rays:
		debug_rays.clear()

	var from_pos: Vector2 = global_position
	var to_pos: Vector2 = global_position + (cast_direction * stats.hitscan_max_distance)

	var exclusion_list: Array[RID] = [source_entity.get_rid()]
	for child: Node in source_entity.get_children():
		if child is Area2D:
			exclusion_list.append(child.get_rid())

	var remaining_pierces: int = int(sc.get_stat("hitscan_pierce_count"))
	var pierce_list: Dictionary[Node, Variant] = {}

	while remaining_pierces >= 0:
		var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.new()
		query.from = from_pos
		query.to = to_pos
		query.exclude = exclusion_list
		query.collision_mask = effect_source.scanned_phys_layers
		query.collide_with_bodies = true
		query.collide_with_areas = true
		var result: Dictionary[Variant, Variant] = space_state.intersect_ray(query)

		var debug_ray_info: Dictionary[String, Variant]
		if DebugFlags.show_hitscan_rays: debug_ray_info = { "from": from_pos, "to": to_pos, "hit": false, "hit_position": to_pos }

		if result:
			var obj: Node = result.collider
			var collision_point: Vector2 = result.position

			pierce_list[obj] = result

			is_hitting_something = true
			end_point = to_local(collision_point)

			impact_particles.position = to_local(collision_point)
			impact_particles.global_rotation = result.normal.angle()

			if obj and obj is EffectReceiverComponent:
				candidates.append(obj)
				contact_positions.append(collision_point)

				from_pos = collision_point

				exclusion_list.append(obj.get_rid())
				exclusion_list.append(obj.get_parent().get_rid())

				remaining_pierces -= 1

				debug_ray_info["hit"] = true
				debug_ray_info["hit_position"] = result.position
			else:
				if obj:
					exclusion_list.append(obj.get_rid())
					if obj is not DynamicEntity and obj is not RigidEntity and obj is not StaticEntity:
						remaining_pierces = -1
				debug_ray_info["to"] = collision_point
		else:
			is_hitting_something = false
			remaining_pierces = -1
		debug_rays.append(debug_ray_info)
		if remaining_pierces > 0 or not result:
			end_point = to_local(to_pos)

	if effect_tick_timer.is_stopped():
		for i: int in range(candidates.size()):
			var receiver_index: int = _select_closest_receiver(candidates)
			var receiver: Node = candidates[receiver_index]
			if receiver != null:
				_start_being_handled(receiver, contact_positions[receiver_index])

				candidates.remove_at(receiver_index)
				contact_positions.remove_at(receiver_index)

				effect_tick_timer.stop()

				var original_interval: float = sc.get_original_stat("hitscan_effect_interval")
				if original_interval == -1:
					effect_tick_timer.start(1000.0)
				else:
					var effect_time: float = sc.get_stat("hitscan_effect_interval")
					effect_tick_timer.start(effect_time)

	_update_impact_particles(pierce_list)

## Give the possible targets, this selects the closest one using a faster 'distance squared' method.
func _select_closest_receiver(targets: Array[Node]) -> int:
	var closest_target: int = 0
	var closest_distance_squared: float = INF
	for i: int in range(targets.size()):
		var distance_squared: float = global_position.distance_squared_to(targets[i].global_position)
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_target = i
	return closest_target

## Updates the particles that spawn at each impacted node.
func _update_impact_particles(pierce_list: Dictionary) -> void:
	for node: Node in pierce_list.keys():
		if node in impacted_nodes:
			impacted_nodes[node].position = to_local(pierce_list[node].position)
			impacted_nodes[node].global_rotation = pierce_list[node].normal.angle()
		else:
			var particles: CPUParticles2D = impact_particles.duplicate()
			particles.position = to_local(pierce_list[node].position)
			particles.global_rotation = pierce_list[node].normal.angle()
			impacted_nodes[node] = particles
			add_child(particles)
			particles.emitting = true

			node.tree_exiting.connect(func() -> void:
				var particles_node: CPUParticles2D = impacted_nodes.get(node)
				if is_instance_valid(particles_node):
					particles_node.queue_free()
				impacted_nodes.erase(node))

	for node: Variant in impacted_nodes.keys():
		if not node in pierce_list.keys():
			impacted_nodes[node].queue_free()
			impacted_nodes.erase(node)

## Overrides parent method. When we overlap with an entity who can accept effect sources,
## pass the effect source to that entity's handler. Note that the effect source is duplicated
## on hit so that we can include unique info like move dir.
func _start_being_handled(handling_area: EffectReceiverComponent, contact_point: Vector2) -> void:
	effect_source = effect_source.duplicate()
	effect_source.multishot_id = multishot_id
	var modified_effect_src: EffectSource = _get_effect_source_adjusted_for_falloff(effect_source, contact_point)
	modified_effect_src.movement_direction = Vector2(cos(rotation), sin(rotation)).normalized()
	effect_source.contact_position = contact_point
	handling_area.handle_effect_source(modified_effect_src, source_entity, source_ii)

## When we hit a handling area during a hitscan, we apply falloff to the components of the effect source.
func _get_effect_source_adjusted_for_falloff(effect_src: EffectSource, contact_point: Vector2) -> EffectSource:
	var falloff_effect_src: EffectSource = effect_src.duplicate()
	var apply_to_bad: bool = stats.bad_effects_falloff
	var apply_to_good: bool = stats.good_effects_falloff

	var point_to_sample: float = float(global_position.distance_to(contact_point) / sc.get_stat("hitscan_max_distance"))
	var sampled_point: float = stats.hitscan_effect_falloff.sample_baked(point_to_sample)
	var falloff_mult: float = max(0.05, sampled_point)

	if apply_to_bad:
		falloff_effect_src.base_damage = int(min(falloff_effect_src.base_damage, ceil(falloff_effect_src.base_damage * falloff_mult)))

	if apply_to_good:
		falloff_effect_src.base_healing = int(min(falloff_effect_src.base_healing, ceil(falloff_effect_src.base_healing * falloff_mult)))

	return falloff_effect_src

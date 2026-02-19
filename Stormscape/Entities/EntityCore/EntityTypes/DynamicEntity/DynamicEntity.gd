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


#region Save & Load
func _on_save_game(save_data: Array[SaveData]) -> void:
	var data: DynamicEntityData = DynamicEntityData.new()

	data.scene_path = scene_file_path

	data.position = global_position
	data.velocity = self.velocity

	data.stat_mods = stats.stat_mods
	data.wearables = wearables

	data.sprite_frames_path = sprite.sprite_frames.resource_path

	data.health = health_component.health
	data.shield = health_component.shield
	data.armor = health_component.armor

	data.facing_dir = facing_component.facing_dir
	data.knockback_vector = fsm.controller.knockback_vector

	if stamina_component != null:
		data.stamina = stamina_component.stamina
		data.can_use_stamina = stamina_component.can_use_stamina
		data.stamina_to_hunger_count = stamina_component.stamina_to_hunger_count
		data.hunger_bars = stamina_component.hunger_bars
		data.can_use_hunger_bars = stamina_component.can_use_hunger_bars

	if inv != null:
		for item: InvItemStats in inv.inv:
			if item != null and item.stats is WeaponStats:
				item.stats.weapon_mods_need_to_be_readded_after_save = true
		data.inv = inv.inv
	if item_receiver != null:
		data.pickup_range = item_receiver.pickup_range

	data.loot = loot.duplicate() if loot else null

	data.snare_factor = snare_factor
	if snare_timer != null: data.snare_time_left = snare_timer.time_left
	else: data.snare_time_left = 0

	if self.name == "Player":
		data.is_player = true
		data.active_slot_index = %HotbarHUD.active_slot.index

	save_data.append(data)

func _on_before_load_game() -> void:
	if not self is Player:
		# In case we try to drop inventory on death
		if inv:
			inv.clear_inventory()
		queue_free()
	else:
		WearablesManager.removal_all_wearables(self)

func _is_instance_on_load_game(data: DynamicEntityData) -> void:
	global_position = data.position
	self.velocity = data.velocity

	if not data.is_player:
		Globals.world_root.add_child(self)

	stats.stat_mods = data.stat_mods
	wearables = data.wearables
	stats.reinit_on_load()

	sprite.sprite_frames = load(data.sprite_frames_path)

	health_component.just_loaded = true
	health_component.health = data.health
	health_component.shield = data.shield
	health_component.armor = data.armor

	facing_component.facing_dir = data.facing_dir
	fsm.controller.knockback_vector = data.knockback_vector
	fsm.controller.update_animation()

	if stamina_component != null:
		stamina_component.stamina = data.stamina
		stamina_component.can_use_stamina = data.can_use_stamina
		stamina_component.stamina_to_hunger_count = data.stamina_to_hunger_count
		stamina_component.hunger_bars = data.hunger_bars
		stamina_component.can_use_hunger_bars = data.can_use_hunger_bars

	if inv != null:
		inv.call_deferred("fill_inventory", data.inv)
	if item_receiver != null:
		item_receiver.pickup_range = data.pickup_range

	loot = data.loot
	if loot:
		loot.initialize(self)

	snare_factor = 0
	if snare_timer != null: snare_timer.queue_free()
	if data.snare_time_left > 0: request_time_snare(data.snare_factor, data.snare_time_left)

	if data.is_player:
		%HotbarHUD.change_active_slot_to_index_relative_to_full_inventory_size(data.active_slot_index)
		WearablesManager.re_add_all_wearables(self)
#endregion

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

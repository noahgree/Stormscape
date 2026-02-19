@icon("res://Utilities/Debug/EditorIcons/effect_receiver_component.svg")
@tool
extends Area2D
class_name EffectReceiverComponent
## A general effect source receiver that passes the appropriate parts of the effect to handlers, but only if
## they exist as children. This node must have an attached collision shape to define where effects are received.
## This node's collision also determines what part of this entity must enter the DetectionComponent
## of another entity before we know about that entity's presence.
##
## Add specific effect handlers as children of this node to be able to receive those effects on the entity.
## For all intensive purposes, this is acting as a hurtbox component via its receiver area.

@export var can_receive_status_effects: bool = true ## Whether the affected entity can have status effects applied at all. This does not include base damage and base healing. This also determines if the entity can have its stats modded.
@export var absorb_full_hit: bool = false ## When true, any weapon's hitbox that sends an effect to this receiver will be disabled for the remainder of the attack afterwards. Useful for when you want something like a tree to take the full hit and not let an axe keep swinging through to hit enemies behind it.
@export_group("Source Filtering")
@export var filter_source_types: bool = false ## When true, only allow matching source types as specified in the below array.
@export var allowed_source_types: Array[Globals.EffectSourceSourceType] = [] ## The list of sources an effect source can come from in order to affect this effect receiver (only when filter_source_types is true).
@export var filter_source_tags: bool = false ## When true, only allow matching source tags as specified in the below array.
@export var allowed_source_tags: Array[String] = [] ## Effect sources must have a tag that matches something in this array in order to be handled when the filter_source_tags is set to true.
@export_group("Connected Nodes")
@export var affected_entity: Entity  ## The connected entity to be affected by the effects be received.
@export var dmg_handler: DmgHandler ## The dmg handler of the affected entity.
@export var heal_handler: HealHandler ## The heal handler of the affected entity.
@export_group("Effect Handlers")
@export var storm_syndrome_handler: StormSyndromeHandler ## The storm syndrome of the affected entity.
@export var knockback_handler: KnockbackHandler ## The knockback of the affected entity.
@export var stun_handler: StunHandler ## The stun handler of the affected entity.
@export var poison_handler: PoisonHandler ## The poison handler of the affected entity.
@export var regen_handler: RegenHandler ## The regen handler of the affected entity.
@export var frostbite_handler: FrostbiteHandler ## The frostbite handler of the affected entity.
@export var burning_handler: BurningHandler ## The burning handler of the affected entity.
@export var time_snare_handler: TimeSnareHandler ## The time snare handler of the affected entity.
@export var life_steal_handler: LifeStealHandler ## The life steal handler of the affected entity.

@onready var tool_script: RefCounted = load("res://Entities/Components/EffectComponents/EffectReceiverComponent/EffectReceiverTool.gd").new(self) ## The tool script node that helps auto-assign export nodes relative to this receiver.

var current_impact_sounds: Array[int] = [] ## The current impact sounds being played and held onto by this effect receiver.
var most_recent_multishot_id: int = 0 ## The most recent multishot id to be received. Prevents multishots from stacking status effects.


## Asserts that the affected entity has been set for easy debugging, then sets the monitoring to off for
## performance reasons in case it was changed in the editor. It also ensures the collision layer is the same as the
## affected entity so that the effect sources only see it when they should.
func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if not affected_entity.is_node_ready():
		await affected_entity.ready

	collision_layer = affected_entity.collision_layer
	collision_mask = 0
	monitoring = false

## Handles an incoming effect source, passing it to present receivers for further processing before changing
## entity stats.
func handle_effect_source(effect_source: EffectSource, source_entity: Entity, source_weapon: WeaponStats,
							process_status_effects: bool = true) -> void:
	# --- Applying Cam FX & Hit Sound ----
	_handle_cam_fx(effect_source)
	_handle_impact_sound(effect_source)

	# --- Changing Cursor to Reflect Hit ---
	if source_entity and source_entity is Player and not affected_entity is Player:
		CursorManager.change_cursor(null, "hit")

	# --- Filtering Source Types & Tags ---
	if filter_source_types and (effect_source.source_type not in allowed_source_types):
		return
	if filter_source_tags:
		var match_found: bool = false
		for tag: String in effect_source.source_tags:
			if tag in allowed_source_tags:
				match_found = true
		if not match_found:
			return

	# --- Checking if Sender is Passive or Receiver Can't Receive Effect Sources ---
	if (source_entity and source_entity.team == Globals.Teams.PASSIVE) or not _check_if_can_receive_effect_sources_and_status_effects():
		if affected_entity.loot:
			affected_entity.loot.handle_hit()
		return

	# --- Spawning Impact VFX ---
	if effect_source.impact_vfx != null:
		var vfx: Node2D = effect_source.impact_vfx.instantiate()
		vfx.global_position = affected_entity.global_position
		add_child(vfx)

	# --- Validating Source Entity ---
	if not source_entity:
		return

	# --- Triggering Loot Component ---
	if affected_entity.loot and not affected_entity.loot.require_dmg_on_hit:
		affected_entity.loot.handle_hit()

	# --- Applying Base Damage & Base Healing ---
	var xp: int = 0
	var do_hitflash: bool = false
	var source_level: int = source_weapon.level if source_weapon else 1
	if effect_source.base_damage > 0 and dmg_handler != null:
		if _check_same_team(source_entity) and _check_if_bad_effects_apply_to_allies(effect_source):
			dmg_handler.handle_instant_damage(effect_source, source_level, _get_life_steal(effect_source, source_entity))
			do_hitflash = true
		elif not _check_same_team(source_entity) and _check_if_bad_effects_apply_to_enemies(effect_source):
			xp = dmg_handler.handle_instant_damage(effect_source, source_level, _get_life_steal(effect_source, source_entity))
			do_hitflash = true

	if effect_source.base_healing > 0 and heal_handler != null:
		if _check_same_team(source_entity) and _check_if_good_effects_apply_to_allies(effect_source):
			xp = heal_handler.handle_instant_heal(effect_source, effect_source.heal_affected_stats, source_level)
			do_hitflash = true
		elif not _check_same_team(source_entity) and _check_if_good_effects_apply_to_enemies(effect_source):
			heal_handler.handle_instant_heal(effect_source, effect_source.heal_affected_stats, source_level)
			do_hitflash = true

	if do_hitflash:
		affected_entity.sprite.start_hitflash(effect_source.hit_flash_color, false)

	# --- Applying Resulting Weapon XP ---
	if source_entity is Player and source_weapon and is_instance_valid(source_weapon):
		var xp_to_add: int = ceili(WeaponII.EFFECT_AMOUNT_XP_MULT * xp)
		source_weapon.add_xp(xp_to_add)

	# --- Start of Status Effect Processing Chain ---
	if process_status_effects:
		if can_receive_status_effects:
			if (effect_source.multishot_id == -1) or (effect_source.multishot_id != most_recent_multishot_id):
				most_recent_multishot_id = effect_source.multishot_id

				if knockback_handler:
					knockback_handler.contact_position = effect_source.contact_position
					knockback_handler.effect_movement_direction = effect_source.movement_direction
					knockback_handler.is_source_moving_type = (effect_source.source_type == Globals.EffectSourceSourceType.FROM_PROJECTILE)

				_check_status_effect_team_logic(effect_source, source_entity)

## Checks if each status effect in the array applies to this entity via team logic, then passes it to be unpacked.
func _check_status_effect_team_logic(effect_source: EffectSource, source_entity: Entity) -> void:
	var is_same_team: bool = _check_same_team(source_entity)
	var bad_effects_to_enemies: bool = not is_same_team and _check_if_bad_effects_apply_to_enemies(effect_source)
	var good_effects_to_enemies: bool = not is_same_team and _check_if_good_effects_apply_to_enemies(effect_source)
	var bad_effects_to_allies: bool = is_same_team and _check_if_bad_effects_apply_to_allies(effect_source)
	var good_effects_to_allies: bool = is_same_team and _check_if_good_effects_apply_to_allies(effect_source)

	for status_effect: StatusEffect in effect_source.status_effects:
		if status_effect:
			var applies_to_target: bool = (status_effect.is_bad_effect and (bad_effects_to_enemies or bad_effects_to_allies)) or (not status_effect.is_bad_effect and (good_effects_to_enemies or good_effects_to_allies))

			if applies_to_target:
				handle_status_effect(status_effect)

## Checks for untouchability and handles the stat mods in the status effect.
## Then it passes the effect to have its main logic handled if it needs a handler.
func handle_status_effect(status_effect: StatusEffect) -> void:
	if not _check_if_applicable_entity_type_for_status_effect(status_effect) or not _check_if_can_receive_effect_sources_and_status_effects():
		return
	if (affected_entity.effects.is_untouchable()) and (status_effect.is_bad_effect):
		return

	for effect_to_stop: String in status_effect.effects_to_stop:
		affected_entity.effects.request_effect_removal_for_all_sources(effect_to_stop)

	affected_entity.effects.handle_status_effect(status_effect)
	_pass_effect_to_handler(status_effect)

	if affected_entity.effects.is_untouchable():
		affected_entity.effects.remove_all_bad_status_effects()

## Passes the status effect to a handler if one is needed for additional logic handling.
func _pass_effect_to_handler(status_effect: StatusEffect) -> void:
	if status_effect is StormSyndromeEffect:
		if storm_syndrome_handler: storm_syndrome_handler.handle_storm_syndrome(status_effect)
		else: return
	if status_effect is KnockbackEffect:
		if knockback_handler: knockback_handler.handle_knockback(status_effect)
		else: return
	if status_effect is StunEffect:
		if stun_handler: stun_handler.handle_stun(status_effect)
		else: return
	if status_effect is PoisonEffect:
		if poison_handler: poison_handler.handle_poison(status_effect)
		else: return
	if status_effect is RegenEffect:
		if regen_handler: regen_handler.handle_regen(status_effect)
		else: return
	if status_effect is FrostbiteEffect:
		if frostbite_handler: frostbite_handler.handle_frostbite(status_effect)
		else: return
	if status_effect is BurningEffect:
		if burning_handler: burning_handler.handle_burning(status_effect)
		else: return
	if status_effect is TimeSnareEffect:
		if time_snare_handler: time_snare_handler.handle_time_snare(status_effect)
		else: return

	if not ((affected_entity is not Player) and status_effect.only_cue_on_player_hit):
		AudioManager.play_2d(status_effect.audio_to_play, affected_entity.global_position)

## Checks if the affected entity is on the same team as the producer of the effect source.
func _check_same_team(source_entity: Entity) -> bool:
	return affected_entity.team & source_entity.team != 0

## Checks if the effect source should do bad effects to allies.
func _check_if_bad_effects_apply_to_allies(effect_source: EffectSource) -> bool:
	return effect_source.bad_effect_affected_teams & Globals.BadEffectAffectedTeams.ALLIES != 0

## Checks if the effect source should do bad effects to enemies.
func _check_if_bad_effects_apply_to_enemies(effect_source: EffectSource) -> bool:
	return effect_source.bad_effect_affected_teams & Globals.BadEffectAffectedTeams.ENEMIES != 0

## Checks if the effect source should do good effects to allies.
func _check_if_good_effects_apply_to_allies(effect_source: EffectSource) -> bool:
	return effect_source.good_effect_affected_teams & Globals.GoodEffectAffectedTeams.ALLIES != 0

## Checks if the effect source should do good effects to enemies.
func _check_if_good_effects_apply_to_enemies(effect_source: EffectSource) -> bool:
	return effect_source.good_effect_affected_teams & Globals.GoodEffectAffectedTeams.ENEMIES != 0

## Compares the flagged affected entities in the status effect to the type of entity
## this node is a child of to see if it applies.
func _check_if_applicable_entity_type_for_status_effect(status_effect: StatusEffect) -> bool:
	var class_int: int = 0
	if affected_entity is DynamicEntity:
		class_int = 1
	elif affected_entity is RigidEntity:
		class_int = 2
	elif affected_entity is StaticEntity:
		class_int = 4
	if class_int & status_effect.affected_entities == 0:
		return false
	else:
		return true

## Checks if the affected entity is Dynamic and has been flagged to not receieve effect sources (and therefore
## not status effects, either).
func _check_if_can_receive_effect_sources_and_status_effects() -> bool:
	if (affected_entity is DynamicEntity) and not affected_entity.fsm.controller.can_receive_effect_srcs:
		return false
	elif not can_receive_status_effects:
		return false
	return true

## Only plays the impact sound if one exists and one is not already playing for a matching multishot id.
func _handle_impact_sound(effect_source: EffectSource) -> void:
	var multishot_id: int = effect_source.multishot_id
	if multishot_id != -1:
		if multishot_id not in current_impact_sounds:
			var player_inst: AudioPlayerInstance = AudioManager.play_2d(effect_source.impact_sound, affected_entity.global_position, 0, true, -1, Globals.world_root)
			if player_inst:
				current_impact_sounds.append(multishot_id)

				var callable: Callable = Callable(func() -> void: current_impact_sounds.erase(multishot_id))
				AudioManager.add_finish_callable_to_player(player_inst.player, callable)
	else:
		AudioManager.play_2d(effect_source.impact_sound, affected_entity.global_position, 0, true)

## Starts the player camera fx from the effect source details.
func _handle_cam_fx(effect_source: EffectSource) -> void:
	if effect_source.impact_cam_fx == null:
		return
	effect_source.impact_cam_fx.apply_falloffs_and_activate_all(affected_entity)

## Checks if there is a life steal effect in the status effects and returns the percent to steal if so.
func _get_life_steal(effect_source: EffectSource, source_entity: Entity) -> float:
	if can_receive_status_effects and life_steal_handler:
		for status_effect: StatusEffect in effect_source.status_effects:
			if status_effect is LifeStealEffect:
				life_steal_handler.source_entity = source_entity
				return status_effect.dmg_steal
	return 0.0

#region Debug
## This works with the tool script defined above to assign export vars automatically in-editor once added
## to the tree.
func _notification(what: int) -> void:
	if Engine.is_editor_hint():
		if tool_script and what == NOTIFICATION_EDITOR_PRE_SAVE:
			tool_script.update_editor_children_exports(self, get_children())
			tool_script.update_editor_parent_export(self, get_parent())
			tool_script.ensure_effect_handler_resource_unique_to_scene(self)

## Edits editor warnings for easier debugging.
func _get_configuration_warnings() -> PackedStringArray:
	if can_receive_status_effects and not get_parent().has_node("%StatusEffectsComponent"):
		return [
			"Entities with effect receievers marked as being able to receive status effects must have a StatusEffectsComponent. Make sure it has a unique name (%)."
			]
	return []

## Attempts to apply an effect based on its file name turned into snake case. "poison_1", for example.
func apply_effect_by_id(effect_key: StringName) -> void:
	var status_effect: StatusEffect = StatusEffectsComponent.cached_status_effects.get(effect_key, null)
	if status_effect == null:
		printerr("The request to apply the effect \"" + effect_key + "\" failed because it does not exist.")
		return

	handle_status_effect(status_effect)

## Attempts to remove an effect based on its effect id. "poison", for example.
func remove_all_effects_of_id(effect_id: StringName) -> void:
	affected_entity.effects.request_effect_removal_for_all_sources(effect_id)

## Attempts to remove an effect based on its effect id case plus its source.
## "poison:from_weapon", for example.
func remove_effect_by_id_and_source(effect_key: StringName) -> void:
	if effect_key not in affected_entity.effects.current_effects:
		printerr("The request to remove \"" + effect_key + "\" failed because it does not exist as a currently applied effect.")
		return

	var effect_pieces: PackedStringArray = effect_key.split(":")
	if effect_pieces.size() < 2:
		return
	affected_entity.effects.request_effect_removal_by_source_string(effect_pieces[0], effect_pieces[1])
#endregion

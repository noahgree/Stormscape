@icon("res://Utilities/Debug/EditorIcons/proj_weapon_resource.png")
extends WeaponStats
class_name ProjWeaponStats
## The resource that defines all stats for a projectile weapon. Passing this around essentially passes the weapon around.

enum ProjWeaponType { ## The kinds of projectile weapons.
	PISTOL, SHOTGUN, SUBMACHINE, SNIPER, RIFLE, EXPLOSIVE, PRIMITIVE_WEAPON, MAGIC, THROWABLE, SPECIAL_WEAPON
}
enum ProjAmmoType { ## The types of projectile ammo.
	NONE, ## Does not have any required ammo. Useful for arbitrary special weapons that may only have one mag of usage. In combination with "dont_consume_ammo", this essentially gives any weapon infinite arbitrary uses.
	SELF, ## Used for consumable weapon uses like throwables, where one use deletes one quantity of the item.
	CHARGES, ## Does not have an associated ammo item, but rather uses recharging mags that fill over time.
	BULLETS, ## Normal bullet ammo.
	SHELLS, ## Normal shell ammo.
	ARROWS, ## Normal arrow ammo.
	ION_CHARGES, ## Normal ion charge ammo.
	BOOMPOWDER, ## Normal boompowder ammo.
	STAMINA, ## Drains stamina on usage. Not enough stamina left means this weapon cannot fire.
	MAGIC ## Drains magic on usage. Not enough magic left means this weapon cannot fire.
}
enum FiringType { ## The kinds of firing modes the weapon can have.
	SEMI_AUTO, AUTO, CHARGE
}
enum ReloadType { ## The kinds of reloads the weapon can have.
	MAGAZINE, SINGLE
}

@export var proj_weapon_type: ProjWeaponType = ProjWeaponType.PISTOL ## The kind of projectile weapon this is.
@export var firing_mode: FiringType = FiringType.SEMI_AUTO ## Whether the weapon should fire projectiles once per click or allow holding down for auto firing logic.
@export var is_hitscan: bool = false ## When true, this weapon will become a hitscan weapon.
@export var projectile_scn: PackedScene ## The projectile scene to spawn on firing.
@export var hitscan_scn: PackedScene ## The hitscan scene to spawn when using hitscan firing.

@export_group("Firing Details")
@export_range(0, 10, 0.01, "hide_slider", "or_greater", "suffix:seconds") var firing_duration: float = 0.1 ## How long the "fire" animation takes, unless overridden by a smaller value in "fire_anim_dur" below. Check the "spawn_after_fire_anim" box below to make it so the animation must finish before things are spawned.
@export_range(0, 30, 0.01, "hide_slider", "or_greater", "suffix:seconds") var fire_cooldown: float = 0.05 ## Time between fully auto projectile emmision. Also the minimum time that must elapse between clicks if set to semi-auto.
@export_subgroup("Charge Details")
@export_range(0.1, 10, 0.01, "hide_slider", "or_greater", "suffix:seconds") var min_charge_time: float = 1.0 ## How long must the activation be held down before releasing the charge shot. [b]Only used when firing mode is set to CHARGE[/b].
@export var auto_do_charge_use: bool = false ## Whether to auto start a charge use when min_charge_time is reached.
@export_range(0, 10.0, 0.01, "suffix:x", "hide_slider") var charge_loss_mult: float = 1.0 ## How much faster or slower charge progress is lost when firing is not available (but not during firing itself). Set to 0 to disable charge progress loss on anything other than successfully firing (assuming that flag is true below).
@export var dec_charge_on_cooldown: bool = false ## If true, the charge will decrease according to the rate above while on default firing cooldown as well as when idling. It will never decrease during firing, though.
@export var reset_charge_on_fire: bool = false ## When true, charge progress will reset to 0 upon successfully firing the weapon.
@export_subgroup("Firing Stat Effects")
@export var firing_stat_effect: StatusEffect ## The status effect to apply to the source entity when firing.
@export var charging_stat_effect: StatusEffect ## A status effect to apply to the entity while charging. Typically to slow them.
@export_subgroup("Firing Animations")
@export var one_frame_per_fire: bool = false ## When true, the sprite frames will only advance one frame when firing normally.
@export var fire_anim_dur: float ## When greater than 0, the fire animation will run for this override time.
@export var spawn_after_fire_anim: bool = false ## When true, the projectile won't actually spawn and fire until the end of the fire animation.
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var post_fire_anim_delay: float ## The delay after the firing duration ends before starting the post-fire animation and fx if one exists.
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var post_fire_anim_dur: float ## The override time for how long the animation should be that plays after firing (if it exists). Anything greater than 0 activates this override.
@export_subgroup("Firing FX")
@export var firing_cam_fx: CamFXResource ## The resource defining how the camera should react to firing.
@export var casing_texture: Texture2D ## The texture to use as the casing that ejects on firing.
@export var casing_tint: Color = Color.WHITE ## The tint to apply to the casing texture. White means no tint.
@export var casing_sound: String ## The sound to play when the casing hits the ground.
@export var firing_sound: String ## The sound to play when firing.
@export var post_fire_sound: String ## The sound to play after firing before the cooldown ends.
@export var charging_sound: String ## The sound to play when charging.
@export var mag_almost_empty_sound: String ## The sound to play alongside each shot sound when the ammo in the mag is almost depleted.
@export var empty_mag_sound: String ## The sound to play when trying to fire with no ammo left.

@export_group("Effect & Logic Resources")
@export var projectile_logic: ProjStats ## The logic for each spawned projectile determining how it behaves.
@export var hitscan_logic: HitscanStats = HitscanStats.new() ## The resource containing information on how to fire and operate the hitscan.
@export var effect_source: EffectSource ## The resource that defines what happens to the entity that is hit by this weapon. Includes things like damage and status effects.

@export_group("Ammo & Reloading")
@export var ammo_type: ProjWeaponStats.ProjAmmoType = ProjAmmoType.NONE ## The kind of ammo to consume on use.
@export var mag_size: int = 30  ## Number of normal attack executions that can happen before a reload is needed.
@export var reload_type: ReloadType = ReloadType.MAGAZINE ## Whether to reload over time or all at once at the end.
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var reload_delay: float ## An additional delay that occurs before the reload begins. This determines the runtime of the "before_single_reload" animation.
@export var dont_consume_ammo: bool = false ## When true, this acts like infinite ammo where the weapon doesn't decrement the ammo in mag upon firing.
@export var hide_reload_ui: bool = false ## When a player uses this, should the reloading UI be hidden.
@export_subgroup("Magazine")
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var mag_reload_time: float = 1.0 ## How long it takes to reload an entire mag.
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var mag_reload_anim_delay: float ## An additional delay that occurs before the magazine reload begins. This will be clamped to the mag_reload_time.
@export_subgroup("Single")
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var single_proj_reload_time: float = 0.25 ## How long it takes to reload a single projectile if the reload type is set to SINGLE.
@export var single_reload_quantity: int = 1 ## How much to add to the mag when the single proj timer elapses each time.
@export var must_reload_fully: bool = false ## When true, if the reload method is SINGLE, the reload cannot be stopped while in progress and must load all single projectiles in before being able to fire again.
@export_subgroup("Recharging")
@export var auto_ammo_interval: float ## How long it takes to recouperate a single ammo when given automatically. Most useful when using the "Charges" ammo type but can also be used to simply grant ammo over time. Anything above 0 activates this feature. Only works with consumable ammo types, meaning not "Self" or "Stamina".
@export var auto_ammo_count: int = 1 ## How much ammo to grant after the interval is up.
@export_range(0.05, 1000, 0.01, "suffix:seconds", "hide_slider", "or_greater") var auto_ammo_delay: float = 0.5 ## How long after firing must we wait before the grant interval countdown starts.
@export var recharge_uses_inv: bool = false ## When true, the ammo will recharge by consuming ammo from the inventory. When none is left, the recharges will stop.
@export_subgroup("Stamina Use")
@export_custom(PROPERTY_HINT_NONE, "suffix:stamina") var stamina_use_per_proj: float = 0.5 ## How much stamina is needed per projectile when stamina is the ammo type.
@export_subgroup("Reloading FX")
@export var reload_sound: String ## The sound resource to play when reloading. Usually called from animation player. The resource should contain each partial reload sound in order.

@export_group("Blooming Logic")
@export_custom(PROPERTY_HINT_NONE, "suffix:degrees") var max_bloom: float ## The max amount of bloom the weapon can have.
@export var bloom_curve: Curve ## X value is bloom amount (0-1), Y value is multiplier on max_bloom.
@export var bloom_increase_rate: Curve ## How much bloom to add per shot based on current bloom.
@export var bloom_decrease_rate: Curve ## How much bloom to take away per second based on current bloom.
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var bloom_decrease_delay: float = 1.0 ## How long after the last bloom increase must we wait before starting to decrease it.

@export_group("Warmup Logic")
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var initial_fire_rate_delay: float ## At the lowest warmup level, how long must we wait before a shot fires. This only works when the firing mode is set to AUTO.
@export var warmup_delay_curve: Curve ## X value is warmup amount (0-1), Y value is multiplier on initial_fire_rate_delay.
@export var warmup_increase_rate: Curve ## A curve for determining how much warmth to add per shot depending on current warmup.
@export var warmup_decrease_rate: Curve ## How much warmup do we remove per second based on current warmup.
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var warmup_decrease_delay: float = 0.75 ## How long after the last warmup increase must we wait before starting to decrease it.

@export_group("Overheating Logic")
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var overheat_penalty: float ## When we reach max overheating, how long is the penalty before being able to use the weapon again. Anything above 0 activates this feature.
@export var overheat_inc_rate: Curve ## X value is overheat amount (0-1), Y value is how much we add to overheat amount per shot.
@export var overheat_dec_rate: Curve ## X value is overheat amount (0-1), Y value is how much we take away from overheat amount per second.
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var overheat_dec_delay: float = 0.75 ## The time between the last overheat increase and when it will begin to decrease back down to 0.
@export var overheated_sound: String ## The sound to play when the weapon reaches max overheat.
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var overheat_anim_dur: float = 0.5 ## How long one loop of the overheat animation should take (if one exists).

@export_group("Burst Logic")
@export_range(1, 100, 1) var projectiles_per_fire: int = 1 ## How many projectiles are emitted per burst execution.
@export var use_ammo_per_burst_proj: bool = true ## Whether to consume ammo per projectile emmitted or consume 1 per full burst.
@export_range(0.03, 1, 0.01, "suffix:seconds", "or_greater", "hide_slider") var burst_proj_delay: float = 0.05 ## Time between burst shots after execute.
@export var add_bloom_per_burst_shot: bool = true ## Whether or not each bullet from a burst fire increases bloom individually.
@export var add_overheat_per_burst_shot: bool = true ## Whether or not each bullet from a burst fire increases overheat individually.

@export_group("Barrage Logic")
@export_range(1, 50, 1) var barrage_count: int = 1 ## Number of projectiles fired at 'angular-spread' degrees apart for each execute. Only applies when angular spread is greater than 0.
@export_range(0, 360, 0.1, "suffix:degrees") var angular_spread: float = 25 ## Angular spread of barrage projectiles in degrees.
@export var do_cluster_barrage: bool = false ## When true, the barrage will spawn like a cluster, with random offsets and delays for each projectile.
@export_range(0, 1, 0.01, "suffix:seconds", "or_greater", "hide_slider") var barrage_proj_delay: float ## The amount of time between each projectile from the barrage spawning. When do_cluster_barrage is true, this becomes the max amount of time between each projectile (with randomness introduced). Anything greater than 0 activates this.


## Creates a new item instance with a new UID.
func create_ii(quantity: int) -> II:
	var new: ProjWeaponII = ProjWeaponII.new()
	new.stats = self
	new.q = quantity
	new.initialize_sc()
	return new

## Copies an item instance, keeping the same exported properties.
func copy_ii(original_ii: II) -> II:
	var new: WeaponII = original_ii.duplicate()
	new.initialize_sc()
	return new

## Returns a nicely formatted string of the ammo type.
func get_ammo_string() -> String:
	var main_string: String = ProjAmmoType.keys()[ammo_type]
	return main_string.to_pascal_case()

## An override to return the string title of the item type rather than just the enum integer value.
func get_item_type_string(exact_weapon_type: bool = false) -> String:
	if exact_weapon_type:
		return str(ProjWeaponType.keys()[proj_weapon_type]).capitalize()
	return str(Globals.ItemType.keys()[item_type]).capitalize()

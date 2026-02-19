extends Resource
class_name ProjStats
## The base projectile stats resource.

@export_group("General")
@export var speed: int = 350 ## The highest speed the projectile can travel in.
@export var speed_curve: Curve ## How the speed changes based on time alive.
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var initial_boost_time: float ## The duration of any initial boost we want to start with on.
@export var initial_boost_mult: float = 2.0 ## The speed multiplier for the initial boost, if any.
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var lifetime: float = 3 ## The max time this projectile can be in the air.
@export_custom(PROPERTY_HINT_NONE, "suffix:pixels") var max_distance: int = 500 ## The max distance this projectile can travel from its starting position.
@export_subgroup("VFX")
@export_custom(PROPERTY_HINT_NONE, "suffix:pixels") var height_override: int = -1 ## How high off the ground to simulate this projectile being. Basically just moves the shadow's y offset. Anything besides -1 activates this.
@export var disable_trail: bool = false ## When true, the projectile will not have a trail if it had one originally. Turn this on when spawning a lot of projectiles from one weapon, as trails can be expensive.
@export var glow_color: Color = Color(1, 1, 1) ## The color of the glow.
@export_range(0, 500, 0.1, "suffix:%") var glow_strength: float = 35 ## How strong the glow should be.
@export var impact_vfx: PackedScene ## The VFX to spawn at the site of impact. Could be a decal or something.
@export var impact_sound: String ## The sound to play at the site of impact.
@export var rand_impact_rot: bool = false ## When true, the sprite will get a random rotation on impact to change how the impact animation looks for circular projectiles.

@export_group("Falloff")
@export var effect_falloff_curve: Curve ## The falloff curve for all effects in the effect source.
@export_custom(PROPERTY_HINT_NONE, "suffix:pixels") var point_of_max_falloff: float = 500 ## The cumulative distance travelled at which the projectile attains the minimum remaining stats due to falloff.
@export var bad_effects_falloff: bool = true ## Whether to apply the falloff curve to bad effects.
@export var good_effects_falloff: bool = false ## Whether to apply the falloff curve to good effects.

@export_group("Curve Movement")
@export_enum("Default", "Sine", "Sawtooth") var path_type: String = "Default" ## The potential wave-based movement method to use.
@export var amplitude: float = 5.0 ## The height of the waves.
@export var frequency: float = 2.0 ## The stretch of the waves.

@export_group("Piercing Logic")
@export_range(0, 100, 1, "or_greater") var max_pierce: int ## The max amount of collisions this can take before freeing.

@export_group("Ricochet Logic")
@export_range(0, 100, 1) var max_ricochet: int ## The max amount of ricochets this can do before trying to pierce and then freeing.
@export var ricochet_angle_bounce: bool = true ## Whether the ricochets should bounce at an angle or just reverse the direction they were travelling in. Note that when colliding with TileMaps, it always just reverses direction.
@export var ricochet_walls_only: bool = false ## When true, the projectile will only bounce off walls with no limit.
@export var ignore_dynamic_entities: bool = false ## When true, the projectile will pass through dynamic entities when it would have otherwise ricocheted.

@export_group("Homing Logic")
@export_enum("None", "FOV", "Closest", "Mouse Position", "Boomerang") var homing_method: String = "None" ## Whether this projectile should home-in on its target.
@export var homing_speed_mult: float = 1.0 ## Multiplies the speed by a factor unique to the homing movement.
@export_custom(PROPERTY_HINT_NONE, "suffix:º/sec") var max_turn_rate: float = 100 ## The max turn rate in degrees per second.
@export var turn_rate_curve: Curve ## The change in turn rate as lifetime elapses.
@export_range(0, 360, 1, "suffix:degrees") var homing_fov_angle: float = 180 ## The FOV for aquiring targets.
@export var homing_max_range: int = 850 ## The max range for aquiring targets when using the "closest" method.
@export var homing_duration: float = -1 ## The duration for which homing is active. -1 means 'always'.
@export var homing_start_delay: float ## The delay before homing begins.
@export var can_change_target: bool = false ## Whether we can update what to home in on during flight.
@export var boomerang_home_radius: float = 5 ## How far from the source entity the boomerang needs to be to queue free.
@export var mouse_target_radius: float = 50 ## How close from the mouse on spawn objects need to be to be considered a target.

@export_group("Spin Logic")
@export_range(0, 10000, 1, "suffix:º/sec") var spin_speed: float ## How fast this projectile should spin while in the air.
@export var spin_both_ways: bool = false ## Whether each projectile should choose a direction at random or depend on the spin_direction.
@export_enum("Forward", "Backward") var spin_direction: String = "Forward" ## If spin_both_ways is false, all projectiles will spin this direction.
@export var do_y_axis_reflection: bool = false ## When true, the sprite will be flipped horizontally if its initial rotation is past the vertical line, meaning facing left. This allows for a consistent bottom edge even when rotated beyond the y-axis.
@export var move_in_rotated_dir: bool = false ## When true, projectiles will travel in the direction of their current rotation, determined by spinning it. If false, they will keep their original trajectory despite the spins. Note that this does nothing if we are arcing.
@export var shadow_matches_spin: bool = false ## Whether the shadow should rotate with the spin or not. This is always overridden to be false when arcing.

@export_group("Arc Trajectory")
@export_range(0, 89, 1, "suffix:degrees") var launch_angle: float ## The initial angle to launch the projectile at. Note that homing projectiles cannot do arcing. Setting this to anything above 0 will enable the arcing logic.
@export_custom(PROPERTY_HINT_NONE, "suffix:pixels") var arc_travel_distance: int = 125 ## How many pixels the arc shot should travel before landing.
@export var arc_speed: float = 500 ## How fast the arcing motion happens.
@export_custom(PROPERTY_HINT_NONE, "suffix:pixels") var max_collision_height: int = 20 ## How many simulated pixels off the ground this can be before it can no longer collide with things.
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var grounding_free_delay: float ## How much time after we hit the ground do we wait before freeing the projectile. Note that this doesn't apply if we start an AOE after grounding.
@export_subgroup("Bouncing")
@export var bounce_count: int ## How many more times to bounce off the ground after landing from the first arc.
@export var bounce_falloff_curve: Curve ## How the bounces simulate losing energy and travel less distance each time as a function of time alive.
@export var ping_pong_bounce: bool = false ## Whether to bounce back and forth instead of in the original direction.

@export_group("Splitting Logic")
@export_range(0, 20, 1) var number_of_splits: int ## How many times the recursive splits should happen.
@export var split_into_counts: Array[int] = [2] ## For each split index, you should assign how many to create.
@export_custom(PROPERTY_HINT_NONE, "suffix:degrees") var angular_spreads: Array[float] = [45] ## For each split index, you should specify how wide of an angle the projectiles will be spread amongst.
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var split_delays: Array[float] = [0.2] ## For each split index, you should assign how long after the last projectile spawn to wait before splitting again. The first delay is the delay before the initial split.
@export_subgroup("Splitting FX")
@export var splitting_sound: String ## The sound to be played during each split.
@export var split_cam_fx: Array[CamFXResource] = [CamFXResource.new()] ## For each split index, you should determine how strong the camera fx will be at the split.

@export_group("Area of Effect")
@export var aoe_effect_source: EffectSource = null ## The effect source to apply when something is hit by aoe damage. If null, this will just use the default effect source for this projectile.
@export_range(0, 200, 1, "suffix:pixels") var aoe_radius: int ## If above 0, this projectile will do AOE damage after hitting something.
@export var do_aoe_on_arc_land: bool = true ## Whether to trigger an AOE when we land after an arc shot.
@export var aoe_before_freeing: bool = false ## Whether to trigger the aoe once we reach end of lifetime if we haven't hit anything yet.
@export_subgroup("Falloff")
@export var aoe_effect_falloff_curve: Curve ## Changes damage and mod times for the effect source based on how far away from the origin of the aoe damage the receiver was hit.
@export var bad_effects_aoe_falloff: bool = true ## Whether to apply the falloff curve to bad effects in an aoe hit.
@export var good_effects_aoe_falloff: bool = false ## Whether to apply the falloff curve to good effects in an aoe hit.
@export_subgroup("Timing")
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var aoe_delay: float ## How long after triggering the AOE does the projectile sit in wait before re-enabling the larger collider.
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var aoe_effect_dur: float = 0.05 ## How long the larger collider will be enabled for once an aoe is triggered.
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var aoe_effect_interval: float = 1 ## How long between applications of the status effects of the AOE to each entity inside it.
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var aoe_effects_delay: float = 0.5 ## How long after an entity enters the AOE effect area before applying the first status effect pulse.
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var aoe_anim_dur: float = 0.2 ## How long the sprite frames' "aoe" animation should take to complete.
@export_subgroup("AOE FX")
@export var aoe_hide_sprite: bool = true ## When true, the main proj sprite will be hidden once AOE starts. If there is an "aoe" animation to play, the sprite will hide after it is done.
@export var aoe_vfx: PackedScene = null ## The scene to instance when activating the aoe.
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var aoe_vfx_dur: float = 0.0 ## When anything besides 0, the vfx will stick around for this amount of seconds instead of immediately fading upon the projectile being freed.
@export var aoe_sound: String ## The sound to play when activating the aoe.

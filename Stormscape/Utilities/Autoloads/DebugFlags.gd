extends Node
## An autoload singleton file for flagging certain debug features like print statements and audio device switches.

# Print Flags
var state_machine_swaps: bool = false
var stat_mod_changes_during_game: bool = true
var stat_mod_changes_on_load: bool = false
var current_effect_changes: bool = false
var weapon_mod_changes: bool = true
var wearable_changes: bool = true
var saver_loader_status_changes: bool = true
var ammo_updates: bool = false
var sounds_starting: bool = false
var sound_preload_changes: bool = false
var sound_refcount_changes: bool = false
var storm_phases: bool = false
var loot_table_updates: bool = false
var weapon_xp_updates: bool = false

# Push Error Flags
var mod_not_in_cache: bool = false ## Anytime a stat mod is applied to a nonexistent stat, push an error. This should be turned off unless debugging a new stat mod, since entities who don't have certain stats like max_speed will always push an error for status effects that try to mod it (but it isn't really an error since it won't affect anything by design).

# Main Menu Flags
var skip_main_menu: bool = false

# Audio Flags
var set_debug_output_device: bool = true

# Hotbar Flags
var use_scroll_debounce: bool = true

# Projectile Flags
var show_collision_points: bool = false
var show_homing_rays: bool = false
var show_homing_targets: bool = false
var show_movement_dir: bool = false
var show_hitscan_rays: bool = false
var show_aiming_direction: bool = false

# Particle Flags
var show_status_effect_particle_emission_area: bool = false

# On Screen Debug Flags
var show_fps: bool = true

# Entity Flags
var show_facing_dir: bool = false
var show_nav: bool = false


func _ready() -> void:
	DebugConsole.add_command("set", set_debug_flag)

## Sets a debug flag to the passed in value.
func set_debug_flag(flag_name: String, value: int) -> void:
	var bool_val: bool = false
	match value:
		1, 1.0:
			bool_val = true
		0, 0.0:
			bool_val = false
		_:
			printerr("The value passed in could not be converted to a bool. False was chosen by default.")

	if flag_name in self:
		set(flag_name, bool_val)
	else:
		printerr("That flag does not exist.")

## Returns all flags and their current values.
func get_all_flags() -> Dictionary[StringName, Variant]:
	var all_flags: Dictionary[StringName, Variant]
	for flag: Dictionary in get_script().get_script_property_list():
		var flag_name: String = flag.name
		if flag_name == "DebugFlags.gd":
			continue
		var value: Variant = get(flag.name)
		all_flags[flag_name] = value
	return all_flags

@icon("res://Utilities/Debug/EditorIcons/weapon_mod.svg")
extends ItemStats
class_name WeaponModStats
## Class for all weapon mods in the game.

@export_group("Whitelist")
@export var allowed_proj_wpns: Array[ProjWeaponStats.ProjWeaponType] = Globals.all_proj_weapons ## The allowed types of projectile weapons that can have this mod attached. Has all types allowed by default.
@export var allowed_melee_wpns: Array[MeleeWeaponStats.MeleeWeaponType] = Globals.all_melee_wpns ## The allowed types of melee weapons that can have this mod attached. Has all types allowed by default.

@export_group("Blacklist")
@export var blocked_mutuals: Array[StringName] = [] ## The mods that cannot be placed on the same weapon as this mod. In other words, only one of the mods in this list and this mod itself can be on a weapon at a time.
@export var blocked_wpn_stats: Dictionary[StringName, float] = {} ## A dictionary of stats and disallowed values for said stats that the weapon must not have in order for the mod to be compatible. This also means the weapon must be the type that actually has this stat at all.
@export var req_all_blocked_stats: bool = false ## When true, every stat in the above list must have their disallowed value. When false, it only takes one stat having the disallowed value to block this mod entirely.
@export var required_stats: Dictionary[StringName, float] = {} ## A dictionary of stats and required values for said stats that the weapon must have in order for the mod to be compatible. This also means the weapon must be the type that actually has this stat at all.

@export_group("Stat & Effect Mods")
@export var wpn_stat_mods: Array[StatMod] ## The stat modifiers applied by this mod. Do not have duplicates in this array.
@export var status_effects: Array[StatusEffect] ## The status effects to add to the weapon's effect source status effects.
@export var charge_status_effects: Array[StatusEffect] ## The status effects to add to the weapon's charge effect source status effects.
@export var aoe_status_effects: Array[StatusEffect] ## The status effects to add to the weapon's aoe effect source status effects.

@export_group("Applied Details")
@export var applied_details: Array[StatDetail] = [] ## The extra information to populate in the item viewer details panel for the weapon that this is attached to. If inside one of the detail resources you leave the stat array empty, the title will turn green and be displayed alone without a colon and any associated numerical value.

@export_group("FX")
@export var equipping_audio: String = "" ## The audio resource to play as a sound effect when adding this mod to a weapon.
@export var removal_audio: String = "" ## The audio resource to play as a sound effect when removing this mod from a weapon.


## Intended to be overridden. This is called immediately after this mod is added.
func on_added(_weapon_stats: WeaponStats, _equipped_item: EquippableItem) -> void:
	pass

## Intended to be overridden. This is called immediately after this mod is removed.
func on_removal(_weapon_stats: WeaponStats, _equipped_item: EquippableItem) -> void:
	pass

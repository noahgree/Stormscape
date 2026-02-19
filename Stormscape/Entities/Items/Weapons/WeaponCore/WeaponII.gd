extends II
class_name WeaponII

@export_custom(PROPERTY_HINT_RANGE, "1,40,1", PROPERTY_USAGE_STORAGE) var level: int = 1 ## The level for this weapon.
@export_storage var allowed_lvl: int = 1 ## The level that the xp gain has allowed this weapon to achieve, potentially pending an upgrade confirmation from the player.
@export_storage var lvl_progress: int ## Any xp gained towards the progress of the next level is stored here.
@export_storage var s_mods: StatModsCacheResource = StatModsCacheResource.new() ## The cache of all up to date stats for this weapon with mods factored in.
@export_storage var weapon_mods_need_to_be_readded_after_save: bool = false ## When the weapons are loaded from a save, the weapon mods end up getting added to the old stats reference and not the new duplicated one after load. But since these properties transfer over, we check this each time the weapon is readied to see if we should readd all weapon mods.
@export_storage var current_mods: Array[Dictionary] = [{ &"1" : null }, { &"2" : null }, { &"3" : null }, { &"4" : null }, { &"5" : null }, { &"6" : null }] ## The current mods applied to this weapon. This is an array of dictionaries so that the KV pairs can be ordered. Keys are StringName mod names and values are weapon_mod resources.
@export_storage var original_status_effects: Array[StatusEffect] = [] ## The original status effect list of the effect source before any mods are applied.
@export_storage var original_charge_status_effects: Array[StatusEffect] = [] ## The original status effect list of the charge effect source before any mods are applied.
@export_storage var original_aoe_status_effects: Array[StatusEffect] = [] ## The original status effect list of the aoe effect source before any mods are applied.

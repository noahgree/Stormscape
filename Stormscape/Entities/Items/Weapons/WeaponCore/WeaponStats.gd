extends ItemStats
class_name WeaponStats
## The base resource for all weapons.

@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var pullout_delay: float = 0.25 ## How long after equipping must we wait before we can use this weapon.
@export var snap_to_six_dirs: bool = false ## When true, free rotation of the sprite is disabled and will snap to six predefined directions.
@export var no_levels: bool = false ## When true, this weapon does not engage with the weapon leveling system.
@export var hide_ammo_ui: bool = false ## Whether to hide the ammo UI when the player uses this weapon.
@export_group("Modding Details")
@export_range(-1, 6, 1) var max_mods_override: int = -1 ## The override for the maximum number of mod slots for this weapon. By default it is based on rarity. Anything other than -1 will activate the override.
@export var blocked_mods: Array[StringName] = [] ## The string names of weapon mod titles that are not allowed to be applied to this weapon.


## Creates a new item instance with a new UID.
func create_ii(quantity: int) -> II:
	var new: WeaponII = WeaponII.new()
	new.stats = self
	new.q = quantity
	return new

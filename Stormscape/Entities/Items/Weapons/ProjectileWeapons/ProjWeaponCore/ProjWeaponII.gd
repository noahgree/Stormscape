extends WeaponII
class_name ProjWeaponII
## The item instance subclass specific to projectile weapons.

@export_group("Proj Weapon")
@export var ammo_in_mag: int = -1: ## The current ammo in the mag.
	set(new_ammo_amount):
		ammo_in_mag = new_ammo_amount
		if DebugFlags.ammo_updates and stats.name != "":
			print_rich("(" + str(stats) + ") [b]AMMO[/b]: [color=Crimson]" + str(ammo_in_mag) + "[/color]")

@icon("res://Utilities/Debug/EditorIcons/weapon_mod.svg")
extends WeaponModStats
class_name ExtendedMagMod
## Implements logic specific to the extended mag mod, mainly to update the UI and reset ammo count on mod removal.


func on_added(weapon_ii: WeaponII, equippable_item: EquippableItem) -> void:
	if weapon_ii is ProjWeaponII:
		# When removed and readded on load, the on_removal will set it to the original size if it was above it, so this just undoes that
		if weapon_ii.ammo_in_mag >= weapon_ii.sc.get_original_stat("mag_size"):
			weapon_ii.ammo_in_mag = weapon_ii.sc.get_stat("mag_size")
			# Must check if it is null since the mod manager may call this for inventory items and not only equipped items
			if equippable_item != null and weapon_ii == equippable_item.ii:
				equippable_item.update_ammo_ui()

func on_removal(weapon_ii: WeaponII, equippable_item: EquippableItem) -> void:
	if weapon_ii is ProjWeaponII:
		weapon_ii.ammo_in_mag = min(weapon_ii.ammo_in_mag, weapon_ii.sc.get_stat("mag_size"))
		if equippable_item != null and weapon_ii == equippable_item.ii:
			equippable_item.update_ammo_ui()

@icon("res://Utilities/Debug/EditorIcons/wearable.svg")
extends ItemStats
class_name WearableStats
## The class for all wearable gear and items that provide status effects or stat modifications to the wearer.


@export var stat_mods: Array[StatMod] ## The stat modifiers applied by this wearable. Do not have duplicates in this array.
@export_subgroup("Applied Details")
@export var applied_details: Array[StatDetail] = [] ## The extra information to populate in the item viewer details panel for the entity that this is attached to. If inside one of the detail resources you leave the stat array empty, the title will turn green and be displayed alone without a colon and any associated numerical value.

@export_group("Blacklist")
@export var blocked_mutuals: Array[StringName] = [] ## The wearables that cannot be on at the same time as this. In other words, only one of the wearables in this list and this wearable itself can be on an entity at a time.

@export_group("FX")
@export var equipping_audio: String = "" ## The audio resource to play as a sound effect when equipping this wearable.
@export var removal_audio: String = "" ## The audio resource to play as a sound effect when unequipping this wearable.

@icon("res://Utilities/Debug/EditorIcons/loot_table_resource.svg")
extends Resource
class_name LootTableResource
## When attached to an entity, this determines what drops from both normal interactions like damage and on death.

@export_group("On Hit")
@export var hit_loot_table: Array[LootTableEntry] = [] ## The possible loot that can drop after being hit by an effect source and the respective weightings of each.
@export_range(0, 100, 0.1, "suffix:%") var hit_spawn_chance: float = 100.0
@export_range(0, 100, 1) var hit_chance_scale: int = 1 ## When above 0, the drop chance will scale up over time based on how long it has been since the last drop, all multiplied by this scaling factor. This prevents the off-chance of there being a long drought of no drops. 0 < x < 1 lowers the scaling factor. 1 < x <= 100 increases it.
@export var remove_when_dropped: bool = false ## If each loot item should only be allowed to drop once for the entity.
@export var require_dmg_on_hit: bool = true ## When true, this will not trigger the "Hit" loot table when receiving a hit unless that hit dealt damage.
@export_range(0, 100, 1, "suffix:%") var hp_percent_hit_checks: int = 15 ## Every time this amount of the total health and shield depletes from the entity, the hit check will fire and see if loot should drop as a result. Set to 0 to check on every hit.

@export_group("On Die")
@export var die_loot_table: Array[LootTableEntry] = [] ## The possible loot that can drop after dying and the respective weightings of each.
@export_range(0, 100, 0.1, "suffix:%") var die_spawn_chance: float = 100.0 ## The overall chance that loot spawns after dying.

@export_group("Rarity Scaling")
@export var rarity_scaling_factors: Dictionary[Globals.ItemRarity, float] = {
		Globals.ItemRarity.COMMON: 0.5,
		Globals.ItemRarity.UNCOMMON: 0.4,
		Globals.ItemRarity.RARE: 0.3,
		Globals.ItemRarity.EPIC: 0.1,
		Globals.ItemRarity.LEGENDARY: 0.05,
		Globals.ItemRarity.SINGULAR: 0.005
	}

var source_entity: Entity ## The entity that this loot table reflects.
var hit_loot_table_total_weight: float ## Sum of all weights for all possible hit loot.
var die_loot_table_total_weight: float ## Sum of all weights for all possible die loot.
var times_since_drop: int ## Tracks the times we did a hit check in a row without dropping any loot.
var is_dying: bool = false ## Flagged to true when the source_entity is dying and shouldn't drop any new loot.
var hp_change_counter: int


## Called once the owning node is ready in order to pass a reference of itself and also set up the weightings.
func initialize(entity: Entity) -> void:
	source_entity = entity
	if require_dmg_on_hit:
		source_entity.health_component.health_changed.connect(_on_hp_changed)
		source_entity.health_component.shield_changed.connect(_on_hp_changed)

	hit_loot_table = hit_loot_table.filter(func(element: LootTableEntry) -> bool: return element != null)
	die_loot_table = die_loot_table.filter(func(element: LootTableEntry) -> bool: return element != null)

	for i: int in range(hit_loot_table.size()):
		hit_loot_table_total_weight += hit_loot_table[i].weighting
	for i: int in range(die_loot_table.size()):
		die_loot_table_total_weight += die_loot_table[i].weighting

## Called when the health or shield of the source_entity changes. When we require damage on hit to trigger a drop
## check, this is the entry point. This doesn't check until we have accumulated enough damagaccording to
## hp_percent_hit_checks.
func _on_hp_changed(new_value: int, old_value: int) -> void:
	# Since this method is only applicable when we require damage on hit
	if new_value >= old_value:
		return

	hp_change_counter += (old_value - new_value)

	var max_health: int = int(source_entity.stats.get_stat("max_health"))
	var max_shield: int = int(source_entity.stats.get_stat("max_shield"))
	var needed_change: float = (max_health + max_shield) * (hp_percent_hit_checks / 100.0)
	if hp_change_counter >= needed_change:
		hp_change_counter = floori(hp_change_counter - needed_change)
		handle_hit()

## This is either called from the _on_hp_changed method or directly from the effect receiver when it gets hit by
## something that did not damage and we don't require damage on hit.
func handle_hit() -> void:
	if is_dying or not _roll_to_check_if_should_drop(true):
		return

	if hit_loot_table and not hit_loot_table.is_empty():
		var entry: LootTableEntry = _get_random_loot_entry(true)
		var ii: II = entry.stats.create_ii(entry.quantity)
		WorldItem.spawn_on_ground(ii, source_entity.global_position, 15.0, false, false)

func handle_death() -> void:
	is_dying = true
	if not _roll_to_check_if_should_drop(false):
		return

	if die_loot_table and not die_loot_table.is_empty():
		var entry: LootTableEntry = _get_random_loot_entry(false)
		var ii: II = entry.stats.create_ii(entry.quantity)
		WorldItem.spawn_on_ground(ii, source_entity.global_position, 15.0, false, false)

func _roll_to_check_if_should_drop(was_hit: bool) -> bool:
	var spawn_chance: float = (hit_spawn_chance if was_hit else die_spawn_chance) / 100.0
	var should_spawn: bool = false
	var increase_factor: float = (times_since_drop * 0.10 * float(hit_chance_scale)) * spawn_chance
	if randf() <= (spawn_chance + increase_factor):
		should_spawn = true
		times_since_drop = 0
	else:
		times_since_drop += 1
	return should_spawn

func _get_random_loot_entry(was_hit: bool) -> LootTableEntry:
	var table_selection: Array[LootTableEntry] = hit_loot_table if was_hit else die_loot_table
	var total_weight: float = 0.0
	var selected_entry: LootTableEntry = null

	var effective_weights: Array[float] = []
	for entry: LootTableEntry in table_selection:
		# The chance multiplier that usually gets lower for the higher rarities
		var rarity_factor: float = rarity_scaling_factors.get(entry.stats.rarity, 1.0)

		# Multiply the effect the time since something was last dropped by the rarity scaler, since it should take longer to drop rarer things again
		var time_factor: float = 1.0 + (entry.last_used * rarity_factor)

		# Multiply the overall weighting by this new rarity-time factor to scale its new weight
		var effective_weight: float = entry.weighting * time_factor
		effective_weights.append(effective_weight)

		# Update the total weight again
		total_weight += effective_weight

	var random_value: float = randf() * total_weight
	var cumulative_weight: float = 0.0

	var removal_index: int = -1
	for i: int in range(table_selection.size()):
		cumulative_weight += effective_weights[i]
		if random_value < cumulative_weight and selected_entry == null:
			table_selection[i].last_used = 0
			table_selection[i].spawn_count += 1
			selected_entry = table_selection[i]
			if remove_when_dropped:
				removal_index = i
		else:
			table_selection[i].last_used += 1

	if removal_index != -1:
		table_selection.remove_at(removal_index)

	table_selection.shuffle()

	if DebugFlags.loot_table_updates:
		_print_table(true)

	return selected_entry

#region Debug
## Debug function used to print out the current loot table data.
func _print_table(use_hit: bool) -> void:
	var table: Array[LootTableEntry] = hit_loot_table if use_hit else die_loot_table
	print("-----------------------------------------------------------------------------------")
	for i: int in range(table.size()):
		print_rich("+++++++++++++++ " + str(table[i].stats) + " | Last Used: " + str(table[i].last_used) + " | Weighting: " + str(table[i].weighting) + " | Spawn Count: [b]" + str(table[i].spawn_count) + "[/b] +++++++++++++++")
#endregion

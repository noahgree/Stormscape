extends Node
## A singleton containing all data needed globally.

var item_dir: String = "res://Entities/Items/TRESItems/" ## The top level folder holding all item resources.
var status_effects_dir: String = "res://Entities/Stats/EffectSystemResources/StatusEffects/" ## The top level folder holding all status effects.

@onready var world_root: WorldRoot = get_parent().get_node("Game/WorldRoot") ## A reference to the root of the game world.
@onready var storm: Storm = get_parent().get_node("Game/WorldRoot/Storm") ## A reference to the main storm node.
@onready var persistent_audio_manager: PersistentAudioManager = get_parent().get_node("Game/PersistentAudioManager") ## A reference to the persistent audio manager.

var player_node: Player = null ## The reference to the player's node.
var player_camera: PlayerCamera = null ## The reference to the player's main camera.
var ui_focus_open: bool = false ## When true, a UI that pauses the game is open.
var ui_focus_is_closing_debounce: bool = false ## When true, the focused ui is still just barely closing.
var ui_focus_close_debounce_timer: Timer = TimerHelpers.create_one_shot_timer(self, 0.05, func() -> void: Globals.ui_focus_is_closing_debounce = false) ## Debounces turning off the flag so that any inputs like inventory clicks can finish first.
var ui_focus_stack: Dictionary[Node, bool] ## Collection of nodes holding focus on the UI.


func _ready() -> void:
	player_node = await SignalBus.player_ready
	player_camera = get_parent().get_node("Game/WorldRoot/PlayerCamera")

func change_focused_ui_state(open: bool, node: Node) -> void:
	get_tree().paused = open
	ui_focus_open = open
	ui_focus_is_closing_debounce = open
	if open:
		ui_focus_stack[node] = true
		ui_focus_close_debounce_timer.stop()
		SignalBus.ui_focus_opened.emit(node)
	else:
		ui_focus_stack.erase(node)
		if ui_focus_stack.is_empty():
			ui_focus_close_debounce_timer.start()
			SignalBus.ui_focus_closed.emit(node)

# Player Inv Resource
const MAIN_PLAYER_INV_SIZE: int = 40
const HOTBAR_SIZE: int = 10
const AMMO_BAR_SIZE: int = 4
const CURRENCY_BAR_SIZE: int = 3

# EffectReceiver & StatModManager
enum Teams {
	PLAYER = 1 << 0, ## The player team (against the enemies).
	ENEMY = 1 << 1, ## The enemy team (against the player).
	PASSIVE = 1 << 2 ## Does not heal or damage anything. Just exists.
}
enum DmgAffectedStats { HEALTH_ONLY, SHIELD_ONLY, SHIELD_THEN_HEALTH, SIMULTANEOUS }
enum HealAffectedStats { HEALTH_ONLY, SHIELD_ONLY, HEALTH_THEN_SHIELD, SIMULTANEOUS }
enum BadEffectAffectedTeams { ENEMIES = 1 << 0, ALLIES = 1 << 1 }
enum GoodEffectAffectedTeams { ENEMIES = 1 << 0, ALLIES = 1 << 1 }
enum EffectSourceSourceType {
	FROM_DEFAULT, ## For any effect source that does not come from any of the below types.
	FROM_PROJECTILE, ## For damage coming from any normal projectile like a bullet from a sniper or pistol.
	FROM_EXPLOSION, ## For damage coming from AOEs that explode.
	FROM_GROUND_AOE, ## For damage coming from AOEs that exist on the ground like a poison puddle or aftermath of a molotov.
	FROM_MAGIC, ## For magic weapons.
	FROM_TOOL, ## For melee weapons like pickaxes and axes that exist primary to interact with the world resources.
	FROM_PHYSICAL_CONTACT, ## For physcial interactions like a punch or running into something with a hitbox attached to the body.
	FROM_COMBAT_MELEE, ## For melee weapons that are primarily damaging weapons like a sword (not tools like the pickaxe).
	FROM_CONSUMABLE ## For receiving effects from consuming consumables.
}
enum StatusEffectSourceType {
	FROM_WEAPON, ## For any status effect that is the result of being hit by a weapon's hitbox (like projectiles).
	FROM_GROUND_AOE, ## For any status effect that gets applied by walking into a ground AOE like after an explosion.
	FROM_ENVIRONMENT, ## For any status effect coming from the environment, like the cold weather, etc.
	FROM_SELF ## For self effects like when weapons apply effects to the entity while being charged up.
}

# Items
enum ItemType {
	CONSUMABLE, WEAPON, AMMO, WEARABLE, WORLD_RESOURCE, SPECIAL, WEAPON_MOD, CURRENCY
}
enum CurrencyType {
	STORMSHINE, SCRAP, TOKEN
}
const all_proj_weapons: Array[ProjWeaponStats.ProjWeaponType] = [ProjWeaponStats.ProjWeaponType.PISTOL, ProjWeaponStats.ProjWeaponType.SHOTGUN, ProjWeaponStats.ProjWeaponType.SUBMACHINE, ProjWeaponStats.ProjWeaponType.SNIPER, ProjWeaponStats.ProjWeaponType.RIFLE, ProjWeaponStats.ProjWeaponType.EXPLOSIVE, ProjWeaponStats.ProjWeaponType.PRIMITIVE_WEAPON, ProjWeaponStats.ProjWeaponType.MAGIC, ProjWeaponStats.ProjWeaponType.THROWABLE, ProjWeaponStats.ProjWeaponType.SPECIAL_WEAPON]
const all_melee_wpns: Array[MeleeWeaponStats.MeleeWeaponType] = [MeleeWeaponStats.MeleeWeaponType.TOOL, MeleeWeaponStats.MeleeWeaponType.PHYSICAL, MeleeWeaponStats.MeleeWeaponType.COMBAT]

enum ItemRarity {
	COMMON,  ## [b][color=darkgray]0[/color][/b]
	UNCOMMON, ## [b][color=green]1[/color][/b]
	RARE, ## [b][color=dodgerblue]2[/color][/b]
	EPIC, ## [b][color=purple]3[/color][/b]
	LEGENDARY, ## [b][color=gold]4[/color][/b]
	SINGULAR ## [b][color=deeppink]5[/color][/b]
}
const rarity_colors: Dictionary[String, Dictionary] = {
	"ground_glow" : {
		ItemRarity.COMMON : Color(0.617, 0.625, 0.633),
		ItemRarity.UNCOMMON : Color(0, 0.743, 0.433),
		ItemRarity.RARE : Color(0, 0.611, 0.98),
		ItemRarity.EPIC : Color(0.613, 0.475, 1),
		ItemRarity.LEGENDARY : Color(0.926, 0.605, 0),
		ItemRarity.SINGULAR : Color(0.97, 0.13, 0.381)
	},
	"outline_color": {
		ItemRarity.COMMON : Color(0.617, 0.625, 0.633),
		ItemRarity.UNCOMMON : Color(0, 0.743, 0.433),
		ItemRarity.RARE : Color(0, 0.611, 0.98),
		ItemRarity.EPIC : Color(0.53, 0.5, 1.45),
		ItemRarity.LEGENDARY : Color(1.586, 0.655, 0),
		ItemRarity.SINGULAR :  Color(1.45, 0.3, 0.5)
	},
	"tint_color" : {
		ItemRarity.COMMON : Color(0.617, 0.625, 0.633, 0.05),
		ItemRarity.UNCOMMON : Color(0, 0.743, 0.433, 0.05),
		ItemRarity.RARE : Color(0, 0.611, 0.98, 0.05),
		ItemRarity.EPIC : Color(0.613, 0.475, 1, 0.07),
		ItemRarity.LEGENDARY : Color(0.926, 0.605, 0, 0.07),
		ItemRarity.SINGULAR : Color(0.946, 0.3, 0.41, 0.07)
	},
	"glint_color" : {
		ItemRarity.COMMON : Color(0.617, 0.625, 0.633),
		ItemRarity.UNCOMMON : Color(0, 0.743, 0.433),
		ItemRarity.RARE : Color(0, 0.611, 0.98),
		ItemRarity.EPIC : Color(0.613, 0.475, 1),
		ItemRarity.LEGENDARY : Color(0.926, 0.605, 0),
		ItemRarity.SINGULAR : Color(0.946, 0, 0.381)
	},
	"slot_glow" : {
		ItemRarity.COMMON : Color(1.0, 1.0, 1.0),
		ItemRarity.UNCOMMON : Color(0, 0.9659, 0.5629),
		ItemRarity.RARE : Color(0, 0.95, 1.55),
		ItemRarity.EPIC : Color(0.9195, 0.7125, 1.5),
		ItemRarity.LEGENDARY : Color(1.389, 0.9075, 0),
		ItemRarity.SINGULAR : Color(1.42, 0.65, 0.65)
	},
	"slot_fill" : {
		ItemRarity.COMMON : Color(0.517, 0.525, 0.533, 0.75),
		ItemRarity.UNCOMMON : Color(0.226, 0.627, 0.429, 0.75),
		ItemRarity.RARE : Color(0, 0.681, 1.0, 0.75),
		ItemRarity.EPIC : Color(0.545, 0.312, 1, 0.75),
		ItemRarity.LEGENDARY : Color(0.948, 0.642, 0, 0.75),
		ItemRarity.SINGULAR : Color(0.805, 0.266, 0.443, 0.75)
	},
	"ui_text" : {
		ItemRarity.COMMON : Color(0.755, 0.781, 0.772),
		ItemRarity.UNCOMMON : Color(0.558, 0.923, 0.67),
		ItemRarity.RARE : Color(0.374, 0.766, 1.0),
		ItemRarity.EPIC : Color(0.765, 0.68, 1.0),
		ItemRarity.LEGENDARY : Color(0.971, 0.76, 0.509),
		ItemRarity.SINGULAR : Color(1.0, 0.53, 0.665)
	}
}

const invis_char: String = "[color=#AAAAAA00][char=21A5][/color]"

const ui_colors: Dictionary[StringName, Color] = {
	"ui_tan" : Color(0.914, 0.769, 0.741),
	"ui_light_tan" : Color(0.961, 0.894, 0.881),
	"ui_text_outline" : Color(0.0, 0.0, 0.0, 0.565),
	"ui_fail" : Color(1.0, 0.282, 0.361),
	"ui_success" : Color(0.0, 1.0, 0.427),
	"ui_glow_light_tan" : Color(1.825, 1.699, 1.678),
	"ui_glow_success" : Color(0.0, 1.572, 0.689, 1.0),
	"ui_glow_strong_success" : Color(0.0, 1.825, 0.805),
	"ui_glow_fail" : Color(1.572, 0.465, 0.586, 1.0),
	"ui_glow_strong_fail" : Color(1.825, 0.546, 0.686),
	"ui_glow_storm" : Color(1.52, 0.616, 2.352),
	"ui_glow_gold" : Color(1.995, 1.138, 0.736)
}

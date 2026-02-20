extends Resource
class_name ItemStats
## The top level resource stats class for all items in the game.

@export var id: String ## The unique identifier for the item.
@export var name: String ## The item's string name.
@export var tags: Array[StringName] = [] ## The set of tags that are checked against when this item is potentially used for crafting.
@export var item_type: Globals.ItemType = Globals.ItemType.CONSUMABLE ## The type that this item is.
@export var rarity: Globals.ItemRarity = Globals.ItemRarity.COMMON ## The rarity of this item.
@export var stack_size: int = 1 ## The max amount that can stack in one inventory slot.
@export var auto_pickup: bool = false ## Whether this item should automatically be picked up when run over.
@export_custom(PROPERTY_HINT_NONE, "suffix:px") var pickup_radius: int = 4 ## The radius at which the item can be detected for pickup.
@export_multiline var info: String ## The multiline information about this item.
@export var extra_details: Array[StatDetail] = [] ## Additional information to populate into the details panel of the item viewer in the inventory.

@export_group("Visuals")
@export var ground_icon: Texture2D ## The on-ground representation of the item.
@export var in_hand_icon: Texture2D ## The physical representation of the item.
@export var inv_icon: Texture2D ## The inventordy representation of the item.
@export var flip_inv_icon_h: bool = false ## When true, the inv icon will be flipped over the y axis.
@export var inv_icon_offset: Vector2 = Vector2.ZERO ## How much to offset the inv icon in a slot.
@export var inv_icon_scale: Vector2 = Vector2.ONE ## How much to scale the inv icon in a slot.
@export_range(-360, 360, 1, "suffix:degrees") var inv_icon_rotation: float = 0 ## How much to rotate the inv icon in a slot.
@export_subgroup("Cursors")
@export var cursors: SpriteFrames ## The cursors that can show when this item is equipped. Must be a SpriteFrames resource. Can have additional cursor animations within the resource to change depending on scenario (such as a different reloading cursor).

@export_group("Crafting")
@export var recipe: Array[CraftingIngredient] = [] ## The items & quantities required to craft an instance of this item.
@export var exact_input_match: bool = false ## When true, the input slots must not be occupied by any more than the exact ingredient count of this recipe. The slots can contain more than they need, but if a recipe calls for 5 logs, you cannot put 2 in one slot and 3 in another, or any greater-than-that combination. There must be 5 or more in a single slot.
@export var upgrade_recipe: bool = false ## When true, this recipe is treated as an upgrade recipe only, meaning the only way this item is crafted is through an item of lower rarity and its upgrade template. This tells the crafting manager to pass along the mods and levels of the old version to the new version.
@export var output_quantity: int = 1 ## The number of resulting instances of this item that spawn when crafted.
@export var recipe_unlocked: bool = true ## A flag to determine whether or not this item can be crafted. True by default.

@export_category("Equippable WorldItem")
@export var item_scene: PackedScene = null ## The equippable representation of this item. If left null, this item cannot be equipped.
@export_range(0, 1, 0.001) var rotation_lerping: float = 0.1 ## How fast the rotation lerping should be while holding this item.
@export var holding_offset: Vector2 = Vector2.ZERO ## The offset for placing the icon of the sprite in the entity's hand.
@export_custom(PROPERTY_HINT_NONE, "suffix:degrees") var holding_degrees: float = 0 ## The rotation offset for holding the thumnbail sprite in the entity's hand.
@export var stay_flat_on_rotate: bool = false ## When true, rotating over the y axis will not flip the sprite.

@export_group("Hand Positioning")
@export var is_gripped_by_one_hand: bool = true ## Whether or not this item should only have one hand shown gripping it.
@export var draw_off_hand: bool = false ## When true, the hands component will draw the off hand for it as well (hiding the idly animated off hand). This only applies when is_gripped_by_one_hand is false.
@export var draw_off_hand_offset: Vector2 = Vector2.ZERO ## The offset for placing the off hand sprite when holding this item, assuming that draw_off_hand is true and is_gripped_by_one_hand is false.
@export var main_hand_offset: Vector2 = Vector2.ZERO ## The offset for placing the main hand sprite when holding this item.

@export_group("Cooldown Details")
@export var cooldowns_shared: bool = true ## When true, cooldowns will be shared amongst all items of the same base id.
@export var shown_cooldown_fills: Array[String] = [] ## Which cooldown source's can show the vertical fill on the slot when the player invokes a cooldown on this item.
@export var show_cursor_cooldown: bool = false ## When true, the cursor will vertically fill for any cooldown in the array above instead of ever vertically filling for reloads in progress.

@export_group("Sounds")
@export var equip_audio: String ## The sound to play when the item is equipped as an equippable item.
@export var pickup_audio: String ## The sound to play when the item is picked up off the ground.
@export var drop_audio: String ## The sound to play when the item is dropped onto the ground.


## Creates a new item instance with a new UID.
func create_ii(quantity: int) -> II:
	var new: II = II.new()
	new.stats = self
	new.q = quantity
	return new

## Copies an item instance, keeping the same exported properties.
func copy_ii(original_ii: II) -> II:
	var new: II = original_ii.duplicate()
	return new

## The custom string representation of this item resource.
func _to_string() -> String:
	return str(Globals.ItemType.keys()[item_type]) + ": " + get_rarity_string() + "_" + name

## Returns the string title of the rarity rather than just the enum integer value.
func get_rarity_string() -> String:
	return str(Globals.ItemRarity.keys()[rarity])

## Returns the string that identifies the item by its ID and its rarity.
func get_cache_key() -> String:
	return id + "_" + str(rarity)

## Returns the string title of the item type rather than just the enum integer value.
func get_item_type_string(_exact_weapon_type: bool = false) -> String:
	return str(Globals.ItemType.keys()[item_type]).capitalize()

## Whether the item is the same as another item when called externally to compare.
func is_same_as(other_item: ItemStats) -> bool:
	return (str(self) == str(other_item))

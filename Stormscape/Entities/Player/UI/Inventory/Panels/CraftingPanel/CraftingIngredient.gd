extends Resource
class_name CraftingIngredient
## A simple resource that defines either a set of allowed tags or an exact item match required as part of a crafting recipe.

@export_enum("Item", "Tags") var type: String = "Item" ## Whether this ingredient should require an exact item match or allow a set of matching tags. It only requires one matching tag.
@export var item: ItemStats ## The item resource to match.
@export_range(1, 1000, 1) var quantity: int = 1 ## The required quantity of any matching item resources or tagged items.
@export var tags: Array[StringName] = [] ## The set of string tags that are allowed to match in order to be considered valid for this ingredient.
@export_enum("No", "Equal", "GEQ") var rarity_match: String = "No" ## What relative rarities are allowed to be used for this recipe. "No" means no rarity match required. "GEQ" means greater or equal rarity match required.


func _to_string() -> String:
	return type.to_upper() + ": (" + str(quantity) + ") " + (str(item.id) if type == "Item" else str(tags)) + "[" + rarity_match + "]"

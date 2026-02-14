class_name StringHelpers
## A collection of helper methods for dealing with strings.


static func remove_trailing_zero(string: String) -> String:
	var new_string: String = string
	if string.ends_with(".0"):
		new_string = string.substr(0, new_string.length() - 2)
	return new_string

static func get_before_colon(string: String) -> String:
	var new_string: String = string
	var colon_index: int = string.find(":")
	if colon_index != -1:
		new_string = string.substr(0, colon_index)
	return new_string

## Gets and returns all matches in an array based on a search string. Can specify the max return count.
static func get_matching_in_dict(dict: Dictionary, string: StringName, max_count: int,
									show_when_no_input: bool = false) -> Array[String]:
	if string == "" and not show_when_no_input:
		return []

	var matches: Array[String] = []
	var begins_withs: Array[String] = []
	for item: StringName in dict:
		if item.begins_with(string):
			begins_withs.append(item)
		elif item.contains(string):
			matches.append(item)

	begins_withs.sort()
	begins_withs.reverse()
	matches.sort()
	matches.reverse()
	matches.append_array(begins_withs)
	matches.reverse()
	matches.resize(min(max_count, matches.size()))
	matches.reverse()
	return matches

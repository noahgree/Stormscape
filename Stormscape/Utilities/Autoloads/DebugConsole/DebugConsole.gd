extends CanvasLayer
## The console that accepts debug commands to aid in development.

@onready var console_input: LineEdit = %ConsoleInput
@onready var console_input_panel: Panel = %ConsoleInputPanel
@onready var console_output: Label = %ConsoleOutput
@onready var output_outer_margins: MarginContainer = %OutputOuterMargins
@onready var console_autoc: RichTextLabel = %ConsoleAutoComplete
@onready var console_autoc_margins: MarginContainer = %ConsoleAutoCompleteMargins
@onready var autocomplete_outer_margins: MarginContainer = %AutoCompleteOuterMargins
@onready var console_history: RichTextLabel = %ConsoleHistory
@onready var console_history_margins: MarginContainer = %ConsoleHistoryMargins

var commands: Dictionary[StringName, Callable]
var past_commands: Array[String]
var history_index: int = -1
var autocomplete_index: int = -1
var showing_valid_help: bool = false
var showing_autocomplete: bool:
	set(new_value):
		autocomplete_outer_margins.visible = new_value
		showing_autocomplete = new_value
var current_matches: Array[String] = []
const MAX_PAST_COMMANDS: int = 10
const MAX_AUTOCOMPLETES: int = 6


func _ready() -> void:
	hide()
	output_outer_margins.hide()
	console_history_margins.hide()
	autocomplete_outer_margins.hide()
	console_input.editable = false
	add_command("help", func() -> void: print(str(commands.keys()).replace("&", "").replace("\"", "")))
	add_command("clear", func() -> void:
		past_commands.clear()
		console_history.hide()
		)

func add_command(command_name: StringName, callable: Callable) -> void:
	commands[command_name] = callable

func _call_command(command_name: StringName, args: Array[Variant]) -> void:
	var callable: Callable = commands.get(command_name, Callable())
	if callable == Callable():
		printerr("The debug command \"" + command_name + "\" did not exist.")
		MessageManager.add_msg_preset("Command Does Not Exist", MessageManager.Presets.FAIL, 4.0, true)
		return

	var target_object: Object = callable.get_object()
	if callable.is_valid():
		var max_args: int = callable.get_argument_count()
		callable.callv(args.slice(0, max_args))
		_toggle_usage()
		MessageManager.add_msg_preset(command_name + " Command Executed", MessageManager.Presets.NEUTRAL, 4.0, true)
	else:
		printerr("The debug command \"" + command_name + "\" is not valid on the object \"" + str(target_object) + "\".")
		MessageManager.add_msg_preset(command_name + " Not Valid on " + str(target_object), MessageManager.Presets.FAIL, 4.0, true)

func _add_to_command_history(string: String) -> void:
	past_commands.append(string)
	console_history_margins.show()
	if past_commands.size() >= MAX_PAST_COMMANDS:
		past_commands.pop_front()

	_update_command_history_display()

func _update_command_history_display() -> void:
	var all_past_commands: String = ""
	for i: int in range(past_commands.size()):
		var color_str: String = "[color=White][outline_size=2][outline_color=Dodgerblue]" if (i == history_index and not showing_autocomplete) else ""
		all_past_commands += color_str + past_commands[i] + ("[/outline_color][/outline_size][/color]" if color_str != "" else "")
		if i <= past_commands.size() - 2:
			all_past_commands += "\n"
		i += 1
	console_history.text = all_past_commands

	if past_commands.size() > 1:
		console_history_margins.add_theme_constant_override("margin_bottom", 2)
		console_history_margins.add_theme_constant_override("margin_top", 2)
	else:
		console_history_margins.add_theme_constant_override("margin_bottom", -2)
		console_history_margins.add_theme_constant_override("margin_top", -2)

func _update_autocomplete_display() -> void:
	var all_options: String = ""
	for i: int in range(current_matches.size()):
		var color_str: String = "[color=Greenyellow][outline_size=2][outline_color=Darkgreen]" if i == autocomplete_index else ""
		all_options += color_str + current_matches[i] + ("[/outline_color][/outline_size][/color]" if color_str != "" else "")
		if i <= current_matches.size() - 2:
			all_options += "\n"
		i += 1
	if current_matches.is_empty():
		console_autoc.text = "autocomplete..."
		console_autoc.add_theme_color_override("default_color", Color.WEB_GRAY)
	else:
		console_autoc.text = all_options
		console_autoc.remove_theme_color_override("default_color")

	if current_matches.size() > 1:
		console_autoc_margins.add_theme_constant_override("margin_bottom", 2)
		console_autoc_margins.add_theme_constant_override("margin_top", 2)
	else:
		console_autoc_margins.add_theme_constant_override("margin_bottom", -2)
		console_autoc_margins.add_theme_constant_override("margin_top", -2)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("console"):
		_toggle_usage()
	elif event.is_action_pressed("esc"):
		if visible:
			_toggle_usage()
	elif console_input.has_focus() and event is InputEventKey and event.is_pressed() and not event.is_echo():
		match event.keycode:
			KEY_UP:
				if showing_autocomplete:
					if autocomplete_index < 0:
						autocomplete_index = current_matches.size()
					autocomplete_index = wrapi(autocomplete_index - 1, 0, current_matches.size())
					_update_autocomplete_display()
				else:
					if history_index < 0:
						history_index = past_commands.size()
					history_index = wrapi(history_index - 1, 0, min(MAX_PAST_COMMANDS, past_commands.size()))
					_show_history_and_update_text_from_past_commands()
				get_viewport().set_input_as_handled()
			KEY_DOWN:
				if showing_autocomplete:
					if autocomplete_index < 0:
						autocomplete_index = current_matches.size() - 2
					autocomplete_index = wrapi(autocomplete_index + 1, 0, current_matches.size())
					_update_autocomplete_display()
				else:
					if history_index < 0:
						history_index = past_commands.size() - 2
					history_index = wrapi(history_index + 1, 0, min(MAX_PAST_COMMANDS, past_commands.size()))
					_show_history_and_update_text_from_past_commands()
				get_viewport().set_input_as_handled()
			KEY_TAB:
				if showing_autocomplete:
					_update_text_from_autocomplete()
			_ when event.keycode != KEY_RIGHT and event.keycode != KEY_LEFT:
				if showing_autocomplete:
					autocomplete_index = -1
					_update_autocomplete_display()
				else:
					history_index = -1
					_update_command_history_display()

func _toggle_usage() -> void:
	console_input.accept_event()
	console_input.editable = !console_input.editable
	Globals.change_focused_ui_state(console_input.editable, self)
	if console_input.editable:
		console_input.grab_focus()
		history_index = -1
		autocomplete_index = -1
		_update_command_history_display()
	else:
		console_input.release_focus()
		output_outer_margins.hide()

	visible = console_input.editable

func _parse_command(new_text: String) -> void:
	var split_elements: PackedStringArray = new_text.split(" ")
	var strings: Array = Array(split_elements)
	if not strings.is_empty() and not strings[0] == "":
		var i: int = 0
		for string: String in strings:
			if string.is_valid_int():
				strings[i] = int(string)
			elif string.is_valid_float():
				strings[i] = float(string)
			i += 1

		_add_to_command_history(new_text)
		_call_command(str(strings[0]), strings.slice(1))

func _on_console_input_text_changed(new_text: String, from_history_scroll: bool = false) -> void:
	output_outer_margins.hide()
	showing_autocomplete = false
	showing_valid_help = false

	var pieces: PackedStringArray = new_text.split(" ", true)
	var command: String = ArrayHelpers.get_or_default(pieces, 0, "")
	var arg_1: String = ArrayHelpers.get_or_default(pieces, 1, "")
	var valid_autocomplete_option: bool = true
	if command in commands:
		if pieces.size() <= 2 and not from_history_scroll:
			match command:
				"spawn_item", "give":
					current_matches = StringHelpers.get_matching_in_dict(Items.cached_items, arg_1, MAX_AUTOCOMPLETES)
				"set":
					current_matches = StringHelpers.get_matching_in_dict(DebugFlags.get_all_flags(), arg_1, MAX_AUTOCOMPLETES)
				"wpn_mod":
					current_matches = StringHelpers.get_matching_in_dict(Items.get_all_wpn_mods(), arg_1, MAX_AUTOCOMPLETES)
				"sound":
					current_matches = StringHelpers.get_matching_in_dict(AudioManager.sound_cache, arg_1, MAX_AUTOCOMPLETES)
				"stop_sound":
					current_matches = StringHelpers.get_matching_in_dict(AudioManager.get_all_active_sounds(), arg_1, MAX_AUTOCOMPLETES, true)
				"effect":
					current_matches = StringHelpers.get_matching_in_dict(StatusEffectsComponent.cached_status_effects, arg_1, MAX_AUTOCOMPLETES)
				"remove_effect_by_source":
					current_matches = StringHelpers.get_matching_in_dict(Globals.player_node.effects.current_effects, arg_1, MAX_AUTOCOMPLETES, true)
				"remove_effect_by_id":
					current_matches = StringHelpers.get_matching_in_dict(Globals.player_node.effects.get_current_effects_grouped_by_id(), arg_1, MAX_AUTOCOMPLETES, true)
				_:
					valid_autocomplete_option = false

			if valid_autocomplete_option:
				showing_autocomplete = true
				autocomplete_index = current_matches.size() - 1
				_update_autocomplete_display()

		console_output.text = _get_arg_list(commands[pieces[0]].get_object(), commands[pieces[0]].get_method())
		if console_output.text != "":
			output_outer_margins.show()
			showing_valid_help = true
	else:
		if command != "":
			current_matches = StringHelpers.get_matching_in_dict(commands, command, MAX_AUTOCOMPLETES)
			if not current_matches.is_empty():
				showing_autocomplete = true
				autocomplete_index = current_matches.size() - 1
				_update_autocomplete_display()

func _get_arg_list(object: Object, method_name: String) -> String:
	if method_name == "<anonymous lambda>":
		return method_name
	var arg_list: String = ""
	var methods: Array[Dictionary] = object.get_method_list()
	var method_dict: Dictionary
	for method: Dictionary in methods:
		if method.name == method_name:
			method_dict = method
	if method_dict.is_empty():
		return "<static method>"

	var default_args: Array[Variant] = []
	default_args.resize(method_dict.args.size() - method_dict.default_args.size())
	default_args.append_array(method_dict.default_args)

	var i: int = 0
	for arg: Dictionary in method_dict.args:
		var quote_char: String = "\"" if typeof(default_args[i]) in [TYPE_STRING, TYPE_STRING_NAME] else ""
		var default_arg: String = ("=" + quote_char + str(default_args[i]) + quote_char) if default_args[i] != null else ""
		arg_list += "<" + (arg.name) + ":" + type_string(arg.type) + default_arg + ">, "
		i += 1

	return arg_list.trim_suffix(", ")

func _show_history_and_update_text_from_past_commands() -> void:
	console_input.text = ArrayHelpers.get_or_default(past_commands, history_index, console_input.text)
	_on_console_input_text_changed(console_input.text, true)
	_update_command_history_display()
	if not past_commands.is_empty():
		console_history_margins.show()
		await get_tree().process_frame
		console_input.caret_column = console_input.text.length()

func _update_text_from_autocomplete() -> void:
	var pieces: PackedStringArray = console_input.text.split(" ", true)
	var arg_0: String = ArrayHelpers.get_or_default(pieces, 0, "")
	if arg_0 == "":
		return
	var current_match: String = ArrayHelpers.get_or_default(current_matches, autocomplete_index, "")
	if current_match == "":
		return

	if pieces.size() == 1:
		console_input.text = current_match
	else:
		console_input.text = arg_0 + " " + current_match

	_on_console_input_text_changed(console_input.text)
	_update_autocomplete_display()

	await get_tree().process_frame
	console_input.caret_column = console_input.text.length()

extends Control
## Debugging script for having buttons on screen that do test actions.

@export var health_component: HealthComponent
@export var mods: Array[WeaponModStats]
@export var wearables: Array[WearableStats]


func _on_test_hurt_btn_pressed() -> void:
	health_component.damage_shield_then_health(12, "basic_damage", false, -1)

func _on_test_heal_btn_pressed() -> void:
	health_component.heal_health_then_shield(15, "basic_healing", -1)

func _on_test_music_btn_pressed() -> void:
	var audio_player: Variant = AudioManager.play_global("mystery_theme", 0, false, -1, Globals.player_node)
	if audio_player:
		(audio_player as AudioStreamPlayer).process_mode = Node.PROCESS_MODE_ALWAYS
		await get_tree().create_timer(2.5).timeout
		#audio_player.queue_free()
		#AudioManager.stop_audio_player(audio_player)

func _on_test_mod_btn_1_pressed() -> void:
	var i: int = 0
	for mod: WeaponModStats in mods:
		if Globals.player_node.hands.equipped_item:
			WeaponModsManager.handle_weapon_mod(
				Globals.player_node.hands.equipped_item.stats, mod, i, Globals.player_node
				)
		i += 1

func _on_test_mod_btn_2_pressed() -> void:
	var i: int = 0
	for mod: WeaponModStats in mods:
		if Globals.player_node.hands.equipped_item:
			WeaponModsManager.remove_weapon_mod(
				Globals.player_node.hands.equipped_item.stats, mod, i, Globals.player_node
				)
		i += 1

func _on_test_mod_btn_3_pressed() -> void:
	var i: int = 0
	for wearable: WearableStats in wearables:
		WearablesManager.handle_wearable(Globals.player_node, wearable, i)
		i += 1

func _on_test_mod_btn_4_pressed() -> void:
	var i: int = 0
	for wearable: WearableStats in wearables:
		WearablesManager.remove_wearable(Globals.player_node, wearable, i)
		i += 1

func _on_test_storm_pressed() -> void:
	if Globals.storm.is_enabled:
		Globals.storm.disable_storm()
	else:
		Globals.storm.enable_storm()

func _on_test_save_btn_pressed() -> void:
	SaverLoader.save_game()

func _on_test_load_btn_pressed() -> void:
	SaverLoader.load_game()

func _on_test_storm_btn_2_pressed() -> void:
	Globals.storm.force_start_next_phase()

func _on_test_combine_items_pressed() -> void:
	Globals.world_root.get_node("WorldItemsManager")._on_combination_attempt_timer_timeout()

func _on_test_time_btn_pressed() -> void:
	if DayNightManager.current_hour > 7 and DayNightManager.current_hour < 18:
		DayNightManager.change_time(20)
	else:
		DayNightManager.change_time(8)

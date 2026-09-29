extends Control

func _ready():
	$VBoxContainer/DPSButton.pressed.connect(_on_dps_selected)
	$VBoxContainer/TankButton.pressed.connect(_on_tank_selected)
	$VBoxContainer/HealerButton.pressed.connect(_on_healer_selected)

func _on_dps_selected():
	GameState.player_class = 0
	get_tree().change_scene_to_file("res://Home.tscn")
func _on_tank_selected():
	GameState.player_class = 1
	get_tree().change_scene_to_file("res://Home.tscn")
func _on_healer_selected():
	GameState.player_class = 2
	get_tree().change_scene_to_file("res://Home.tscn")

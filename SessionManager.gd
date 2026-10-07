extends Node
## Tracks Pomodoro-style flow time and daily play time.
## Flow time counts while you are out in a zone. Going Home = a break.

signal flow_target_reached
signal break_started(blocks_today)

const FLOW_TARGET := 25.0 * 60.0	# 25 minutes of flow
const MIN_BLOCK := 20.0 * 60.0	# a flow block counts if it lasted at least 20 minutes
const SAVE_PATH := "user://session.cfg"

var flow_seconds := 0.0
var blocks_today := 0
var play_seconds_today := 0.0
var rest_left := 0.0	# seconds of rest left after a deposit

var _flow_signal_sent := false
var _today := ""
var _last_zone := ""
var _save_timer := 0.0


func _ready():
	_today = Time.get_date_string_from_system()
	_load()


func _process(delta):
	var zone = GameState.current_zone

	# Walking into Home starts a break
	if zone == "Home" and _last_zone != "" and _last_zone != "Home":
		_start_break()
	_last_zone = zone

	play_seconds_today += delta
	if rest_left > 0.0:
		rest_left = max(rest_left - delta, 0.0)

	if zone != "Home" and not is_resting():	# resting at a camp or town pauses the flow clock
		flow_seconds += delta
		if flow_seconds >= FLOW_TARGET and not _flow_signal_sent:
			_flow_signal_sent = true
			flow_target_reached.emit()

	# Every 30 seconds: check for a new day and save
	_save_timer += delta
	if _save_timer >= 30.0:
		_save_timer = 0.0
		_check_new_day()
		_save()


func _start_break():
	if flow_seconds >= MIN_BLOCK:
		blocks_today += 1
	flow_seconds = 0.0
	_flow_signal_sent = false
	break_started.emit(blocks_today)
	_save()


## Banked gold at a forward camp or town Inn: counts as a rest at Home.
func rest_here():
	_start_break()
	start_rest(5 * 60)


func start_rest(seconds: float):
	rest_left = seconds


func is_resting() -> bool:
	return rest_left > 0.0


# Test key: F11 skips the rest (only in debug builds)
func _unhandled_input(event):
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		rest_left = 0.0


func is_flow_done() -> bool:
	return flow_seconds >= FLOW_TARGET


## Rewards taper after 3 hours of play in one day (see design doc)
func reward_multiplier() -> float:
	var hours = play_seconds_today / 3600.0
	if hours < 3.0:
		return 1.0
	elif hours < 4.0:
		return lerp(1.0, 0.5, hours - 3.0)
	else:
		return 0.1


func flow_text() -> String:
	var minutes = int(flow_seconds / 60.0)
	var seconds = int(flow_seconds) % 60
	return "Flow %02d:%02d / %d:00" % [minutes, seconds, int(FLOW_TARGET / 60.0)]


func _check_new_day():
	var now = Time.get_date_string_from_system()
	if now != _today:
		_today = now
		play_seconds_today = 0.0
		blocks_today = 0


func _save():
	var cfg = ConfigFile.new()
	cfg.set_value("day", "date", _today)
	cfg.set_value("day", "play_seconds", play_seconds_today)
	cfg.set_value("day", "blocks", blocks_today)
	cfg.save(SAVE_PATH)


func _load():
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	if cfg.get_value("day", "date", "") == _today:
		play_seconds_today = cfg.get_value("day", "play_seconds", 0.0)
		blocks_today = cfg.get_value("day", "blocks", 0)


func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()

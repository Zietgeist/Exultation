extends Node
## Makes failures LOUD and traceable.
## - Catches every Godot error and warning (script errors, missing files, etc.)
## - Writes them to an error log file with the time, file, and line
## - Flashes a red banner on screen so you can't miss it
##
## Use it in code when something goes wrong:
##     ErrorLog.fail("Door leads to a zone that doesn't exist: " + target_scene)
##     ErrorLog.warn("Skin is missing a color for enemy_boss")
##
## Log file:
##     Playing from the Godot editor -> <project folder>/logs/error_log.txt
##     Exported game                 -> user://logs/error_log.txt

const BANNER_SECONDS := 8.0

var log_path := ""
var error_count := 0
var _file: FileAccess = null
var _mutex := Mutex.new()
var _banner: Label = null
var _banner_timer := 0.0
var _logger = null
var _last_line = ""
var _repeats = 0


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	var folder = "res://logs/" if OS.has_feature("editor") else "user://logs/"
	DirAccess.make_dir_recursive_absolute(folder)
	log_path = folder + "error_log.txt"
	_file = FileAccess.open(log_path, FileAccess.READ_WRITE if FileAccess.file_exists(log_path) else FileAccess.WRITE)
	if _file:
		_file.seek_end()
		_write_line("")
		_write_line("===== Game started %s =====" % Time.get_datetime_string_from_system(false, true))
	else:
		push_error("ErrorLog could not open " + log_path)

	_build_banner()

	# Catch ALL engine errors (Godot 4.5+)
	if ClassDB.class_exists("Logger"):
		_logger = load("res://error_catcher.gd").new()
		_logger.sink = self
		OS.add_logger(_logger)


## Something broke. Shows red in Godot, writes to the log, flashes the banner.
func fail(message: String):
	if _logger:
		push_error(message)	# the catcher records it (with file and line)
	else:
		record("ERROR", message, "")


## Something looks wrong but the game can keep going.
func warn(message: String):
	if _logger:
		push_warning(message)
	else:
		record("WARNING", message, "")


## Called by the catcher (may be from another thread).
func record(kind: String, message: String, where: String):
	_mutex.lock()
	var stamp = Time.get_time_string_from_system()
	var line = "%s: %s" % [kind, message]
	if where != "":
		line += "   (at %s)" % where
	if line == _last_line:
		_repeats += 1	# same error again (e.g. every frame): count it, don't flood the log
		if _repeats == 10 or _repeats == 100 or _repeats == 1000:
			_write_line("[%s]   ...repeated %d times" % [stamp, _repeats])
		_mutex.unlock()
		return
	_last_line = line
	_repeats = 0
	_write_line("[%s] %s" % [stamp, line])
	_mutex.unlock()
	if kind == "ERROR":
		call_deferred("_show_banner", message)


func _write_line(text: String):
	if _file:
		_file.store_line(text)
		_file.flush()


func _build_banner():
	var layer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = 6
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.add_theme_color_override("font_color", Color(1, 0.25, 0.25))
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.add_theme_font_size_override("font_size", 20)
	_banner.visible = false
	layer.add_child(_banner)


func _show_banner(message: String):
	error_count += 1
	_banner.text = "ERROR (%d): %s\nSee logs/error_log.txt" % [error_count, message]
	_banner.visible = true
	_banner_timer = BANNER_SECONDS


func _process(delta):
	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer <= 0.0:
			_banner.visible = false

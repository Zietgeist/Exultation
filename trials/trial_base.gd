extends Control
## Base for every shrine trial. A trial is one small screen, 20-45 seconds, mouse and keyboard only.
## Make a new trial: extend this, fill in title/instructions/time_limit/build, and call finish(true/false).
## Then list it in Trials.TYPES (trials.gd).

signal done(passed: bool)

var difficulty := 0.0	# 0 = easiest, 1 = hardest (from your rating in this ability)
var rng := RandomNumberGenerator.new()
var _over := false

const AREA = Vector2(720, 340)	# room the trial gets inside the window
const INK = Color(0.92, 0.9, 0.85)
const GOLD = Color(1.0, 0.85, 0.3)


func title() -> String:
	return "Trial"

func instructions() -> String:
	return ""

## Seconds allowed (can depend on difficulty).
func time_limit() -> float:
	return 30.0

## Make the trial's controls. Called once, after difficulty and rng are set.
func build():
	pass

## A hand for testing: solve it the right way (used by automated tests).
func auto_solve():
	finish(true)


func finish(passed: bool):
	if _over:
		return
	_over = true
	done.emit(passed)


func is_over() -> bool:
	return _over


## Small helper: a label with the trial's font colors.
func make_label(text: String, size := 20, color := INK) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

extends "res://trials/trial_base.gd"
## Swiftness: type the sentence exactly, before time runs out. (Capitals don't matter.)

const SENTENCES = [
	"the quick brown fox jumps over the lazy dog",
	"sphinx of black quartz judge my vow",
	"the five boxing wizards jump quickly",
	"how vexingly quick daft zebras jump",
	"pack my box with five dozen jugs of jam",
	"bright vixens jump while dozy fowl quack",
	"a quart jar of oil mixed with zinc oxide makes a very bright paint",
]

var target := ""
var shown: RichTextLabel
var box: LineEdit


func title() -> String:
	return "Swift Hands"

func instructions() -> String:
	return "Type the sentence exactly. Capitals don't matter."

func time_limit() -> float:
	var cps = lerp(2.5, 5.5, difficulty)	# letters per second (about 30 to 66 words a minute)
	return 2.0 + target.length() / cps


func build():
	custom_minimum_size = AREA
	var pool = SENTENCES.filter(func(s): return s.length() <= 45) if difficulty < 0.6 else SENTENCES
	target = pool[rng.randi() % pool.size()]
	var v = VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 24)
	add_child(v)
	shown = RichTextLabel.new()
	shown.bbcode_enabled = true
	shown.fit_content = true
	shown.custom_minimum_size = Vector2(AREA.x, 60)
	shown.add_theme_font_size_override("normal_font_size", 28)
	v.add_child(shown)
	box = LineEdit.new()
	box.custom_minimum_size = Vector2(AREA.x - 40, 48)
	box.add_theme_font_size_override("font_size", 24)
	box.text_changed.connect(_on_typed)
	v.add_child(box)
	_on_typed("")
	box.grab_focus.call_deferred()


func _on_typed(text: String):
	if is_over():
		return
	var typed = text.to_lower()
	var good = 0
	while good < typed.length() and good < target.length() and typed[good] == target[good]:
		good += 1
	var wrong = typed.length() > good
	var out = "[center][color=#7cff8a]%s[/color]" % target.substr(0, good)
	if wrong:
		out += "[color=#ff6a5a]%s[/color]" % target.substr(good, 1)
		out += "[color=#e8e4da]%s[/color]" % target.substr(good + 1)
	else:
		out += "[color=#e8e4da]%s[/color]" % target.substr(good)
	shown.text = out + "[/center]"
	if typed == target:
		finish(true)


func auto_solve():
	box.text = target
	_on_typed(target)

extends Node3D
## Base for every Godot shot (R56): the picture is a function of the frame number, never of wall-clock time, so Movie
## Maker writes the same frames on any machine speed. tools/render-shot.py passes --shot, --size, --frames and --seed
## after "--". A shot script extends this file, builds its world in build() and places everything in pose(frame).

const MIN_MOVE_FRAMES := 18  # R17: nothing travels in under 0.6 s at 30 fps

var shot := ""  # variant name from engines/shots.json ("shot")
var frames := 300  # frames this render writes, preroll included
var seed_value := 1
var look := {}  # the film's look: engines/look.json, written from src/lib/look.ts by tools/export-look.mts
var palette := {}  # the look named by the shot's "look" field, else the first one
var fps := 30
var frame := 0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"shot": shot = kv[1]
			"frames": frames = int(kv[1])
			"seed": seed_value = int(kv[1])
			"size":
				var wh := kv[1].split("x")
				get_tree().root.content_scale_size = Vector2i(int(wh[0]), int(wh[1]))
	look = load_look()
	fps = int(look.get("fps", 30))
	var looks: Dictionary = look.get("looks", {})
	palette = looks.values()[0] if looks.size() > 0 else {}
	rng.seed = seed_value
	seed(seed_value)
	build()
	pose(0)


func _process(_delta: float) -> void:
	pose(frame)
	frame += 1


## Override: create nodes once.
func build() -> void:
	pass


## Override: set every animated property from the frame number alone.
func pose(_f: int) -> void:
	pass


static func load_look() -> Dictionary:
	var file := ProjectSettings.globalize_path("res://").path_join("../look.json")
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null:
		push_error("no %s: run node --no-warnings tools/export-look.mts" % file)
		return {}
	return JSON.parse_string(f.get_as_text())


func color(key: String, gain := 1.0) -> Color:
	var c := Color(str(palette.get(key, "#ff00ff")))
	return Color(c.r * gain, c.g * gain, c.b * gain, c.a)


## The template's calm in-out curve (src/lib/ease.ts SOFT_POINTS): a CSS-style cubic bezier solved for x.
func soft(x: float) -> float:
	var p: Array = look.get("softPoints", [0.45, 0, 0.55, 1])
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	var x1 := float(p[0])
	var y1 := float(p[1])
	var x2 := float(p[2])
	var y2 := float(p[3])
	var cx := 3.0 * x1
	var bx := 3.0 * (x2 - x1) - cx
	var ax := 1.0 - cx - bx
	var cy := 3.0 * y1
	var by := 3.0 * (y2 - y1) - cy
	var ay := 1.0 - cy - by
	var t := x
	for i in 8:
		var err := ((ax * t + bx) * t + cx) * t - x
		if absf(err) < 1e-7:
			break
		var d := (3.0 * ax * t + 2.0 * bx) * t + cx
		if absf(d) < 1e-7:
			break
		t -= err / d
	t = clampf(t, 0.0, 1.0)
	return ((ay * t + by) * t + cy) * t


## 0..1 over [at, at + dur] frames with the soft curve; dur is raised to MIN_MOVE_FRAMES (motion.ts `move`).
func move(f: float, at: float, dur: float) -> float:
	return soft((f - at) / maxf(dur, MIN_MOVE_FRAMES))


func tween(f: float, at: float, dur: float, from, to):
	return lerp(from, to, move(f, at, dur))

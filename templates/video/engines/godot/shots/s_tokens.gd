extends "res://lib/aos_shot.gd"
## Example shot: tokens flowing through a model's layers. Six layers of eight nodes, each joined to three nodes of the
## next layer; 320 tokens follow seeded routes, resting softly on each node. Every position is computed from the frame
## (no accumulated state), so a rerun is pixel-identical. Variants: "wide" (default) and "close".

const LAYERS := 6
const PER_LAYER := 8
const LINKS := 3
const TOKENS := 320

var nodes := []  # [layer][index] -> Vector3
var links := []  # [layer][index] -> Array of indices in the next layer
var routes := []  # token -> Array of node indices, one per layer
var periods := PackedFloat32Array()
var phases := PackedFloat32Array()
var camera: Camera3D
var token_mesh: MultiMesh
var node_mesh: MultiMesh


func build() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = color("bg")
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = float(palette.get("exposure", 1.0))
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = float(palette.get("bloom", {}).get("strength", 0.5)) * 0.2
	env.glow_hdr_threshold = float(palette.get("bloom", {}).get("threshold", 1.0))
	env.fog_enabled = true
	env.fog_light_color = color("bg")
	env.fog_density = 0.035
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	camera = Camera3D.new()
	camera.fov = 30.0
	add_child(camera)

	for k in LAYERS:
		var layer := []
		for j in PER_LAYER:
			var a: float = TAU * float(j) / PER_LAYER + float(k) * 0.35
			layer.append(Vector3((float(k) - (LAYERS - 1) / 2.0) * 2.4, sin(a) * 1.7, cos(a) * 1.7))
		nodes.append(layer)
	for k in LAYERS - 1:
		var layer := []
		for j in PER_LAYER:
			var picks := []
			while picks.size() < LINKS:
				var n := rng.randi_range(0, PER_LAYER - 1)
				if not picks.has(n):
					picks.append(n)
			layer.append(picks)
		links.append(layer)
	for i in TOKENS:
		var route := [rng.randi_range(0, PER_LAYER - 1)]
		for k in LAYERS - 1:
			var options: Array = links[k][route[-1]]
			route.append(options[rng.randi_range(0, options.size() - 1)])
		routes.append(route)
		periods.append(rng.randf_range(5.0, 8.0) * fps)
		phases.append(rng.randf())

	var lines := ImmediateMesh.new()
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var ink := color("inkSoft")
	line_mat.albedo_color = Color(ink.r, ink.g, ink.b, 0.28)
	lines.surface_begin(Mesh.PRIMITIVE_LINES, line_mat)
	for k in LAYERS - 1:
		for j in PER_LAYER:
			for n in links[k][j]:
				lines.surface_add_vertex(nodes[k][j])
				lines.surface_add_vertex(nodes[k + 1][n])
	lines.surface_end()
	var line_node := MeshInstance3D.new()
	line_node.mesh = lines
	add_child(line_node)

	node_mesh = _multimesh(0.11, LAYERS * PER_LAYER)
	token_mesh = _multimesh(0.045, TOKENS)
	for k in LAYERS:
		for j in PER_LAYER:
			node_mesh.set_instance_transform(k * PER_LAYER + j, Transform3D(Basis(), nodes[k][j]))


func _multimesh(radius: float, count: int) -> MultiMesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	sphere.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = sphere
	mm.instance_count = count
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	add_child(inst)
	return mm


func pose(f: int) -> void:
	var close := shot == "close"
	# a slow lateral track along the layers, close enough that the graph fills the frame
	var from := Vector3(-3.2, 0.9, 4.4) if close else Vector3(-6.5, 1.4, 9.0)
	var to := Vector3(-1.2, 0.5, 3.9) if close else Vector3(-1.0, 0.8, 8.2)
	var eye: Vector3 = tween(f, 0, frames, from, to)
	var target: Vector3 = tween(f, 0, frames, Vector3(-2.6, 0, 0), Vector3(1.6, 0, 0))
	camera.look_at_from_position(eye, target, Vector3.UP)

	var accent := color("accent", float(palette.get("accentGain", 6.0)) * 0.35)
	var lit := PackedFloat32Array()
	lit.resize(LAYERS * PER_LAYER)
	for i in TOKENS:
		var s := fposmod(f / periods[i] + phases[i], 1.0) * (LAYERS - 1)
		var seg := mini(int(s), LAYERS - 2)
		var u := s - seg
		var a: Vector3 = nodes[seg][routes[i][seg]]
		var b: Vector3 = nodes[seg + 1][routes[i][seg + 1]]
		var p := a.lerp(b, soft(u)) + Vector3(0, sin(PI * u) * 0.12, 0)
		var fade := smoothstep(0.0, 0.4, s) * (1.0 - smoothstep(LAYERS - 1.4, LAYERS - 1.0, s))
		token_mesh.set_instance_transform(i, Transform3D(Basis(), p))
		token_mesh.set_instance_color(i, Color(accent.r * fade, accent.g * fade, accent.b * fade))
		var near := 1.0 - smoothstep(0.0, 0.18, minf(u, 1.0 - u))
		var layer := seg if u < 0.5 else seg + 1
		var idx: int = layer * PER_LAYER + int(routes[i][layer])
		lit[idx] = minf(1.0, lit[idx] + near * fade * 0.5)
	var ink := color("ink")
	for n in LAYERS * PER_LAYER:
		var g := 0.55 + lit[n] * 1.6
		node_mesh.set_instance_color(n, Color(ink.r * g, ink.g * g, ink.b * g))

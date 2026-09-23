extends Node3D
# TIDEMILL Godot port - water-first milestone.
# Ocean with depth-based shoreline foam around a test island platform.
# Town grammar, interaction and save come after the water reads right.

var cam: Camera3D
var t := 0.0

func _ready():
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.42, 0.66, 0.63)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.95, 0.85)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.91, 0.75)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-52, -38, 0)
	add_child(sun)

	cam = Camera3D.new()
	cam.far = 220.0
	add_child(cam)

	# ocean
	var water_mat := ShaderMaterial.new()
	water_mat.shader = load("res://shaders/water.gdshader")
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 160)
	plane.subdivide_width = 96
	plane.subdivide_depth = 96
	water.mesh = plane
	water.material_override = water_mat
	add_child(water)

	# test island: stands in for the town platform so the foam has a shore
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.62, 0.64, 0.58)
	stone.roughness = 0.85
	var island := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(7, 0.9, 7)
	island.mesh = box
	island.position.y = 0.28
	island.material_override = stone
	add_child(island)

	# a few test houses on the platform so scale reads
	for i in 3:
		var c := StandardMaterial3D.new()
		c.albedo_color = [Color(0.88, 0.38, 0.29), Color(0.91, 0.64, 0.24), Color(0.96, 0.9, 0.73)][i]
		c.roughness = 0.8
		var h := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(1.5, 1.4 + float(i) * 0.5, 1.5)
		h.mesh = b
		h.position = Vector3(-2.0 + float(i) * 2.0, 0.73 + b.size.y * 0.5, 0.6 * float(i % 2))
		h.material_override = c
		add_child(h)
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.78, 0.42, 0.28)
		rm.roughness = 0.75
		var roof := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(1.7, 0.7, 1.7)
		roof.mesh = prism
		roof.position = h.position + Vector3(0, b.size.y * 0.5 + 0.35, 0)
		roof.material_override = rm
		add_child(roof)

func _process(delta):
	t += delta
	var r := 16.0
	cam.position = Vector3(cos(t * 0.1) * r, 8.5, sin(t * 0.1) * r)
	cam.look_at(Vector3(0, 0.5, 0), Vector3.UP)

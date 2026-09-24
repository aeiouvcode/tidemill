extends Node3D
# TIDEMILL - Godot port of the original v4 (three.js) build.
# Same irregular grid (baked from v4 into grid.json), same block grammar,
# same share-link format, so a town link from v4 opens here unchanged.

const GRID_SEED := 11
const MAXK := 30
const G0 := 0.3
const FH := 1.0
const PALETTE := ["#e95c5b", "#ee8a5a", "#f2cf63", "#d9e070", "#a9c07a", "#7fc466", "#48b977", "#46b8a0", "#48afc8", "#5b8fe0", "#7777c9", "#b25670", "#d6ae8e", "#b3a69c", "#ecebe6"]
const ROOFS := ["#e58a5c", "#d7654e", "#eaa865", "#c95f4c"]
const B64 := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
const MS := 256
const MB := 17.0

var P: Array = []        # Vector2 per grid vertex
var cells: Array = []    # {v: PackedInt32Array, c: Vector2, nb: PackedInt32Array}
var E: Array = []        # E[c][i] edge dictionaries
var vcells := {}         # grid vertex -> cells touching it
var blocks := {}         # c*32+k -> colour index
var PAL: Array = []
var ROOF: Array = []
var CAP: Color; var COBBLE: Color; var STONE: Color; var RAIL: Color
var FRAME: Color; var PANE: Color; var PANE_HI: Color; var DOOR: Color

var town: Node3D
var MAT := {}
var outline_mat: StandardMaterial3D
var water_mat: ShaderMaterial
var mask_img: Image
var mask_tex: ImageTexture
var mask_wide_tex: ImageTexture
var refl_vp: SubViewport
var refl_cam: Camera3D
var refl_n := 0
var refl_last := Transform3D()
var pick_groups: Array = []  # [PackedVector3Array positions, Array info]

var cam: Camera3D
var target := Vector3(1.3, 3.3, -0.7)
var dist := 43.0
var base_dist := 43.0
var zoom_mul := 1.0
var fit0 := {}
var goal_target := Vector3(1.3, 3.3, -0.7)
var goal_dist := 43.0
var az := 0.55
var pol := 0.98
var v_az := 0.0
var v_pol := 0.0
var last_interact := 0.0
var t := 0.0

var color := 0
var erase := false
var undo_stack: Array = []
var gulls: Array = []
var ripples: Array = []
var ring_mesh: Mesh

# ui
var pal_buttons: Array = []
var erase_btn: Button
var hint: Label
var title: Label
var toast: Label
var toast_t := 0.0
var hint_gone := false

# ---------------------------------------------------------------- utils
static func lin(h: String) -> Color:
	return Color(h)

static func shade(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f)

static func hsh(n: Array) -> float:
	var h := 2166136261
	for x in n:
		h = (h ^ ((int(x) + 0x9e3779b9) & 0xFFFFFFFF)) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
		h = h ^ (h >> 13)
	return float(h % 10000) / 10000.0

func key(c: int, k: int) -> int:
	return c * 32 + k

func has(c: int, k: int) -> bool:
	return c >= 0 and k >= 0 and blocks.has(c * 32 + k)

func vp(i: int, y: float) -> Vector3:
	var p: Vector2 = P[i]
	return Vector3(p.x, y, p.y)

# ---------------------------------------------------------------- geometry builder
class GB:
	var p := PackedVector3Array()
	var n := PackedVector3Array()
	var u := PackedVector2Array()
	var c := PackedColorArray()
	var info: Array = []
	var ctx = null
	var alt: GB = null
	var mc := -1
	var mk := -1

	func tri(a: Vector3, b: Vector3, d: Vector3, ca: Color, cb: Color, cd: Color, ua := Vector2.ZERO, ub := Vector2.ZERO, ud := Vector2.ZERO, want := Vector3.ZERO) -> void:
		if alt != null and ctx != null and ctx.c == mc and ctx.k == mk:
			alt.ctx = ctx
			alt.tri(a, b, d, ca, cb, cd, ua, ub, ud, want)
			return
		var nn := (b - a).cross(d - a).normalized()
		if want != Vector3.ZERO and nn.dot(want) < 0.0:
			tri(a, d, b, ca, cd, cb, ua, ud, ub)
			return
		p.append(a); p.append(b); p.append(d)
		n.append(nn); n.append(nn); n.append(nn)
		c.append(ca); c.append(cb); c.append(cd)
		u.append(ua); u.append(ub); u.append(ud)
		info.append(ctx)

	func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, col, uv = null, want := Vector3.ZERO) -> void:
		var cs: Array = col if col is Array else [col, col, col, col]
		var us: Array = uv if uv != null else [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		var V := [a, b, d, e]
		var C := cs
		var U := us
		if want != Vector3.ZERO and (b - a).cross(d - a).dot(want) < 0.0:
			V = [a, e, d, b]; C = [cs[0], cs[3], cs[2], cs[1]]; U = [us[0], us[3], us[2], us[1]]
		tri(V[0], V[1], V[2], C[0], C[1], C[2], U[0], U[1], U[2])
		tri(V[0], V[2], V[3], C[0], C[2], C[3], U[0], U[2], U[3])

	func box(ctr: Vector3, tt: Vector3, nn: Vector3, hx: float, hy: float, hz: float, col: Color) -> void:
		var T := tt * hx
		var Y := Vector3.UP * hy
		var N := nn * hz
		var faces := [
			[tt, Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(1, -1, 1)],
			[-tt, Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1)],
			[Vector3.UP, Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1)],
			[Vector3.DOWN, Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1)],
			[nn, Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
			[-nn, Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, -1, -1)]]
		for f in faces:
			var q := []
			for i in range(1, 5):
				var s: Vector3 = f[i]
				q.append(ctr + T * s.x + Y * s.y + N * s.z)
			quad(q[0], q[1], q[2], q[3], col, null, f[0])

	func mesh() -> ArrayMesh:
		# Godot treats clockwise as front-facing: flip each triangle.
		var P2 := PackedVector3Array(); var N2 := PackedVector3Array()
		var U2 := PackedVector2Array(); var C2 := PackedColorArray()
		var cnt := p.size()
		P2.resize(cnt); N2.resize(cnt); U2.resize(cnt); C2.resize(cnt)
		for i in range(0, cnt, 3):
			for j in 3:
				var s: int = i + [0, 2, 1][j]
				P2[i + j] = p[s]; N2[i + j] = n[s]; U2[i + j] = u[s]; C2[i + j] = c[s]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = P2; arr[Mesh.ARRAY_NORMAL] = N2
		arr[Mesh.ARRAY_TEX_UV] = U2; arr[Mesh.ARRAY_COLOR] = C2
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

# ---------------------------------------------------------------- setup
func _ready() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://grid.json"))
	for p in data.P:
		P.append(Vector2(p[0], p[1]))
	for cl in data.cells:
		cells.append({v = PackedInt32Array(cl.v), c = Vector2(cl.c[0], cl.c[1]), nb = PackedInt32Array(cl.nb)})
	for c in cells.size():
		for vi in cells[c].v:
			if not vcells.has(vi): vcells[vi] = []
			vcells[vi].append(c)
	for c in cells.size():
		var row := []
		for i in 4:
			row.append(_edge(c, i))
		E.append(row)
	for h in PALETTE: PAL.append(lin(h))
	for h in ROOFS: ROOF.append(lin(h))
	CAP = lin("#ecc27e"); COBBLE = lin("#c7b3a3"); STONE = lin("#b9aea6"); RAIL = lin("#34424f")
	FRAME = lin("#f4f1ea"); PANE = lin("#34465f"); PANE_HI = lin("#6d8aa6"); DOOR = lin("#6e4b3b")

	_scene()
	_ui()
	if OS.has_feature("web"):
		var q := str(_win().location.search)
		if q.find("slow=") >= 0: Engine.time_scale = 0.15
	var loaded = _decode(_hash())
	if loaded == null:
		loaded = _decode(_stored())
	if loaded == null:
		loaded = {}
		for pair in data.town:
			loaded[int(pair[0])] = int(pair[1])
	var dflt := {}
	for pair in data.town: dflt[int(pair[0])] = int(pair[1])
	fit0 = _fit(dflt)
	blocks = loaded
	rebuild()
	_save()
	get_viewport().size_changed.connect(_frame)
	_frame()

func _edge(c: int, i: int) -> Dictionary:
	var cl: Dictionary = cells[c]
	var ia: int = cl.v[i]
	var ib: int = cl.v[(i + 1) % 4]
	var a: Vector2 = P[ia]
	var b: Vector2 = P[ib]
	var tt := Vector3(b.x - a.x, 0, b.y - a.y).normalized()
	var nn := Vector3(tt.z, 0, -tt.x)
	var m := (a + b) * 0.5
	var cc: Vector2 = cl.c
	if nn.x * (m.x - cc.x) + nn.z * (m.y - cc.y) < 0.0:
		nn = -nn
	return {a = ia, b = ib, t = tt, n = nn, m = m, L = a.distance_to(b)}

func _frame() -> void:
	var s := get_viewport().get_visible_rect().size
	base_dist = 43.0 if s.x < s.y else 29.0
	if refl_vp: refl_vp.size = Vector2i(maxi(64, int(s.x * 0.3)), maxi(64, int(s.y * 0.3)))
	_reframe()
	dist = goal_dist; target = goal_target

func _scene() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var fog := Color("#4a898e")
	e.background_mode = Environment.BG_COLOR
	e.background_color = fog
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#c4e2e0")
	e.ambient_light_energy = 0.38
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = 1.0
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = fog
	e.fog_depth_begin = 45.0
	e.fog_depth_end = 120.0
	e.fog_density = 1.0
	e.fog_sky_affect = 0.0
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#fff0d8")
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.0
	add_child(sun)
	sun.look_at_from_position(Vector3(-14, 22, 10), Vector3.ZERO, Vector3.UP)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#9fd3dc")
	fill.light_energy = 0.4
	add_child(fill)
	fill.look_at_from_position(Vector3(12, 8, -10), Vector3.ZERO, Vector3.UP)

	cam = Camera3D.new()
	cam.fov = 30.0
	cam.near = 0.5
	cam.far = 400.0
	add_child(cam)

	MAT.W = _mat(_tex_brick(), Vector3(1, 1, 1))
	MAT.RF = _mat(_tex_tile(), Vector3(1.4, 1, 1))
	MAT.RF.cull_mode = BaseMaterial3D.CULL_DISABLED
	MAT.GR = _mat(_tex_cobble(), Vector3(0.9, 0.9, 1))
	MAT.ST = _mat(_tex_stone(), Vector3(1.3, 1.3, 1))
	MAT.PL = _mat(null, Vector3.ONE)
	outline_mat = StandardMaterial3D.new()
	outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline_mat.albedo_color = Color(0.122, 0.176, 0.212, 0.5)

	town = Node3D.new()
	add_child(town)

	mask_img = Image.create(MS, MS, false, Image.FORMAT_L8)
	mask_tex = ImageTexture.create_from_image(mask_img)
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/water.gdshader")
	water_mat.set_shader_parameter("mask", mask_tex)
	water_mat.set_shader_parameter("mb", MB)
	mask_wide_tex = ImageTexture.create_from_image(mask_img)
	water_mat.set_shader_parameter("mask_wide", mask_wide_tex)
	# planar reflection: a low-res mirrored camera renders the town (not the sea)
	refl_vp = SubViewport.new()
	refl_vp.transparent_bg = true
	refl_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	refl_vp.size = Vector2i(256, 256)
	add_child(refl_vp)
	refl_cam = Camera3D.new()
	refl_cam.cull_mask = 1
	refl_vp.add_child(refl_cam)
	water_mat.set_shader_parameter("refl", refl_vp.get_texture())
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	water.mesh = plane
	water.material_override = water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.layers = 2
	add_child(water)

	# gulls
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#f7f7f2")
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wing := ArrayMesh.new()
	var wa := []
	wa.resize(Mesh.ARRAY_MAX)
	wa[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, -0.07), Vector3(0.42, 0.02, 0), Vector3(0, 0, 0.07)])
	wa[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	wing.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wa)
	for i in 4:
		var g := Node3D.new()
		var l := MeshInstance3D.new(); l.mesh = wing; l.material_override = gm
		var r := MeshInstance3D.new(); r.mesh = wing; r.material_override = gm; r.scale.x = -1
		var body := MeshInstance3D.new()
		var sm := SphereMesh.new(); sm.radius = 0.06; sm.height = 0.12; sm.radial_segments = 8; sm.rings = 6
		body.mesh = sm; body.material_override = gm; body.scale = Vector3(1, 0.8, 2.2)
		g.add_child(l); g.add_child(r); g.add_child(body)
		add_child(g)
		gulls.append({n = g, l = l, r = r, rad = 4.0 + i * 1.6, h = 7.0 + i * 1.3, sp = 0.18 + i * 0.05, ph = i * 1.7})
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9; tm.outer_radius = 1.0; tm.rings = 48; tm.ring_segments = 3
	ring_mesh = tm

func _mat(tex: Texture2D, scale: Vector3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	if tex:
		m.albedo_texture = tex
		m.uv1_scale = scale
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

# ---------------------------------------------------------------- textures (drawn in code)
func _img(bg: String) -> Image:
	var im := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	im.fill(Color(bg))
	return im

func _grey(v: int, d := 0) -> Color:
	return Color8(v, v - d, v - 2 * d)

func _done(im: Image) -> ImageTexture:
	im.generate_mipmaps()
	return ImageTexture.create_from_image(im)

func _tex_brick() -> ImageTexture:
	var im := _img("#d9d6d2")
	var r := RandomNumberGenerator.new(); r.seed = 135
	for y in range(0, 128, 8):
		for x in range(-16, 128, 16):
			var ox := 8 if (y / 8) % 2 == 1 else 0
			im.fill_rect(Rect2i(x + ox + 1, y + 1, 15, 7).intersection(Rect2i(0, 0, 128, 128)), _grey(222 + int(r.randf() * 33)))
	return _done(im)

func _tex_tile() -> ImageTexture:
	var im := _img("#a8a4a0")
	var r := RandomNumberGenerator.new(); r.seed = 138
	for row in 10:
		var y0 := int(row * 12.8)
		var x := -14
		while x < 142:
			var ox := 7 if row % 2 == 1 else 0
			var v := 215 + int(r.randf() * 40)
			for yy in 12:
				var f := float(yy) / 12.0
				var rc := Rect2i(x + ox + 1, y0 + yy, 13, 1).intersection(Rect2i(0, 0, 128, 128))
				if rc.size.x > 0 and rc.size.y > 0:
					im.fill_rect(rc, _grey(int(v - 45 * f)))
			x += 14
	return _done(im)

func _tex_cobble() -> ImageTexture:
	var im := _img("#a9a4a0")
	var r := RandomNumberGenerator.new(); r.seed = 134
	for i in 260:
		var cx := r.randf() * 128.0
		var cy := r.randf() * 128.0
		var rr := 3.0 + r.randf() * 4.0
		var col := _grey(200 + int(r.randf() * 50), 4)
		var ang := r.randf() * 3.0
		var ca := cos(ang); var sa := sin(ang)
		for yy in range(int(cy - rr) - 1, int(cy + rr) + 2):
			for xx in range(int(cx - rr) - 1, int(cx + rr) + 2):
				var dx := xx - cx; var dy := yy - cy
				var u := (dx * ca + dy * sa) / rr
				var w := (-dx * sa + dy * ca) / (rr * 0.8)
				if u * u + w * w <= 1.0:
					im.set_pixel(posmod(xx, 128), posmod(yy, 128), col)
	return _done(im)

func _tex_stone() -> ImageTexture:
	var im := _img("#8f8a86")
	var r := RandomNumberGenerator.new(); r.seed = 140
	var y := 0.0
	while y < 128.0:
		var ox := 16 if int(round(y / 21.33)) % 2 == 1 else 0
		for x in range(-40, 128, 32):
			var rc := Rect2i(x + ox + 2, int(y) + 2, 29, 18).intersection(Rect2i(0, 0, 128, 128))
			if rc.size.x > 0: im.fill_rect(rc, _grey(190 + int(r.randf() * 55)))
		y += 21.33
	return _done(im)

# ---------------------------------------------------------------- town grammar (port of v4 buildTown)
func _land_seg(c: int, ci: int, a2: Vector2, b2: Vector2, ei: int, top: bool, ST: GB, PL: GB) -> void:
	var L := a2.distance_to(b2)
	if L < 0.001: return
	var tt := Vector3(b2.x - a2.x, 0, b2.y - a2.y) / L
	var nn := Vector3(tt.z, 0, -tt.x)
	var cc: Vector2 = cells[c].c
	var m := (a2 + b2) * 0.5
	if nn.x * (m.x - cc.x) + nn.z * (m.y - cc.y) < 0.0: nn = -nn
	var A := func(y: float) -> Vector3: return Vector3(a2.x, y, a2.y)
	var B := func(y: float) -> Vector3: return Vector3(b2.x, y, b2.y)
	ST.ctx = {c = c, k = 0, t = "side", e = ei}
	var dk := shade(STONE, 0.45)
	var u0 := a2.x * tt.x + a2.y * tt.z
	ST.quad(A.call(-1.4), B.call(-1.4), B.call(G0 - 0.1), A.call(G0 - 0.1), [dk, dk, STONE, STONE], [Vector2(u0, -1.4), Vector2(u0 + L, -1.4), Vector2(u0 + L, G0), Vector2(u0, G0)], nn)
	# stone footing: a heavier plinth stepping out at the waterline
	var fo := nn * 0.08
	var fc := shade(STONE, 0.78)
	ST.quad(A.call(-0.5) + fo, B.call(-0.5) + fo, B.call(0.02) + fo, A.call(0.02) + fo, [shade(fc, 0.6), shade(fc, 0.6), fc, fc], [Vector2(u0, -0.5), Vector2(u0 + L, -0.5), Vector2(u0 + L, 0.02), Vector2(u0, 0.02)], nn)
	ST.quad(A.call(0.02), B.call(0.02), B.call(0.02) + fo, A.call(0.02) + fo, shade(STONE, 0.9), null, Vector3.UP)
	PL.ctx = {c = c, k = 0, t = "side", e = ei}
	var col: Color = PAL[ci]
	var o := nn * 0.035
	var a0: Vector3 = A.call(G0 - 0.12) + o; var b0: Vector3 = B.call(G0 - 0.12) + o
	var b1: Vector3 = B.call(G0 + 0.03) + o; var a1: Vector3 = A.call(G0 + 0.03) + o
	PL.quad(a0, b0, b1, a1, col, null, nn)
	PL.quad(a1, b1, B.call(G0 + 0.03), A.call(G0 + 0.03), shade(col, 1.08), null, Vector3.UP)
	PL.quad(a0, b0, B.call(G0 - 0.12) - nn * 0.02, A.call(G0 - 0.12) - nn * 0.02, shade(col, 0.6), null, Vector3.DOWN)
	if top:
		PL.ctx = {c = c, k = 0, t = "rail"}
		var inset := nn * -0.06
		var a: Vector3 = A.call(0) + inset; var b: Vector3 = B.call(0) + inset
		var posts := maxi(1, roundi(L / 0.17))
		for j in posts + 1:
			var pp := a.lerp(b, float(j) / posts); pp.y = G0 + 0.17
			PL.box(pp, tt, nn, 0.011, 0.14, 0.011, RAIL)
		var mm := a.lerp(b, 0.5); mm.y = G0 + 0.32
		PL.box(mm, tt, nn, L / 2.0 + 0.012, 0.016, 0.02, RAIL)

func _conn(c: int, k: int, i: int) -> int:
	var n: int = cells[c].nb[i]
	return 1 if has(n, k) and not has(n, k + 1) else 0

func _is_tower(c: int, k: int) -> bool:
	if not (k >= 4 and has(c, k - 1) and has(c, k - 2) and has(c, k - 3)): return false
	for i in 4:
		if has(cells[c].nb[i], k): return false
	return true

func _column_tall(c: int) -> bool:
	var n := 0
	for k in range(1, MAXK):
		if has(c, k): n += 1
	return n >= 4

func build_town(ac := -1, ak := -1) -> Dictionary:
	var W := GB.new(); var RF := GB.new(); var GR := GB.new(); var ST := GB.new(); var PL := GB.new()
	if ac >= 0:
		for g in [W, RF, GR, ST, PL]:
			g.alt = GB.new(); g.mc = ac; g.mk = ak
	var lamps := []; var bushes := []; var finials := []
	var list := []
	for kk in blocks.keys():
		list.append([int(kk) / 32, int(kk) % 32])
	var ridge := {}
	for ck in list:
		var c: int = ck[0]; var k: int = ck[1]
		if k < 1 or has(c, k + 1): continue
		var cA := _conn(c, k, 0) + _conn(c, k, 2)
		var cB := _conn(c, k, 1) + _conn(c, k, 3)
		var p := 0
		if cA != cB:
			p = 0 if cA > cB else 1
		else:
			var m0: Vector2 = E[c][0].m; var m1: Vector2 = E[c][1].m; var m2: Vector2 = E[c][2].m; var m3: Vector2 = E[c][3].m
			p = 0 if m0.distance_to(m2) >= m1.distance_to(m3) else 1
		ridge[key(c, k)] = p
	var joined := func(c: int, k: int, i: int) -> bool:
		var n: int = cells[c].nb[i]
		if _conn(c, k, i) == 0: return false
		var j: int = Array(cells[n].nb).find(c)
		return ridge.get(key(n, k), -1) == j % 2

	for ck in list:
		var c: int = ck[0]; var k: int = ck[1]
		var cl: Dictionary = cells[c]
		var ci: int = blocks[key(c, k)]
		if k == 0:
			var top := not has(c, 1)
			if top:
				GR.ctx = {c = c, k = 0, t = "top"}
				var q := []; var qu := []
				for vi in cl.v:
					var pt := vp(vi, G0); q.append(pt); qu.append(Vector2(pt.x * 0.9, pt.z * 0.9))
				GR.quad(q[0], q[1], q[2], q[3], COBBLE, qu, Vector3.UP)
			# outline with Townscaper-style rounded convex corners on open quays
			var rnd := []
			for i in 4:
				var pv := (i + 3) % 4
				var free_v := true
				for oc in vcells[cl.v[i]]:
					if oc != c and has(oc, 0): free_v = false
				rnd.append(top and not has(cl.nb[pv], 0) and not has(cl.nb[i], 0) and free_v)
			var outline := []
			var segs := []
			for i in 4:
				var a: Vector2 = P[cl.v[i]]; var b: Vector2 = P[cl.v[(i + 1) % 4]]
				var pa: Vector2 = P[cl.v[(i + 3) % 4]]
				var L := a.distance_to(b)
				var dir := (b - a) / L
				var dprev := (a - pa).normalized()
				var r := minf(0.3, minf(L, pa.distance_to(a)) * 0.45)
				var s0 := a + dir * r if rnd[i] else a
				if rnd[i]:
					var p0 := a - dprev * r
					var last := p0
					for j in range(0, 7):
						var tt := j / 6.0
						var q := p0 * (1 - tt) * (1 - tt) + a * 2 * (1 - tt) * tt + s0 * tt * tt
						outline.append(q)
						if j > 0: segs.append([last, q, i])
						last = q
				else:
					outline.append(a)
				var nxt: bool = rnd[(i + 1) % 4]
				var e1 := b - dir * minf(0.3, minf(L, b.distance_to(P[cl.v[(i + 2) % 4]])) * 0.45) if nxt else b
				if not has(cl.nb[i], 0): segs.append([s0, e1, i])
			if top:
				GR.ctx = {c = c, k = 0, t = "top"}
				var C0 := Vector3(cl.c.x, G0, cl.c.y)
				for j in outline.size():
					var q1: Vector2 = outline[j]; var q2: Vector2 = outline[(j + 1) % outline.size()]
					var A3 := Vector3(q1.x, G0, q1.y); var B3 := Vector3(q2.x, G0, q2.y)
					GR.tri(C0, A3, B3, COBBLE, COBBLE, COBBLE, Vector2(C0.x, C0.z) * 0.9, Vector2(A3.x, A3.z) * 0.9, Vector2(B3.x, B3.z) * 0.9, Vector3.UP)
			for sg in segs:
				_land_seg(c, ci, sg[0], sg[1], sg[2], top, ST, PL)
			if top:
				var nbld := []
				for i in 4:
					if has(cl.nb[i], 1): nbld.append(i)
				if nbld.size() > 0 and hsh([c, 3]) < 0.42:
					var e: Dictionary = E[c][nbld[int(hsh([c, 4]) * nbld.size())]]
					var s := 0.18 + hsh([c, 5]) * 0.1
					var cc: Vector2 = cl.c; var em: Vector2 = e.m
					bushes.append([Vector3(cc.x + (em.x - cc.x) * 0.55, G0 + s * 0.8, cc.y + (em.y - cc.y) * 0.55), s, hsh([c, 6])])
			continue
		# building floor
		var yb := G0 + (k - 1) * FH
		var yt := yb + FH
		var tint := 0.95 + hsh([c, k, 1]) * 0.08
		var wc := shade(PAL[ci], tint)
		var roof_top := not has(c, k + 1)
		var door_done := false
		for i in 4:
			var n: int = cl.nb[i]
			if has(n, k): continue
			var e: Dictionary = E[c][i]
			W.ctx = {c = c, k = k, t = "wall", e = i}
			var bf := 0.72 if (k == 1 or not has(c, k - 1)) else 1.0
			var tf := 0.88 if roof_top else 1.0
			W.quad(vp(e.a, yb), vp(e.b, yb), vp(e.b, yt), vp(e.a, yt), [shade(wc, bf), shade(wc, bf), shade(wc, tf), shade(wc, tf)], [Vector2(0, yb), Vector2(e.L, yb), Vector2(e.L, yt), Vector2(0, yt)], e.n)
			PL.ctx = {c = c, k = k, t = "wall", e = i}
			var em: Vector2 = e.m
			var et: Vector3 = e.t; var en: Vector3 = e.n
			var at := func(dx: float, y: float, off: float) -> Vector3:
				return Vector3(em.x, y, em.y) + et * dx + en * off
			var rect := func(cx: float, cy: float, w: float, h: float, off: float, col: Color) -> void:
				PL.quad(at.call(cx - w / 2, cy - h / 2, off), at.call(cx + w / 2, cy - h / 2, off), at.call(cx + w / 2, cy + h / 2, off), at.call(cx - w / 2, cy + h / 2, off), col, null, en)
			var door_ok: bool = k == 1 and not door_done and has(n, 0) and not has(n, 1) and e.L > 0.45
			if door_ok and hsh([c, i, 7]) < 0.7:
				door_done = true
				var w := 0.26; var h := 0.52
				rect.call(0.0, yb + h / 2 + 0.01, w + 0.07, h + 0.05, 0.012, FRAME)
				rect.call(0.0, yb + h / 2, w, h, 0.02, DOOR)
				rect.call(0.0, yb + h - 0.08, w * 0.6, 0.1, 0.024, PANE_HI)
				lamps.append(at.call(w / 2 + 0.12, yb + 0.62, 0.06))
				continue
			if e.L < 0.5 or hsh([c, k, i, 9]) > (0.95 if _column_tall(c) else 0.8): continue
			var w2: float = minf(0.3, e.L * 0.34); var h2 := 0.34; var cy := yb + FH * 0.55
			rect.call(0.0, cy, w2 + 0.07, h2 + 0.07, 0.012, FRAME)
			rect.call(0.0, cy + h2 * 0.25, w2 - 0.02, h2 * 0.45, 0.02, PANE_HI)
			rect.call(0.0, cy - h2 * 0.25, w2 - 0.02, h2 * 0.45, 0.02, PANE)
			rect.call(0.0, cy, 0.025, h2, 0.026, FRAME)
			rect.call(0.0, cy, w2, 0.025, 0.026, FRAME)
			rect.call(0.0, cy - h2 / 2 - 0.045, w2 + 0.12, 0.035, 0.03, shade(FRAME, 0.92))
		if k > 1 and not has(c, k - 1):
			W.ctx = {c = c, k = k, t = "under"}
			var q := []; var qu := []
			for vi in cl.v:
				var pt := vp(vi, yb); q.append(pt); qu.append(Vector2(pt.x, pt.z))
			W.quad(q[0], q[1], q[2], q[3], shade(wc, 0.6), qu, Vector3.DOWN)
		if not roof_top: continue
		RF.ctx = {c = c, k = k, t = "top"}
		var C: Vector2 = cl.c
		if _is_tower(c, k):
			var ring := []
			for i in 4:
				var a: Vector2 = P[cl.v[i]]; var b: Vector2 = P[cl.v[(i + 1) % 4]]
				for f in [0.2, 0.8]:
					ring.append(a.lerp(b, f))
			var rp := func(s: float, y: float) -> Array:
				var out := []
				for pp in ring:
					out.append(Vector3(C.x + (pp.x - C.x) * s, y, C.y + (pp.y - C.y) * s))
				return out
			var r0: Array = rp.call(1.16, yt - 0.06); var r1: Array = rp.call(1.0, yt + 0.12); var r2: Array = rp.call(0.62, yt + 0.62)
			var apex := Vector3(C.x, yt + 1.25, C.y)
			var q := []
			for vi in cl.v: q.append(vp(vi, yt))
			RF.quad(q[0], q[1], q[2], q[3], CAP, null, Vector3.UP)
			for i in 8:
				var j := (i + 1) % 8
				var out := Vector3((r0[i].x + r0[j].x) / 2 - C.x, 0.6, (r0[i].z + r0[j].z) / 2 - C.y).normalized()
				RF.quad(r0[i], r0[j], r1[j], r1[i], shade(CAP, 0.95), [Vector2(0, 0), Vector2(0.5, 0), Vector2(0.5, 0.2), Vector2(0, 0.2)], out)
				RF.quad(r1[i], r1[j], r2[j], r2[i], CAP, [Vector2(0, 0.2), Vector2(0.5, 0.2), Vector2(0.5, 0.8), Vector2(0, 0.8)], out)
				RF.tri(r2[i], r2[j], apex, CAP, CAP, CAP, Vector2(0, 0.8), Vector2(0.4, 0.8), Vector2(0.2, 1.4), out)
			finials.append([apex, ci])
			continue
		var p: int = ridge[key(c, k)]
		var rc: Color = ROOF[(ci + (0 if hsh([c, 2]) < 0.5 else 1)) % ROOF.size()]
		var Ec: Array = E[c]
		var rh := 0.72; var oh := 0.13; var drop := 0.08
		var v0 := vp(cl.v[p % 4], yt - drop); var v1 := vp(cl.v[(p + 1) % 4], yt - drop)
		var v2 := vp(cl.v[(p + 2) % 4], yt - drop); var v3 := vp(cl.v[(p + 3) % 4], yt - drop)
		var eA: Dictionary = Ec[(p + 1) % 4]; var eB: Dictionary = Ec[(p + 3) % 4]
		v1 += eA.n * oh; v2 += eA.n * oh; v3 += eB.n * oh; v0 += eB.n * oh
		var mp: Vector2 = Ec[p].m; var mq: Vector2 = Ec[(p + 2) % 4].m
		var R1 := Vector3(mp.x, yt + rh, mp.y); var R2 := Vector3(mq.x, yt + rh, mq.y)
		var rd := (R2 - R1).normalized()
		var j1: bool = joined.call(c, k, p); var j2: bool = joined.call(c, k, (p + 2) % 4)
		if not j1:
			var s := rd * -0.1; R1 += s; v0 += s; v1 += s
		if not j2:
			var s := rd * 0.1; R2 += s; v2 += s; v3 += s
		var ruv := func(pt: Vector3) -> Vector2: return Vector2(pt.x * rd.x + pt.z * rd.z, (pt.y - yt) * 2.2)
		var upA: Vector3 = (eA.n + Vector3(0, 1.2, 0)).normalized()
		var upB: Vector3 = (eB.n + Vector3(0, 1.2, 0)).normalized()
		var rd9 := shade(rc, 0.9)
		RF.quad(v1, v2, R2, R1, [rd9, rd9, rc, rc], [ruv.call(v1), ruv.call(v2), ruv.call(R2), ruv.call(R1)], upA)
		RF.quad(v3, v0, R1, R2, [rd9, rd9, rc, rc], [ruv.call(v3), ruv.call(v0), ruv.call(R1), ruv.call(R2)], upB)
		for g in [[p, j1, Vector3(mp.x, yt + rh, mp.y)], [(p + 2) % 4, j2, Vector3(mq.x, yt + rh, mq.y)]]:
			if g[1]: continue
			var ei: int = g[0]; var Rp: Vector3 = g[2]
			var e: Dictionary = Ec[ei]
			W.ctx = {c = c, k = k, t = "wall", e = ei}
			W.tri(vp(e.a, yt), vp(e.b, yt), Rp, shade(wc, 0.9), shade(wc, 0.9), shade(wc, 0.84), Vector2(0, yt), Vector2(e.L, yt), Vector2(e.L / 2, yt + rh), e.n)
			if e.L > 0.6 and hsh([c, k, ei, 11]) < 0.6:
				PL.ctx = {c = c, k = k, t = "wall", e = ei}
				var em: Vector2 = e.m
				var Mx := Vector3(em.x, yt + 0.26, em.y)
				var nn: Vector3 = e.n; var tt: Vector3 = e.t
				for sq in [[0.08, 0.09, 0.012, FRAME], [0.055, 0.065, 0.02, PANE]]:
					var O: Vector3 = nn * sq[2]; var w: float = sq[0]; var h: float = sq[1]
					PL.quad(Mx - tt * w + Vector3(0, -h, 0) + O, Mx + tt * w + Vector3(0, -h, 0) + O, Mx + tt * w + Vector3(0, h, 0) + O, Mx - tt * w + Vector3(0, h, 0) + O, sq[3], null, nn)
		if hsh([c, k, 13]) < 0.28 and Ec[p].L > 0.5:
			W.ctx = {c = c, k = k, t = "top"}
			var eb: Dictionary = Ec[(p + 3) % 4]
			var ebm: Vector2 = eb.m
			var mb := Vector3(ebm.x, yt, ebm.y); var mr := R1.lerp(R2, 0.3)
			var pos := mb.lerp(Vector3(mr.x, yt, mr.z), 0.55)
			var hr := yt + rh * 0.55
			var top_y := yt + rh + 0.22; var bot := hr - 0.1
			W.box(Vector3(pos.x, (top_y + bot) / 2, pos.z), rd, Vector3(rd.z, 0, -rd.x), 0.08, (top_y - bot) / 2, 0.08, shade(wc, 0.85))
	return {W = W, RF = RF, GR = GR, ST = ST, PL = PL, lamps = lamps, bushes = bushes, finials = finials}

# ---------------------------------------------------------------- rebuild
# Townscaper-style auto framing: the camera eases out and re-centres as the
# town grows, scaled so the default town frames exactly like v4.
func _fit(b: Dictionary) -> Dictionary:
	if b.is_empty(): return {c = Vector3(0, 0, 0), r = 3.0}
	var lo := Vector2(1e9, 1e9); var hi := Vector2(-1e9, -1e9); var ymax := 0.0
	for kk in b.keys():
		var c: int = int(kk) / 32; var k: int = int(kk) % 32
		var cc: Vector2 = cells[c].c
		lo = lo.min(cc); hi = hi.max(cc)
		ymax = maxf(ymax, G0 + k * FH + (1.25 if k > 0 else 0.3))
	var mid := (lo + hi) * 0.5
	var r := maxf((hi - lo).length() * 0.5 + 1.0, ymax * 0.62)
	return {c = Vector3(mid.x, ymax * 0.33, mid.y), r = r}

func _reframe() -> void:
	if fit0.is_empty(): return
	var f := _fit(blocks)
	var sc: float = maxf(0.55, f.r / fit0.r)
	goal_dist = clampf(base_dist * sc * zoom_mul, 7.0, 90.0)
	goal_target = Vector3(1.3, 3.3, -0.7) + (f.c - fit0.c)

var rise: Node3D = null
var rise_t := -1.0
var drops: Array = []

func rebuild(ac := -1, ak := -1) -> void:
	for ch in town.get_children():
		ch.queue_free()
	pick_groups = []
	_reframe()
	var B := build_town(ac, ak)
	if rise: rise.queue_free(); rise = null
	if ac >= 0:
		rise = Node3D.new(); town.add_child(rise); rise_t = 0.0
		for k in ["W", "RF", "GR", "ST", "PL"]:
			var ag: GB = B[k].alt
			if ag.p.is_empty(): continue
			var mi := MeshInstance3D.new(); mi.mesh = ag.mesh(); mi.material_override = MAT[k]
			rise.add_child(mi)
			pick_groups.append([ag.p, ag.info])
		rise.position.y = -0.9
	for k in ["W", "RF", "GR", "ST", "PL"]:
		var gb: GB = B[k]
		if gb.p.is_empty(): continue
		var mi := MeshInstance3D.new()
		mi.mesh = gb.mesh()
		mi.material_override = MAT[k]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if k == "GR" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		town.add_child(mi)
		pick_groups.append([gb.p, gb.info])
		if k != "PL":
			var lm := _edges(gb.p, gb.n, 28.0)
			if lm:
				var li := MeshInstance3D.new(); li.mesh = lm; li.material_override = outline_mat
				li.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				town.add_child(li)
	var greens := [Color("#3f7a4f"), Color("#4d8a4a"), Color("#35684a")]
	for b in B.bushes:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new(); sm.radius = 1.0; sm.height = 2.0; sm.radial_segments = 8; sm.rings = 4
		mi.mesh = sm
		var m := StandardMaterial3D.new(); m.albedo_color = greens[int(b[2] * 3) % 3]; m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT; m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mi.material_override = m
		mi.position = b[0]; mi.scale = Vector3(b[1], b[1] * 1.05, b[1]); mi.rotation = Vector3(b[2] * 3, b[2] * 5, 0)
		town.add_child(mi)
	var lamp_m := StandardMaterial3D.new(); lamp_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; lamp_m.albedo_color = Color("#ffe6a3")
	for lp in B.lamps:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new(); sm.radius = 0.045; sm.height = 0.09; sm.radial_segments = 10; sm.rings = 8
		mi.mesh = sm; mi.material_override = lamp_m; mi.position = lp
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		town.add_child(mi)
	for f in B.finials:
		var mi := MeshInstance3D.new(); mi.mesh = _finial_mesh()
		var m := StandardMaterial3D.new(); m.albedo_color = shade(PAL[f[1]], 0.7); m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT; m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mi.material_override = m; mi.position = f[0] - Vector3(0, 0.04, 0)
		town.add_child(mi)
	_rebuild_mask()
	if OS.has_feature("web"):
		_win().__tmCount = blocks.size()

var _fin: ArrayMesh
func _finial_mesh() -> ArrayMesh:
	if _fin: return _fin
	var prof := [Vector2(0, 0), Vector2(0.05, 0.02), Vector2(0.09, 0.12), Vector2(0.05, 0.2), Vector2(0.025, 0.24), Vector2(0.025, 0.3), Vector2(0.05, 0.36), Vector2(0.012, 0.52), Vector2(0, 0.56)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 10
	for s in seg:
		var a0 := TAU * s / seg; var a1 := TAU * (s + 1) / seg
		for i in prof.size() - 1:
			var p0: Vector2 = prof[i]; var p1: Vector2 = prof[i + 1]
			var A := Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x); var B2 := Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var C2 := Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x); var D := Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			for v in [A, D, C2, A, C2, B2]: st.add_vertex(v)
	st.generate_normals()
	_fin = st.commit()
	return _fin

func _edges(pos: PackedVector3Array, nor: PackedVector3Array, deg: float) -> ArrayMesh:
	var th := cos(deg_to_rad(deg))
	var map := {}
	var q := func(v: Vector3) -> Vector3i: return Vector3i(roundi(v.x * 1000), roundi(v.y * 1000), roundi(v.z * 1000))
	for i in range(0, pos.size(), 3):
		for j in 3:
			var a: Vector3i = q.call(pos[i + j]); var b: Vector3i = q.call(pos[i + (j + 1) % 3])
			var kk := [a, b] if (a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z < b.z)))) else [b, a]
			var ks := str(kk)
			if map.has(ks): map[ks][2].append(nor[i])
			else: map[ks] = [pos[i + j], pos[i + (j + 1) % 3], [nor[i]]]
	var lines := PackedVector3Array()
	for ks in map:
		var ent: Array = map[ks]
		var ns: Array = ent[2]
		if ns.size() == 1 or (ns.size() >= 2 and (ns[0] as Vector3).dot(ns[1]) <= th):
			lines.append(ent[0]); lines.append(ent[1])
	if lines.is_empty(): return null
	var arr := []; arr.resize(Mesh.ARRAY_MAX); arr[Mesh.ARRAY_VERTEX] = lines
	var m := ArrayMesh.new(); m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	return m

func _point_in_cell(c: int, x: float, z: float) -> bool:
	var v: PackedInt32Array = cells[c].v
	var inside := false
	var j := 3
	for i in 4:
		var a: Vector2 = P[v[i]]; var b: Vector2 = P[v[j]]
		if (a.y > z) != (b.y > z) and x < (b.x - a.x) * (z - a.y) / (b.y - a.y) + a.x:
			inside = not inside
		j = i
	return inside

func _rebuild_mask() -> void:
	mask_img.fill(Color.BLACK)
	for c in cells.size():
		if not has(c, 0) and not has(c, 1): continue
		var v: PackedInt32Array = cells[c].v
		var lo := Vector2(1e9, 1e9); var hi := Vector2(-1e9, -1e9)
		for i in v:
			lo = lo.min(P[i]); hi = hi.max(P[i])
		var x0 := int((lo.x + MB) / (2 * MB) * MS); var x1 := int((hi.x + MB) / (2 * MB) * MS) + 1
		var y0 := int((lo.y + MB) / (2 * MB) * MS); var y1 := int((hi.y + MB) / (2 * MB) * MS) + 1
		for py in range(maxi(0, y0), mini(MS, y1 + 1)):
			for px in range(maxi(0, x0), mini(MS, x1 + 1)):
				var wx := (px + 0.5) / MS * 2 * MB - MB; var wz := (py + 0.5) / MS * 2 * MB - MB
				if _point_in_cell(c, wx, wz): mask_img.set_pixel(px, py, Color.WHITE)
	# soft blur via native down/up-sampling (stands in for v4's 3-pass box blur)
	var b := mask_img.duplicate() as Image
	b.resize(26, 26, Image.INTERPOLATE_LANCZOS)
	b.resize(MS, MS, Image.INTERPOLATE_CUBIC)
	mask_tex.update(b)
	var bw := mask_img.duplicate() as Image
	bw.resize(11, 11, Image.INTERPOLATE_LANCZOS)
	bw.resize(MS, MS, Image.INTERPOLATE_CUBIC)
	mask_wide_tex.update(bw)

# ---------------------------------------------------------------- save / share
func _win():
	return JavaScriptBridge.get_interface("window")

func _hash() -> String:
	if not OS.has_feature("web"): return ""
	var h = _win().location.hash
	return str(h).substr(1) if h != null else ""

func _stored() -> String:
	if not OS.has_feature("web"): return ""
	var ls = _win().localStorage
	if ls == null: return ""
	var v = ls.getItem("tidemill.town.v3")
	return str(v) if v != null else ""


func _encode() -> String:
	var ks := blocks.keys(); ks.sort()
	var out := "g%d." % GRID_SEED
	for k in ks:
		var v: int = ((int(k) / 32) << 12) | ((int(k) % 32) << 6) | int(blocks[k])
		out += B64[(v >> 18) & 63] + B64[(v >> 12) & 63] + B64[(v >> 6) & 63] + B64[v & 63]
	return out

func _decode(s: String):
	var re := RegEx.create_from_string("^g(\\d+)\\.([A-Za-z0-9_-]*)$")
	var m := re.search(s)
	if m == null or int(m.get_string(1)) != GRID_SEED: return null
	var d := m.get_string(2)
	var res := {}
	var i := 0
	while i + 3 < d.length():
		var v := (B64.find(d[i]) << 18) | (B64.find(d[i + 1]) << 12) | (B64.find(d[i + 2]) << 6) | B64.find(d[i + 3])
		var c := v >> 12; var lv := (v >> 6) & 63; var col := v & 63
		if c < cells.size() and lv < MAXK and col < PALETTE.size(): res[key(c, lv)] = col
		i += 4
	return res if res.size() > 0 else null

func _save() -> void:
	var s := _encode()
	if OS.has_feature("web"):
		var w = _win()
		if w.localStorage != null: w.localStorage.setItem("tidemill.town.v3", s)
		w.history.replaceState(null, "", "#" + s)

func _share() -> void:
	_save()
	if OS.has_feature("web"):
		var w = _win()
		var u := str(w.location.href)
		if w.navigator.share != null:
			var o = JavaScriptBridge.create_object("Object")
			o.title = "My Tidemill town"; o.url = u
			w.navigator.share(o)
		elif w.navigator.clipboard != null:
			w.navigator.clipboard.writeText(u); _say("Link copied")
		else:
			_say("Link is in the address bar")
	else:
		_say("Link copied")

# ---------------------------------------------------------------- interaction
func _pick(sp: Vector2):
	var o := cam.project_ray_origin(sp)
	var d := cam.project_ray_normal(sp)
	var best := INF; var best_info = null
	for g in pick_groups:
		var pos: PackedVector3Array = g[0]; var info: Array = g[1]
		for i in range(0, pos.size(), 3):
			var a := pos[i]; var e1 := pos[i + 1] - a; var e2 := pos[i + 2] - a
			var h := d.cross(e2); var det := e1.dot(h)
			if absf(det) < 1e-8: continue
			var f := 1.0 / det; var s := o - a
			var u := f * s.dot(h)
			if u < 0.0 or u > 1.0: continue
			var qq := s.cross(e1); var v := f * d.dot(qq)
			if v < 0.0 or u + v > 1.0: continue
			var tt := f * e2.dot(qq)
			if tt > 0.001 and tt < best:
				best = tt; best_info = info[i / 3]
	if best_info != null:
		return {info = best_info, point = o + d * best}
	if absf(d.y) < 1e-6: return null
	var tw := -o.y / d.y
	if tw <= 0: return null
	var p := o + d * tw
	for c in cells.size():
		if _point_in_cell(c, p.x, p.z):
			return {info = {c = c, k = -1, t = "water"}, point = p}
	return null

func act(sp: Vector2, force_erase := false) -> void:
	var h = _pick(sp)
	if h == null or h.info == null: return
	var inf: Dictionary = h.info
	var c: int = inf.c; var k: int = inf.k; var ty: String = inf.t
	var rem := force_erase or erase
	var tc := -1; var tk := -1
	if rem:
		if ty != "water": tc = c; tk = k
	elif ty == "water": tc = c; tk = 0
	elif ty == "top": tc = c; tk = k + 1
	elif ty == "rail": tc = c; tk = 1
	elif ty == "under": tc = c; tk = k - 1
	elif ty == "side": tc = cells[c].nb[inf.e]; tk = 0
	elif ty == "wall": tc = cells[c].nb[inf.e]; tk = k
	if tc < 0 or tk < 0 or tk >= MAXK: return
	if rem:
		if not has(tc, tk): return
		undo_stack.append(blocks.duplicate())
		blocks.erase(key(tc, tk))
	else:
		if has(tc, tk): return
		undo_stack.append(blocks.duplicate())
		blocks[key(tc, tk)] = color
		if tk >= 1 and not has(tc, 0): blocks[key(tc, 0)] = color
	if undo_stack.size() > 120: undo_stack.pop_front()
	_tone(tk, rem)
	_ripple(h.point)
	if rem: rebuild()
	else:
		rebuild(tc, tk)
		if tk == 0: _splash(cells[tc].c)
	_save(); _hide_hint()
	if OS.has_feature("web") and _win().navigator.vibrate != null: _win().navigator.vibrate(18 if rem else 8)

var _ac = null
func _tone(k: int, remove: bool) -> void:
	if not OS.has_feature("web"): return
	var w = _win()
	if _ac == null:
		if w.AudioContext == null: return
		_ac = JavaScriptBridge.create_object("AudioContext")
	var sc := [0, 2, 4, 7, 9]
	var n: int = -5 if remove else sc[k % 5] + 12 * (k / 5)
	var f := 392.0 * pow(2.0, mini(n, 24) / 12.0)
	var t0: float = _ac.currentTime
	var o = _ac.createOscillator(); var g = _ac.createGain()
	o.type = "triangle"; o.frequency.value = f
	g.gain.setValueAtTime(0.0001, t0); g.gain.exponentialRampToValueAtTime(0.09, t0 + 0.01)
	g.gain.exponentialRampToValueAtTime(0.0001, t0 + (0.25 if remove else 0.6))
	o.connect(g); g.connect(_ac.destination); o.start(t0); o.stop(t0 + 0.7)

var drop_mesh: SphereMesh
func _splash(c: Vector2) -> void:
	if drop_mesh == null:
		drop_mesh = SphereMesh.new(); drop_mesh.radius = 0.055; drop_mesh.height = 0.11; drop_mesh.radial_segments = 6; drop_mesh.rings = 3
	for i in 18:
		var a := TAU * i / 18.0 + randf() * 0.4
		var r := 0.45 + randf() * 0.35
		var m := MeshInstance3D.new(); m.mesh = drop_mesh
		var mat := StandardMaterial3D.new(); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; mat.albedo_color = Color(0.95, 0.99, 1.0, 1.0)
		m.material_override = mat; m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.position = Vector3(c.x + cos(a) * r, 0.05, c.y + sin(a) * r)
		m.scale = Vector3.ONE * (0.6 + randf() * 0.8)
		add_child(m)
		drops.append({m = m, t = 0.0, v = Vector3(cos(a) * (0.6 + randf()), 2.2 + randf() * 1.6, sin(a) * (0.6 + randf()))})
	_ripple(Vector3(c.x, 0.0, c.y))
	get_tree().create_timer(0.18).timeout.connect(func(): _ripple(Vector3(c.x, 0.0, c.y)))
	# foam stir: a soft white disc that spreads and fades around the new piece
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 1.0; cm.bottom_radius = 1.0; cm.height = 0.01; cm.radial_segments = 32
	disc.mesh = cm
	var dm := StandardMaterial3D.new(); dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; dm.albedo_color = Color(0.93, 0.97, 0.94, 0.55)
	disc.material_override = dm; disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position = Vector3(c.x, 0.03, c.y); disc.scale = Vector3(0.5, 1, 0.5)
	add_child(disc)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(disc, "scale", Vector3(1.5, 1, 1.5), 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(dm, "albedo_color:a", 0.0, 0.9)
	tw.chain().tween_callback(disc.queue_free)

func _ripple(p: Vector3) -> void:
	var m := MeshInstance3D.new(); m.mesh = ring_mesh
	var mat := StandardMaterial3D.new(); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; mat.albedo_color = Color(1, 1, 1, 0.8); mat.no_depth_test = false
	m.material_override = mat; m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = p + Vector3(0, 0.02, 0); m.scale = Vector3(0.2, 0.01, 0.2)
	add_child(m); ripples.append({m = m, t = 0.0})

var touches := {}
var down = null
var pinch0 := 0.0
var dist0 := 0.0

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		last_interact = t
		if ev.pressed:
			touches[ev.index] = ev.position
			if touches.size() == 1:
				down = {p = ev.position, t = t, moved = false, used = false}
			else:
				down = null
				var ps := touches.values(); pinch0 = (ps[0] as Vector2).distance_to(ps[1]); dist0 = zoom_mul
		else:
			touches.erase(ev.index)
			if down != null and not down.moved and not down.used and t - down.t < 0.45:
				act(down.p, false)
			down = null
	elif ev is InputEventScreenDrag:
		last_interact = t
		touches[ev.index] = ev.position
		if touches.size() >= 2:
			var ps := touches.values()
			var dd := (ps[0] as Vector2).distance_to(ps[1])
			if pinch0 > 0: zoom_mul = clampf(dist0 * pinch0 / maxf(dd, 1.0), 0.25, 2.2); _reframe()
		else:
			if down != null and (ev.position - down.p).length() > 8: down.moved = true
			if down == null or down.moved:
				var hgt := get_viewport().get_visible_rect().size.y
				v_az = -TAU * ev.relative.x / hgt * 0.55
				v_pol = -TAU * ev.relative.y / hgt * 0.55
	elif ev is InputEventMouseButton and ev.pressed:
		last_interact = t
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP: zoom_mul = clampf(zoom_mul * 0.92, 0.25, 2.2); _reframe()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom_mul = clampf(zoom_mul / 0.92, 0.25, 2.2); _reframe()
		elif ev.button_index == MOUSE_BUTTON_RIGHT: act(ev.position, true)

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	t += dt
	if down != null and not down.moved and not down.used and touches.size() == 1 and t - down.t > 0.48 and not DisplayServer.is_touchscreen_available() == false:
		down.used = true
		act(down.p, true)
	if t - last_interact > 14.0:
		az += TAU / 60.0 * 0.35 * dt
	az += v_az; pol = clampf(pol + v_pol, 0.25, 1.38)
	v_az *= 0.92 if touches.size() == 0 else 0.0
	v_pol *= 0.92 if touches.size() == 0 else 0.0
	var kf := 1.0 - exp(-dt * 2.2)
	target = target.lerp(goal_target, kf); dist = lerpf(dist, goal_dist, kf)
	cam.position = target + Vector3(sin(pol) * sin(az), cos(pol), sin(pol) * cos(az)) * dist
	cam.look_at(target, Vector3.UP)
	refl_cam.fov = cam.fov; refl_cam.near = cam.near; refl_cam.far = cam.far
	var mp := Vector3(cam.position.x, -cam.position.y, cam.position.z)
	refl_cam.look_at_from_position(mp, Vector3(target.x, -target.y, target.z), Vector3.UP)
	# throttle the mirror render: every 2nd frame while the view moves, every 6th when still
	refl_n += 1
	var moving := not refl_cam.global_transform.is_equal_approx(refl_last)
	if refl_n >= (2 if moving else 6):
		refl_n = 0; refl_last = refl_cam.global_transform
		refl_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	water_mat.set_shader_parameter("u_time", t)
	water_mat.set_shader_parameter("focus", Vector2(target.x, target.z))
	for g in gulls:
		var a: float = t * g.sp + g.ph
		g.n.position = Vector3(cos(a) * g.rad, g.h + sin(t * 0.7 + g.ph) * 0.4, sin(a) * g.rad)
		g.n.rotation.y = -a
		var f := sin(t * 6.0 + g.ph) * 0.5
		g.l.rotation.z = f; g.r.rotation.z = -f
	if rise != null and rise_t >= 0.0:
		rise_t += dt
		var u := clampf(rise_t / 0.6, 0.0, 1.0)
		# ease-out-back: rises from the water, overshoots a touch, settles
		var c1 := 1.9
		var e := 1.0 + (c1 + 1.0) * pow(u - 1.0, 3) + c1 * pow(u - 1.0, 2)
		rise.position.y = -0.9 * (1.0 - e)
		if u >= 1.0: rise.position.y = 0.0; rise_t = -1.0
	for i in range(drops.size() - 1, -1, -1):
		var d: Dictionary = drops[i]
		d.t += dt; d.v.y -= 9.0 * dt
		d.m.position += d.v * dt
		d.m.material_override.albedo_color.a = maxf(0.0, 1.0 - d.t / 0.7)
		if d.t > 0.7 or d.m.position.y < -0.1:
			d.m.queue_free(); drops.remove_at(i)
	for i in range(ripples.size() - 1, -1, -1):
		var r: Dictionary = ripples[i]
		r.t += dt
		var s: float = 0.2 + r.t * 1.6
		r.m.scale = Vector3(s, 0.01, s)
		r.m.material_override.albedo_color.a = maxf(0.0, 0.8 - r.t * 1.2)
		if r.t > 0.7:
			r.m.queue_free(); ripples.remove_at(i)
	if toast_t > 0:
		toast_t -= dt
		if toast_t <= 0: toast.modulate.a = 0.0

# ---------------------------------------------------------------- ui
func _ui() -> void:
	var layer := CanvasLayer.new(); add_child(layer)
	var root := Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var pal := VBoxContainer.new()
	pal.add_theme_constant_override("separation", 7)
	pal.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	pal.position = Vector2(12, 0); pal.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(pal)
	for i in PALETTE.size():
		var b := Button.new(); b.custom_minimum_size = Vector2(24, 24); b.focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new(); sb.bg_color = Color(PALETTE[i]); sb.set_corner_radius_all(7)
			sb.shadow_color = Color(0, 0.12, 0.16, 0.35); sb.shadow_size = 2; sb.shadow_offset = Vector2(0, 1)
			b.add_theme_stylebox_override(st, sb)
		b.pivot_offset = Vector2(12, 12)
		b.pressed.connect(func(): _set_color(i))
		pal.add_child(b); pal_buttons.append(b)
	_set_color(0)
	var tools := HBoxContainer.new(); tools.add_theme_constant_override("separation", 10)
	tools.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	tools.grow_horizontal = Control.GROW_DIRECTION_BEGIN; tools.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tools.offset_right = -14; tools.offset_bottom = -16
	root.add_child(tools)
	var mk := func(icon: String) -> Button:
		var b := IconButton.new(); b.icon_name = icon; b.custom_minimum_size = Vector2(44, 44); b.focus_mode = Control.FOCUS_NONE
		tools.add_child(b); return b
	var undo: Button = mk.call("undo")
	undo.pressed.connect(func():
		if undo_stack.is_empty(): return
		blocks = undo_stack.pop_back(); rebuild(); _save(); _tone(0, true))
	erase_btn = mk.call("erase")
	erase_btn.pressed.connect(func(): _set_erase(not erase))
	var share: Button = mk.call("share")
	share.pressed.connect(_share)
	title = Label.new(); title.text = "T I D E M I L L"; title.position = Vector2(14, 14)
	title.add_theme_font_size_override("font_size", 11); title.modulate.a = 0.75
	root.add_child(title)
	hint = Label.new(); hint.text = "Tap the sea to raise land · tap again to build up · drag to turn"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE); hint.offset_top = -120; hint.offset_bottom = -76
	hint.offset_left = 20; hint.offset_right = -20; hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_shadow_color", Color(0, 0.16, 0.2, 0.4)); hint.modulate.a = 0.85
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint)
	toast = Label.new(); toast.set_anchors_preset(Control.PRESET_CENTER_TOP); toast.offset_top = 18
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var tsb := StyleBoxFlat.new(); tsb.bg_color = Color(1, 1, 1, 0.92); tsb.set_corner_radius_all(16); tsb.content_margin_left = 14; tsb.content_margin_right = 14; tsb.content_margin_top = 8; tsb.content_margin_bottom = 8
	toast.add_theme_stylebox_override("normal", tsb); toast.add_theme_color_override("font_color", Color("#2f6c73"))
	toast.modulate.a = 0.0
	root.add_child(toast)
	get_tree().create_timer(5.0).timeout.connect(func(): create_tween().tween_property(title, "modulate:a", 0.0, 1.2))

func _set_color(i: int) -> void:
	color = i
	_set_erase(false)
	for j in pal_buttons.size():
		var b: Button = pal_buttons[j]
		b.scale = Vector2.ONE * (1.22 if j == i else 1.0)
		for st in ["normal", "hover", "pressed"]:
			var sb: StyleBoxFlat = b.get_theme_stylebox(st)
			sb.border_color = Color.WHITE; sb.set_border_width_all(2 if j == i else 0)

func _set_erase(v: bool) -> void:
	erase = v
	if erase_btn: (erase_btn as IconButton).on = v; erase_btn.queue_redraw()

func _say(s: String) -> void:
	toast.text = s; toast.modulate.a = 1.0; toast_t = 1.8

func _hide_hint() -> void:
	if hint_gone: return
	hint_gone = true
	var tw := create_tween(); tw.tween_property(hint, "modulate:a", 0.0, 1.0)
	create_tween().tween_property(title, "modulate:a", 0.0, 1.0)

class IconButton extends Button:
	var icon_name := ""
	var on := false
	func _init() -> void:
		flat = true
	func _draw() -> void:
		var bg := Color(1, 1, 1, 1) if on else Color(1, 1, 1, 0.16)
		draw_circle(size / 2, 22, bg)
		var fg := Color("#2f6c73") if on else Color.WHITE
		var o := size / 2 - Vector2(10, 10)
		var s := 20.0 / 24.0
		var L := func(pts: Array) -> void:
			var pp := PackedVector2Array()
			for p in pts: pp.append(o + (p as Vector2) * s)
			draw_polyline(pp, fg, 1.8, true)
		if icon_name == "undo":
			L.call([Vector2(9, 14), Vector2(4, 9), Vector2(9, 4)])
			var arc := [Vector2(4, 9), Vector2(14, 9)]
			for i in range(0, 13):
				var a := -PI / 2 + PI * i / 12.0
				arc.append(Vector2(14, 15) + Vector2(cos(a), sin(a)) * 6)
			arc.append(Vector2(11, 21))
			L.call(arc)
		elif icon_name == "erase":
			L.call([Vector2(20, 20), Vector2(9, 20), Vector2(4, 15), Vector2(3.6, 12.6), Vector2(4, 12), Vector2(13, 3), Vector2(16, 3), Vector2(20, 7), Vector2(20.4, 9.4), Vector2(20, 10), Vector2(11, 19)])
			L.call([Vector2(8, 9), Vector2(15, 16)])
		else:
			L.call([Vector2(12, 3), Vector2(12, 16)])
			L.call([Vector2(7, 8), Vector2(12, 3), Vector2(17, 8)])
			L.call([Vector2(5, 14), Vector2(5, 19), Vector2(7, 21), Vector2(17, 21), Vector2(19, 19), Vector2(19, 14)])

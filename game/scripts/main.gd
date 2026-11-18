extends Node2D

# پازل بلوکی ۸×۸. قطعه را از ردیف پایین بگیر و روی تخته بکش.

const N := 8
const CELL := 60.0
const HAND_CELL := 40.0
const LIFT := 110.0          # فاصله‌ی قطعه‌ی در حال کشیدن از انگشت، تا دیده شود

const COLORS := [
	Color("#ff6ad5"), Color("#6bd6ff"), Color("#ffd166"),
	Color("#9ff0c9"), Color("#7b5cff"),
]

const SHAPES := [
	[Vector2i(0, 0)],
	[Vector2i(0, 0), Vector2i(1, 0)],
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
	[Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)],
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)],
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)],
]

var board_origin := Vector2((720 - N * CELL) / 2.0, 280)
var board: Array = []          # 0 = خالی، عدد بالاتر = شماره‌ی رنگ + 1
var hand: Array = []           # Dictionary {cells, color} یا null
var drag := -1                 # اندیس قطعه‌ای که در حال کشیدن است
var drag_pos := Vector2.ZERO
var tap_candidate := false     # برای لمس بالای صفحه (ورود)
var score := 0
var game_over := false
var account_balance := -1
var flashes: Array = []        # جلوه‌ی پاک شدن ردیف
var time := 0.0


func _ready() -> void:
	randomize()
	new_game()
	_handle_launch_uri()


func new_game() -> void:
	board = []
	board.resize(N * N)
	board.fill(0)
	hand = _new_hand()
	drag = -1
	score = 0
	game_over = false
	flashes = []
	queue_redraw()


func _new_hand() -> Array:
	var h := []
	for i in 3:
		h.append({
			"cells": SHAPES[randi() % SHAPES.size()],
			"color": randi() % COLORS.size(),
		})
	return h


func cell_pos(c: int, r: int) -> Vector2:
	return board_origin + Vector2(c, r) * CELL


func slot_rect(i: int) -> Rect2:
	return Rect2(Vector2(60 + i * 200, 900), Vector2(180, 180))


func _process(delta: float) -> void:
	time += delta
	for fl in flashes:
		fl["t"] += delta
	flashes = flashes.filter(func(fl): return fl["t"] < 0.5)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press(event.position)
		else:
			_release(event.position)
	elif event is InputEventMouseMotion and drag >= 0:
		drag_pos = event.position
		tap_candidate = false


func _press(p: Vector2) -> void:
	if game_over:
		new_game()
		return
	for i in hand.size():
		if hand[i] != null and slot_rect(i).has_point(p):
			drag = i
			drag_pos = p
			tap_candidate = false
			return
	tap_candidate = p.y < 240 and Api.token == ""


func _release(p: Vector2) -> void:
	if drag >= 0:
		var i := drag
		drag = -1
		var piece: Dictionary = hand[i]
		var c := _target_cell(i, p)
		if _can_place(piece.cells, c):
			_place(i, c)
		queue_redraw()
		return
	if tap_candidate:
		tap_candidate = false
		OS.shell_open(Api.BASE + "launch")


func _place(i: int, c: Vector2i) -> void:
	var piece: Dictionary = hand[i]
	for v in piece.cells:
		board[(c.y + v.y) * N + (c.x + v.x)] = piece.color + 1
	score += piece.cells.size()
	hand[i] = null

	_clear_lines()

	if hand.all(func(x): return x == null):
		hand = _new_hand()
	if not _any_move_left():
		game_over = true
		Save.set_best(score)


# موقعیت گوشه‌ی بالا-چپ قطعه‌ی در حال کشیدن (کمی بالاتر از انگشت)
func _ghost_tl(i: int, p: Vector2) -> Vector2:
	var sz := _piece_size(hand[i].cells)
	return p - Vector2(sz) * CELL * 0.5 - Vector2(0, LIFT)


# خانه‌ای از تخته که قطعه‌ی در حال کشیدن روی آن قرار می‌گیرد
func _target_cell(i: int, p: Vector2) -> Vector2i:
	var local := (_ghost_tl(i, p) - board_origin) / CELL
	return Vector2i(roundi(local.x), roundi(local.y))


func _piece_size(cells: Array) -> Vector2i:
	var mx := 0
	var my := 0
	for v in cells:
		mx = maxi(mx, v.x)
		my = maxi(my, v.y)
	return Vector2i(mx + 1, my + 1)


func _can_place(cells: Array, c: Vector2i) -> bool:
	for v in cells:
		var x: int = c.x + v.x
		var y: int = c.y + v.y
		if x < 0 or y < 0 or x >= N or y >= N:
			return false
		if board[y * N + x] != 0:
			return false
	return true


func _any_move_left() -> bool:
	for piece in hand:
		if piece == null:
			continue
		for r in N:
			for c in N:
				if _can_place(piece.cells, Vector2i(c, r)):
					return true
	return false


func _clear_lines() -> void:
	var clear := {}
	var lines := 0
	for r in N:
		if range(N).all(func(c): return board[r * N + c] != 0):
			lines += 1
			for c in N:
				clear[r * N + c] = true
	for c in N:
		if range(N).all(func(r): return board[r * N + c] != 0):
			lines += 1
			for r in N:
				clear[r * N + c] = true
	for idx in clear:
		flashes.append({
			"pos": cell_pos(idx % N, idx / N) + Vector2(CELL / 2, CELL / 2),
			"color": COLORS[board[idx] - 1],
			"t": 0.0,
		})
		board[idx] = 0
	if lines > 0:
		score += lines * 10
		Save.add_coins(lines)


# ---------- نقاشی ----------

func _with_alpha(col: Color, a: float) -> Color:
	var c := col
	c.a *= a
	return c


# بلوک دوبعدی با سایه، برجستگی بالایی و لبه‌ی تیره تا عمق داشته باشد
func _draw_block(pos: Vector2, size: float, col: Color, alpha := 1.0) -> void:
	var s := size * 0.9
	var p := pos + Vector2((size - s) / 2, (size - s) / 2)
	draw_rect(Rect2(p + Vector2(0, 5), Vector2(s, s)), _with_alpha(Color.BLACK, 0.35 * alpha))
	draw_rect(Rect2(p, Vector2(s, s)), _with_alpha(col, alpha))
	draw_rect(Rect2(p, Vector2(s, s * 0.2)), _with_alpha(Color.WHITE, 0.28 * alpha))
	draw_rect(Rect2(p + Vector2(0, s * 0.8), Vector2(s, s * 0.2)), _with_alpha(Color.BLACK, 0.2 * alpha))


func _draw_background(vp: Vector2) -> void:
	var top := Color("#1b0f3a")
	var bot := Color("#070311")
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(vp.x, 0), vp, Vector2(0, vp.y)]),
		PackedColorArray([top, top, bot, bot]))
	draw_circle(Vector2(vp.x * 0.2, 180), 220, Color(1, 0.42, 0.84, 0.08))
	draw_circle(Vector2(vp.x * 0.85, 1000), 260, Color(0.42, 0.36, 1, 0.08))


func _draw() -> void:
	var vp := get_viewport_rect().size
	_draw_background(vp)
	var f := ThemeDB.fallback_font

	draw_string(f, Vector2(0, 130), "Cheeno", HORIZONTAL_ALIGNMENT_CENTER, 720, 56, Color.WHITE)
	var info := "امتیاز: %d    سکه: %d    رکورد: %d" % [score, Save.get_coins(), Save.best_score]
	draw_string(f, Vector2(0, 200), info, HORIZONTAL_ALIGNMENT_CENTER, 720, 30, Color("#d9d0ff"))
	var acc := "برای ورود به حساب، اینجا لمس کن" if Api.token == "" else "سکه‌ی حساب: %d" % account_balance
	draw_string(f, Vector2(0, 240), acc, HORIZONTAL_ALIGNMENT_CENTER, 720, 24, Color("#ffd166"))

	# قاب تخته
	var frame := Rect2(board_origin - Vector2(14, 14), Vector2(N * CELL + 28, N * CELL + 28))
	draw_rect(Rect2(frame.position + Vector2(0, 10), frame.size), Color(0, 0, 0, 0.45))
	draw_rect(frame, Color("#1a1036"))
	draw_rect(frame, Color("#4b3a8a"), false, 2.0)

	# خانه‌ها
	for r in N:
		for c in N:
			var v: int = board[r * N + c]
			var col: Color = Color("#2a1f4f") if v == 0 else COLORS[v - 1]
			_draw_block(cell_pos(c, r), CELL, col)

	# پیش‌نمایش جای قطعه و قطعه‌ی در حال کشیدن
	if drag >= 0:
		var piece: Dictionary = hand[drag]
		var col: Color = COLORS[piece.color]
		var target := _target_cell(drag, drag_pos)
		if _can_place(piece.cells, target):
			for v in piece.cells:
				_draw_block(cell_pos(target.x + v.x, target.y + v.y), CELL, col, 0.35)
		var tl := _ghost_tl(drag, drag_pos)
		for v in piece.cells:
			_draw_block(tl + Vector2(v) * CELL, CELL, col)

	# قطعه‌های ردیف پایین
	for i in hand.size():
		var rect := slot_rect(i)
		draw_rect(Rect2(rect.position + Vector2(0, 6), rect.size), Color(0, 0, 0, 0.3))
		draw_rect(rect, Color("#140d2b"))
		draw_rect(rect, Color("#3c2a6e"), false, 2.0)
		var piece = hand[i]
		if piece == null or i == drag:
			continue
		var sz := _piece_size(piece.cells)
		var origin := rect.position + (rect.size - Vector2(sz) * HAND_CELL) / 2
		for v in piece.cells:
			_draw_block(origin + Vector2(v) * HAND_CELL, HAND_CELL, COLORS[piece.color])

	# جلوه‌ی پاک شدن ردیف
	for fl in flashes:
		var k: float = fl["t"] / 0.5
		draw_arc(fl["pos"], 20.0 + k * 90.0, 0, TAU, 32, _with_alpha(fl["color"], 1.0 - k), 4.0)

	draw_string(f, Vector2(0, 1160), "قطعه را بگیر و روی جای خالی تخته رها کن", HORIZONTAL_ALIGNMENT_CENTER, 720, 24, Color("#8c7fb3"))

	if game_over:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.7))
		draw_string(f, Vector2(0, 600), "بازی تمام شد", HORIZONTAL_ALIGNMENT_CENTER, 720, 52, Color.WHITE)
		draw_string(f, Vector2(0, 660), "برای شروع دوباره لمس کن", HORIZONTAL_ALIGNMENT_CENTER, 720, 28, Color("#d9d0ff"))


func _handle_launch_uri() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("cheeno://auth"):
			var code := arg.get_slice("code=", 1).get_slice("&", 0).uri_decode()
			var r: Dictionary = await Api.login(code)
			if r.ok:
				account_balance = int(r.data.get("balance", 0))
				queue_redraw()
			return

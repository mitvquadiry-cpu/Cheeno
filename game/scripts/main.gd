extends Node2D

# پازل بلوکی ۸×۸. کنترل نسخه‌ی اول: قطعه را لمس کن، بعد خانه‌ای از صفحه را لمس کن.

const N := 8
const CELL := 60.0
const HAND_CELL := 36.0

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
var selected := -1
var score := 0
var game_over := false
var account_balance := -1


func _ready() -> void:
	randomize()
	new_game()
	_handle_launch_uri()


func new_game() -> void:
	board = []
	board.resize(N * N)
	board.fill(0)
	hand = _new_hand()
	selected = -1
	score = 0
	game_over = false
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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_tap(event.position)


func _on_tap(p: Vector2) -> void:
	if game_over:
		new_game()
		return

	if p.y < 240 and Api.token == "":
		OS.shell_open(Api.BASE + "launch")
		return

	for i in hand.size():
		if hand[i] != null and slot_rect(i).has_point(p):
			selected = -1 if selected == i else i
			queue_redraw()
			return

	if selected < 0:
		return

	var local := (p - board_origin) / CELL
	var c := Vector2i(floori(local.x), floori(local.y))
	var piece: Dictionary = hand[selected]
	if not _can_place(piece.cells, c):
		return

	for v in piece.cells:
		board[(c.y + v.y) * N + (c.x + v.x)] = piece.color + 1
	score += piece.cells.size()
	hand[selected] = null
	selected = -1

	_clear_lines()

	if hand.all(func(x): return x == null):
		hand = _new_hand()
	if not _any_move_left():
		game_over = true
		Save.set_best(score)
	queue_redraw()


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
		board[idx] = 0
	if lines > 0:
		score += lines * 10
		Save.add_coins(lines)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color("#0b0718"))
	var f := ThemeDB.fallback_font

	draw_string(f, Vector2(0, 130), "Cheeno", HORIZONTAL_ALIGNMENT_CENTER, 720, 56, Color.WHITE)
	var info := "امتیاز: %d    سکه: %d    رکورد: %d" % [score, Save.get_coins(), Save.best_score]
	draw_string(f, Vector2(0, 200), info, HORIZONTAL_ALIGNMENT_CENTER, 720, 30, Color("#d9d0ff"))
	var acc := "برای ورود به حساب، اینجا لمس کن" if Api.token == "" else "سکه‌ی حساب: %d" % account_balance
	draw_string(f, Vector2(0, 240), acc, HORIZONTAL_ALIGNMENT_CENTER, 720, 24, Color("#ffd166"))

	draw_rect(Rect2(board_origin - Vector2(8, 8), Vector2(N * CELL + 16, N * CELL + 16)), Color("#1a1036"))
	for r in N:
		for c in N:
			var v: int = board[r * N + c]
			var col: Color = Color("#241a40") if v == 0 else COLORS[v - 1]
			draw_rect(Rect2(cell_pos(c, r) + Vector2(3, 3), Vector2(CELL - 6, CELL - 6)), col)

	for i in hand.size():
		var piece = hand[i]
		if piece == null:
			continue
		var rect := slot_rect(i)
		var border := Color("#ffd166") if i == selected else Color("#3c2a6e")
		draw_rect(rect, border, false, 3.0)
		for v in piece.cells:
			var pos: Vector2 = rect.position + Vector2(30, 50) + Vector2(v) * HAND_CELL
			draw_rect(Rect2(pos, Vector2(HAND_CELL - 4, HAND_CELL - 4)), COLORS[piece.color])

	draw_string(f, Vector2(0, 1160), "قطعه را انتخاب کن، سپس خانه‌ای از صفحه را لمس کن", HORIZONTAL_ALIGNMENT_CENTER, 720, 24, Color("#8c7fb3"))

	if game_over:
		draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0, 0, 0, 0.7))
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

extends Node2D

# Cheeno: پازل بلوکی. تخته از ۶×۶ شروع می‌شود و تا ۱۰×۱۰ بزرگ می‌شود.

const MIN_N := 6
const MAX_N := 10
const BOARD_PX := 600.0
const LIFT := 110.0
const SCORE_PER_GROW := 30
const SCORE_PER_SHAPE := 10
const LINES_PER_COIN := 12       # هر ۱۲ ردیف پاک‌شده، ۱ سکه
const HINT_COST := 5
const SHUFFLE_COST := 5
const CONTINUE_COST := 10
const UNDO_COST := 3
const ROTATE_COST := 3
const PACKS := [
	{"id": "starter", "name": "بسته شروع (یک‌بار)", "coins": 1000, "price": 25000},
	{"id": "small", "name": "بسته کوچک", "coins": 500, "price": 50000},
	{"id": "medium", "name": "بسته معمولی", "coins": 1200, "price": 100000},
	{"id": "large", "name": "بسته بزرگ", "coins": 3500, "price": 250000},
	{"id": "mega", "name": "بسته ویژه", "coins": 8000, "price": 500000},
]
const UNDO_MOVES := 3

# شکل‌ها از آسان به سخت
const SHAPE_STR := [
	["#"], ["##"], ["###"], ["#", "#", "#"], ["##", "##"], ["#.", "#.", "##"],
	["####"], ["###", ".#."], ["#..", "###"], ["##", ".##"], [".##", "##."],
	["###", "#.#"], ["#", "#", "#", "#"], ["###", "###"], ["##", "#.", "#."],
	["###", "#..", "#.."], ["#####"], [".#.", "###", ".#."], ["###", "###", "###"],
	["##.", ".#.", ".##"], ["#.#", "###", "#.#"], ["####", "#..."], ["#.#", ".#.", "#.#"],
	["#####", "#...."], ["##.", "###", ".##"], ["#...#", "#####"],
]
const START_SHAPES := 6

const SKINS := [
	{"name": "کلاسیک", "cost": 0, "colors": ["#ff6ad5", "#6bd6ff", "#ffd166", "#9ff0c9", "#7b5cff"]},
	{"name": "اقیانوس", "cost": 30, "colors": ["#4cc9f0", "#4895ef", "#4361ee", "#3a0ca3", "#48cae4"]},
	{"name": "آبنبات", "cost": 60, "colors": ["#ff99c8", "#fcf6bd", "#d0f4de", "#a9def9", "#e4c1f9"]},
	{"name": "جنگل", "cost": 100, "colors": ["#95d5b2", "#52b788", "#2d6a4f", "#b7e4c7", "#d8f3dc"]},
	{"name": "آتش", "cost": 150, "colors": ["#ff4800", "#ff7b00", "#ffaa00", "#ffd000", "#d00000"]},
]
const AVATARS := ["#ff6ad5", "#6bd6ff", "#ffd166", "#9ff0c9", "#7b5cff", "#ff7b00"]

var shapes: Array = []
var n := MIN_N
var cell := BOARD_PX / MIN_N
var board_origin := Vector2(60, 260)
var board: Array = []
var hand: Array = []
var drag := -1
var drag_pos := Vector2.ZERO
var score := 0
var game_over := false
var flashes: Array = []
var history: Array = []
var hint := {}
var msg := ""
var time := 0.0
var panel := ""                  # "", skins, sound, profile
var reset_armed := 0.0
var busy := false
var account_name := ""
var account_best := 0
var account_balance := -1
var top_off := 0.0
var snd := {}
var rot_mode := false
var records: Array = []
var records_state := ""


func _ready() -> void:
	randomize()
	for s in SHAPE_STR:
		shapes.append(_parse(s))
	_make_sounds()
	_apply_audio()
	if not _load_game():
		new_game()
	_handle_launch_uri()
	if Api.token != "":
		refresh_profile()


func _parse(rows: Array) -> Array:
	var out := []
	for y in rows.size():
		for x in (rows[y] as String).length():
			if rows[y][x] == "#":
				out.append(Vector2i(x, y))
	return out


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game()


# ---------- وضعیت بازی ----------

func set_size(v: int) -> void:
	var old := board.duplicate()
	var on := n
	n = v
	cell = BOARD_PX / n
	board = []
	board.resize(n * n)
	board.fill(0)
	for r in mini(on, n):
		for c in mini(on, n):
			if old.size() == on * on:
				board[r * n + c] = old[r * on + c]


func new_game() -> void:
	n = MIN_N
	cell = BOARD_PX / n
	board = []
	board.resize(n * n)
	board.fill(0)
	score = 0
	game_over = false
	flashes = []
	history = []
	hint = {}
	hand = _new_hand()
	Save.game = {}
	Save.save()


func _snap() -> Dictionary:
	return {"n": n, "board": board.duplicate(), "hand": hand.duplicate(true), "score": score}


func _restore(s: Dictionary) -> void:
	n = int(s.n)
	cell = BOARD_PX / n
	board = (s.board as Array).duplicate()
	hand = (s.hand as Array).duplicate(true)
	score = int(s.score)
	game_over = false
	hint = {}
	drag = -1


func _save_game() -> void:
	if game_over:
		Save.game = {}
	else:
		Save.game = _snap()
	Save.save()


func _load_game() -> bool:
	var g: Dictionary = Save.game
	if g.is_empty() or not g.has("board") or not g.has("hand") or not g.has("n"):
		return false
	if int(g.n) < MIN_N or int(g.n) > MAX_N or (g.board as Array).size() != int(g.n) * int(g.n):
		return false
	_restore(g)
	return true


func _pool() -> Array:
	return shapes.slice(0, clampi(START_SHAPES + score / SCORE_PER_SHAPE, START_SHAPES, shapes.size()))


func _new_hand() -> Array:
	var h := []
	var pool := _pool()
	var cols: Array = SKINS[Save.skin].colors
	for i in 3:
		h.append({"cells": pool[randi() % pool.size()], "color": randi() % cols.size()})
	return h


func _col(i: int) -> Color:
	return Color((SKINS[Save.skin].colors as Array)[i % 5])


# ---------- مکان‌ها ----------

func cell_pos(c: int, r: int) -> Vector2:
	return board_origin + Vector2(c, r) * cell


func slot_rect(i: int) -> Rect2:
	return Rect2(Vector2(60 + i * 200, 895), Vector2(180, 180))


func top_btn(i: int) -> Rect2:
	return Rect2(Vector2(15 + i * 140, 10), Vector2(130, 50))


func hint_rect() -> Rect2:
	return Rect2(Vector2(60, 1090), Vector2(280, 56))


func shuffle_rect() -> Rect2:
	return Rect2(Vector2(380, 1090), Vector2(280, 56))


func undo_rect() -> Rect2:
	return Rect2(Vector2(60, 1156), Vector2(280, 56))


func rotate_rect() -> Rect2:
	return Rect2(Vector2(380, 1156), Vector2(280, 56))


func shop_rect() -> Rect2:
	return Rect2(Vector2(30, 92), Vector2(200, 56))


func records_rect() -> Rect2:
	return Rect2(Vector2(490, 92), Vector2(200, 56))


func pack_rect(i: int) -> Rect2:
	return Rect2(Vector2(70, 400 + i * 100), Vector2(580, 88))


func avatar_center() -> Vector2:
	return Vector2(360, 120)


func panel_rect() -> Rect2:
	return Rect2(Vector2(40, 280), Vector2(640, 720))


func close_rect() -> Rect2:
	return Rect2(Vector2(220, 920), Vector2(280, 56))


func cont_rect() -> Rect2:
	return Rect2(Vector2(110, 640), Vector2(500, 70))


func restart_rect() -> Rect2:
	return Rect2(Vector2(110, 730), Vector2(500, 70))


func skin_rect(i: int) -> Rect2:
	return Rect2(Vector2(70, 340 + i * 110), Vector2(580, 96))


# ---------- حلقه ----------

func _process(delta: float) -> void:
	time += delta
	for fl in flashes:
		fl["t"] += delta
	flashes = flashes.filter(func(fl): return fl["t"] < 0.5)
	queue_redraw()


func _unhandled_input(ev: InputEvent) -> void:
	if time < 1.5:
		return
	var event := ev.duplicate()
	if event is InputEventMouse:
		event.position.y -= top_off
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press(event.position)
		else:
			_release(event.position)
	elif event is InputEventMouseMotion:
		if drag >= 0:
			drag_pos = event.position
		elif panel == "sound" and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_slider(event.position)


func _slider_rect() -> Rect2:
	return Rect2(Vector2(100, 560), Vector2(520, 40))


func _slider(p: Vector2) -> void:
	var r := _slider_rect()
	if p.y > r.position.y - 30 and p.y < r.end.y + 30:
		Save.volume = clampf((p.x - r.position.x) / r.size.x, 0.0, 1.0)
		_apply_audio()


func _press(p: Vector2) -> void:
	if busy:
		return
	if panel != "":
		_press_panel(p)
		return
	if game_over:
		if cont_rect().has_point(p):
			_continue()
		elif restart_rect().has_point(p):
			new_game()
			_play("click")
		return
	for i in 5:
		if top_btn(i).has_point(p):
			_play("click")
			_top_action(i)
			return
	if p.distance_to(avatar_center()) < 50:
		panel = "profile"
		_play("click")
		return
	if shop_rect().has_point(p):
		panel = "shop"
		_play("click")
		return
	if records_rect().has_point(p):
		panel = "records"
		_play("click")
		_load_records()
		return
	if hint_rect().has_point(p):
		_use_hint()
		return
	if undo_rect().has_point(p):
		_undo()
		return
	if rotate_rect().has_point(p):
		rot_mode = not rot_mode
		msg = "کارتی را که می‌خواهی بچرخانی لمس کن (%d سکه)" % ROTATE_COST if rot_mode else ""
		_play("click")
		return
	if shuffle_rect().has_point(p):
		_shuffle()
		return
	msg = ""
	hint = {}
	for i in hand.size():
		if hand[i] != null and slot_rect(i).has_point(p):
			if rot_mode:
				rot_mode = false
				_rotate(i)
				return
			drag = i
			drag_pos = p
			_play("pick")
			return


func _release(p: Vector2) -> void:
	if drag < 0:
		return
	var i := drag
	drag = -1
	var piece: Dictionary = hand[i]
	var c := _target_cell(i, p)
	if _can_place(piece.cells, c):
		_place(i, c)


func _top_action(i: int) -> void:
	match i:
		0:
			_save_game()
			msg = "بازی ذخیره شد"
		1:
			if reset_armed > time:
				new_game()
				msg = "بازی تازه شروع شد"
				reset_armed = 0.0
			else:
				reset_armed = time + 3.0
				msg = "برای شروع از اول، دوباره «ریست» را لمس کن"
		2:
			panel = "skins"
		3:
			panel = "sound"
		4:
			_save_game()
			get_tree().quit()


func _press_panel(p: Vector2) -> void:
	_play("click")
	if panel == "login" and panel_rect().has_point(p) and not close_rect().has_point(p):
		_login_pad(p)
		if Rect2(Vector2(110, 500), Vector2(500, 64)).has_point(p):
			_login_step()
		return
	# لمس بیرون پنل یا غیر از دکمهٔ بستن، پنل را نمی‌بندد
	if close_rect().has_point(p):
		panel = ""
		_close_login_edit()
		Save.save()
		return
	if not panel_rect().has_point(p):
		return
	match panel:
		"skins":
			for i in SKINS.size():
				if skin_rect(i).has_point(p):
					_pick_skin(i)
		"sound":
			if Rect2(Vector2(100, 440), Vector2(520, 70)).has_point(p):
				Save.muted = not Save.muted
				_apply_audio()
			else:
				_slider(p)
		"shop":
			for i in PACKS.size():
				if pack_rect(i).has_point(p):
					_buy_pack(PACKS[i].id)
		"profile":
			for i in AVATARS.size():
				if Rect2(Vector2(70 + i * 95, 500), Vector2(80, 80)).has_point(p):
					Save.avatar = i
					if Api.token != "":
						Api.set_profile(i)
			if Api.token != "" and Rect2(Vector2(110, 735), Vector2(500, 64)).has_point(p):
				panel = "name"
				name_text = ""
				name_msg = ""
			if Rect2(Vector2(110, 640), Vector2(500, 70)).has_point(p):
				if Api.token == "":
					_open_login()
				else:
					Api.logout()
					account_name = ""
					account_balance = 0
		"login":
			_login_pad(p)
			if Rect2(Vector2(110, 500), Vector2(500, 64)).has_point(p):
				_login_step()
		"name":
			_name_pad(p)
			if Rect2(Vector2(110, 836), Vector2(500, 56)).has_point(p):
				_name_save()


var login_sent := false
var login_msg := ""
var login_busy := false
var login_text := ""
var login_phone := ""


func _open_login() -> void:
	panel = "login"
	login_sent = false
	login_msg = ""
	login_text = ""


func _close_login_edit() -> void:
	pass


func _login_pad(p: Vector2) -> void:
	var keys := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "حذف", "0", "پاک"]
	for i in keys.size():
		if _pad_rect(i).has_point(p):
			var k: String = keys[i]
			if k == "حذف":
				login_text = login_text.substr(0, login_text.length() - 1)
			elif k == "پاک":
				login_text = ""
			elif login_text.length() < 11:
				login_text += k


var name_text := ""
var name_msg := ""
var name_busy := false
const NAME_KEYS := ["ا","ب","پ","ت","ث","ج","چ","ح","خ","د","ذ","ر","ز","ژ","س","ش","ص","ض","ط","ظ","ع","غ","ف","ق","ک","گ","ل","م","ن","و","ه","ی","0","1","2","3","4","5","6","7","8","9","_","فاصله","حذف"]


func _name_key_rect(i: int) -> Rect2:
	return Rect2(45 + (i % 6) * 106, 430 + (i / 6) * 50, 100, 44)


func _name_pad(p: Vector2) -> void:
	for i in NAME_KEYS.size():
		if _name_key_rect(i).has_point(p):
			var k: String = NAME_KEYS[i]
			if k == "حذف":
				name_text = name_text.substr(0, name_text.length() - 1)
			elif k == "فاصله":
				if name_text.length() < 12 and not name_text.ends_with(" ") and name_text != "":
					name_text += " "
			elif name_text.length() < 12:
				name_text += k
			return


func _name_save() -> void:
	if name_busy:
		return
	var txt := name_text.strip_edges()
	if txt.length() < 2:
		name_msg = "نام باید حداقل ۲ حرف باشد"
		return
	name_busy = true
	name_msg = "در حال ذخیره…"
	var r: Dictionary = await Api.set_profile(Save.avatar, txt)
	if r.ok:
		account_name = txt
		name_msg = ""
		panel = "profile"
	elif r.code == 409:
		name_msg = "این نام قبلاً گرفته شده، نام دیگری انتخاب کن"
	else:
		name_msg = str(r.data.get("message", "ذخیره نشد؛ دوباره تلاش کن"))
	name_busy = false


func _pad_rect(i: int) -> Rect2:
	return Rect2(110 + (i % 3) * 170, 630 + (i / 3) * 66, 160, 56)


func _login_step() -> void:
	if login_busy:
		return
	login_busy = true
	var txt := login_text.strip_edges()
	if not login_sent:
		login_msg = "در حال ارسال…"
		var r: Dictionary = await Api.otp_send(txt)
		if r.ok:
			login_sent = true
			login_phone = txt
			login_text = ""
			login_msg = "کد ارسال شد"
		else:
			login_msg = str(r.data.get("message", "خطا در ارسال؛ اینترنت یا شماره را بررسی کن"))
	else:
		login_msg = "در حال بررسی…"
		var r2: Dictionary = await Api.otp_verify(login_phone, txt)
		if r2.ok:
			await refresh_profile()
			Api.set_profile(Save.avatar)
			panel = "profile"
		else:
			login_msg = str(r2.data.get("message", "خطا؛ دوباره تلاش کن"))
	login_busy = false


func _pick_skin(i: int) -> void:
	if Save.owned.has(i):
		Save.skin = i
		Save.save()
		return
	var cost: int = SKINS[i].cost
	if await _pay(cost, "skin_%d" % i):
		Save.owned.append(i)
		Save.skin = i
		Save.save()
		msg = "پوسته خریداری شد"
	else:
		_need_coins(cost)


# پرداخت: با حساب وارد‌شده از سرور، وگرنه از سکه‌ی محلی
func _pay(amount: int, reason: String) -> bool:
	if Api.token != "":
		busy = true
		var r: Dictionary = await Api.spend(amount, reason)
		busy = false
		if not r.ok:
			return false
		account_balance = int(r.data.get("balance", account_balance))
		return true
	return Save.spend_coins(amount)


func _need_coins(amount: int) -> void:
	msg = "سکه کافی نیست (%d سکه لازم است). می‌توانی سکه بخری." % amount
	panel = "shop"


func _undo() -> void:
	if game_over or history.is_empty():
		msg = "حرکتی برای برگشت نیست"
		return
	if not await _pay(UNDO_COST, "undo"):
		_need_coins(UNDO_COST)
		return
	_restore(history.pop_back())
	msg = "یک حرکت برگشت"
	_save_game()


func _rotate(i: int) -> void:
	if game_over or hand[i] == null:
		return
	if not await _pay(ROTATE_COST, "rotate"):
		_need_coins(ROTATE_COST)
		return
	var cells: Array = hand[i].cells
	var my := 0
	for v in cells:
		my = maxi(my, v.y)
	var out := []
	for v in cells:
		out.append(Vector2i(my - v.y, v.x))
	hand[i].cells = out
	hint = {}
	_play("pick")
	if not _any_move_left():
		game_over = true
	_save_game()


func _buy_pack(id: String) -> void:
	if Api.token == "":
		msg = "برای خرید اول ثبت‌نام/ورود کن (شماره موبایل)"
		panel = "login"
		return
	busy = true
	var r: Dictionary = await Api.create_order(id)
	busy = false
	if r.ok and str(r.data.get("payment_url", "")) != "":
		OS.shell_open(str(r.data.payment_url))
		msg = "بعد از پرداخت به بازی برگرد؛ سکه‌ها خودکار اضافه می‌شوند"
		panel = ""
	else:
		msg = str(r.data.get("message", "خطا در ساخت سفارش"))


func _load_records() -> void:
	records_state = "loading"
	var r: Dictionary = await Api.leaderboard()
	if r.ok and r.data.get("items") is Array:
		records = r.data.items
		records_state = "ok"
	else:
		records_state = "error"


func _coins() -> int:
	return Save.get_coins() if Api.token == "" else account_balance


# ---------- منطق ----------

func _place(i: int, c: Vector2i) -> void:
	hint = {}
	history.append(_snap())
	if history.size() > UNDO_MOVES:
		history.pop_front()
	var piece: Dictionary = hand[i]
	for v in piece.cells:
		board[(c.y + v.y) * n + (c.x + v.x)] = piece.color + 1
	hand[i] = null
	_play("place")
	_clear_lines()

	var want := clampi(MIN_N + score / SCORE_PER_GROW, MIN_N, MAX_N)
	if want > n:
		set_size(want)
		msg = "تخته بزرگ‌تر شد: %d×%d" % [n, n]
	if hand.all(func(x): return x == null):
		hand = _new_hand()
	if not _any_move_left():
		game_over = true
		Save.set_best(score)
		if Api.token != "":
			Api.submit_score(score)
		_play("over")
		Save.game = {}
		Save.save()
	else:
		_save_game()


func _continue() -> void:
	if history.is_empty():
		msg = "حرکتی برای برگشت نیست"
		return
	if not await _pay(CONTINUE_COST, "continue"):
		_need_coins(CONTINUE_COST)
		return
	_restore(history[0])
	history = []
	msg = "سه حرکت برگشتی؛ ادامه بده"
	_save_game()


func _shuffle() -> void:
	if game_over:
		return
	if not await _pay(SHUFFLE_COST, "shuffle"):
		_need_coins(SHUFFLE_COST)
		return
	hand = _new_hand()
	hint = {}
	_play("pick")
	if not _any_move_left():
		game_over = true
	_save_game()


func _ghost_tl(i: int, p: Vector2) -> Vector2:
	var sz := _piece_size(hand[i].cells)
	return p - Vector2(sz) * cell * 0.5 - Vector2(0, LIFT)


func _target_cell(i: int, p: Vector2) -> Vector2i:
	var local := (_ghost_tl(i, p) - board_origin) / cell
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
		if x < 0 or y < 0 or x >= n or y >= n:
			return false
		if board[y * n + x] != 0:
			return false
	return true


func _any_move_left() -> bool:
	for piece in hand:
		if piece == null:
			continue
		for r in n:
			for c in n:
				if _can_place(piece.cells, Vector2i(c, r)):
					return true
	return false


func _clear_lines() -> void:
	var clear := {}
	var lines := 0
	for r in n:
		if range(n).all(func(c): return board[r * n + c] != 0):
			lines += 1
			for c in n:
				clear[r * n + c] = true
	for c in n:
		if range(n).all(func(r): return board[r * n + c] != 0):
			lines += 1
			for r in n:
				clear[r * n + c] = true
	for idx in clear:
		flashes.append({
			"pos": cell_pos(idx % n, idx / n) + Vector2(cell / 2, cell / 2),
			"color": _col(board[idx] - 1),
			"t": 0.0,
		})
		board[idx] = 0
	if lines > 0:
		score += lines
		_play("clear")
		# سکه خیلی آهسته؛ فقط برای حساب محلی (حساب سرور فقط با خرید شارژ می‌شود)
		Save.line_acc += lines
		while Save.line_acc >= LINES_PER_COIN:
			Save.line_acc -= LINES_PER_COIN
			if Api.token == "":
				Save.coins += 1
		Save.save()


func _find_hint() -> Dictionary:
	for i in hand.size():
		if hand[i] == null:
			continue
		for r in n:
			for c in n:
				if _can_place(hand[i].cells, Vector2i(c, r)):
					return {"slot": i, "cell": Vector2i(c, r)}
	return {}


func _use_hint() -> void:
	if game_over or not hint.is_empty():
		return
	var found := _find_hint()
	if found.is_empty():
		msg = "جای قانونی‌ای پیدا نشد"
		return
	if not await _pay(HINT_COST, "hint"):
		_need_coins(HINT_COST)
		return
	hint = found
	msg = "قطعه‌ی روشن‌شده را روی خانه‌ی روشن بگذار"


func refresh_profile() -> void:
	var r: Dictionary = await Api.balance()
	if r.ok:
		account_balance = int(r.data.get("balance", 0))
		account_name = str(r.data.get("name", ""))
		account_best = int(r.data.get("best", 0))


func _handle_launch_uri() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("cheeno://auth"):
			var code := arg.get_slice("code=", 1).get_slice("&", 0).uri_decode()
			var r: Dictionary = await Api.login(code)
			if r.ok:
				await refresh_profile()
			return


# ---------- صدا (ساخته‌شده با کد) ----------

func _wave(notes: Array, dur: float, vol: float, sweep := 0.0) -> AudioStreamWAV:
	var rate := 22050
	var per := int(rate * dur)
	var bytes := PackedByteArray()
	bytes.resize(per * notes.size() * 2)
	var k := 0
	for f in notes:
		var ph := 0.0
		for i in per:
			var t := float(i) / per
			ph += TAU * (f * (1.0 + sweep * t)) / rate
			var env := pow(1.0 - t, 1.6) * minf(1.0, t * 40.0)
			var v := (sin(ph) * 0.8 + sin(ph * 2.0) * 0.2) * env * vol
			bytes.encode_s16(k * 2, int(clampf(v, -1.0, 1.0) * 32000))
			k += 1
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = bytes
	return w


func _make_sounds() -> void:
	var defs := {
		"place": _wave([330.0], 0.12, 0.7, -0.4),
		"pick": _wave([660.0], 0.05, 0.4),
		"click": _wave([880.0], 0.04, 0.35),
		"clear": _wave([523.0, 659.0, 784.0, 1047.0], 0.09, 0.6),
		"over": _wave([392.0, 330.0, 262.0], 0.22, 0.6),
	}
	for k in defs:
		var p := AudioStreamPlayer.new()
		p.stream = defs[k]
		add_child(p)
		snd[k] = p


func _play(name: String) -> void:
	if snd.has(name) and not Save.muted:
		snd[name].play()


func _apply_audio() -> void:
	AudioServer.set_bus_mute(0, Save.muted)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(Save.volume, 0.0001)))


# ---------- نقاشی ----------

func _with_alpha(col: Color, a: float) -> Color:
	var c := col
	c.a *= a
	return c


func _draw_block(pos: Vector2, size: float, col: Color, alpha := 1.0) -> void:
	var s := size * 0.9
	var p := pos + Vector2((size - s) / 2, (size - s) / 2)
	draw_rect(Rect2(p + Vector2(0, 4), Vector2(s, s)), _with_alpha(Color.BLACK, 0.35 * alpha))
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


func _btn(r: Rect2, text: String, fill := Color("#140d2b"), fs := 24, tc := Color.WHITE) -> void:
	var f := ThemeDB.fallback_font
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(minf(r.size.y * 0.3, 22.0)))
	sb.border_color = Color("#7b5cff")
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	draw_style_box(sb, r)
	draw_string(f, Vector2(r.position.x, r.position.y + r.size.y / 2 + fs * 0.35), text,
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, tc)


func _draw_avatar(c: Vector2, r: float) -> void:
	draw_circle(c, r + 4, Color("#ffd166"))
	draw_circle(c, r, Color(AVATARS[Save.avatar]))
	draw_circle(c + Vector2(0, -r * 0.2), r * 0.32, Color(1, 1, 1, 0.85))
	draw_circle(c + Vector2(0, r * 0.75), r * 0.55, Color(1, 1, 1, 0.85))


func _draw() -> void:
	var vp := get_viewport_rect().size
	var f := ThemeDB.fallback_font
	if time < 1.5:
		draw_rect(Rect2(Vector2.ZERO, vp), Color.BLACK)
		draw_string(f, Vector2(0, 600), "Cheeno", HORIZONTAL_ALIGNMENT_CENTER, 720, 72, Color.WHITE)
		draw_string(f, Vector2(0, 680), "در حال بارگذاری...", HORIZONTAL_ALIGNMENT_CENTER, 720, 28, Color("#d9d0ff"))
		draw_rect(Rect2(Vector2(160, 720), Vector2(400, 10)), Color("#2a1f4f"))
		draw_rect(Rect2(Vector2(160, 720), Vector2(400 * clampf(time / 1.5, 0, 1), 10)), Color("#ff6ad5"))
		return
	_draw_background(vp)
	top_off = clampf((vp.y - 1280.0) * 0.5, 0.0, 90.0)
	draw_set_transform(Vector2(0, top_off))

	var labels := ["ذخیره", "ریست", "پوسته", "صدا", "خروج"]
	for i in 5:
		var lb: String = labels[i]
		if i == 3 and Save.muted:
			lb = "بی‌صدا"
		_btn(top_btn(i), lb, Color("#140d2b"), 22)

	_draw_avatar(avatar_center(), 38)
	var nm := "مهمان (لمس کن)" if Api.token == "" else account_name
	draw_string(f, Vector2(0, 195), nm, HORIZONTAL_ALIGNMENT_CENTER, 720, 24, Color("#ffd166"))
	var info := "امتیاز: %d    سکه: %d    رکورد: %d" % [score, _coins(), maxi(Save.best_score, account_best)]
	draw_string(f, Vector2(0, 232), info, HORIZONTAL_ALIGNMENT_CENTER, 720, 26, Color("#d9d0ff"))

	var side := n * cell
	var frame := Rect2(board_origin - Vector2(14, 14), Vector2(side + 28, side + 28))
	draw_rect(Rect2(frame.position + Vector2(0, 10), frame.size), Color(0, 0, 0, 0.45))
	draw_rect(frame, Color("#1a1036"))
	draw_rect(frame, Color("#4b3a8a"), false, 2.0)
	for r in n:
		for c in n:
			var v: int = board[r * n + c]
			_draw_block(cell_pos(c, r), cell, Color("#2a1f4f") if v == 0 else _col(v - 1))

	for i in hand.size():
		var rect := slot_rect(i)
		draw_rect(Rect2(rect.position + Vector2(0, 6), rect.size), Color(0, 0, 0, 0.3))
		draw_rect(rect, Color("#140d2b"))
		draw_rect(rect, Color("#3c2a6e"), false, 2.0)
		var piece = hand[i]
		if piece == null or i == drag:
			continue
		var sz := _piece_size(piece.cells)
		var hc := minf(40.0, 160.0 / maxi(sz.x, sz.y))
		var origin := rect.position + (rect.size - Vector2(sz) * hc) / 2
		for v in piece.cells:
			_draw_block(origin + Vector2(v) * hc, hc, _col(piece.color))

	if drag >= 0:
		var piece: Dictionary = hand[drag]
		var col := _col(piece.color)
		var target := _target_cell(drag, drag_pos)
		if _can_place(piece.cells, target):
			for v in piece.cells:
				_draw_block(cell_pos(target.x + v.x, target.y + v.y), cell, col, 0.35)
		var tl := _ghost_tl(drag, drag_pos)
		for v in piece.cells:
			_draw_block(tl + Vector2(v) * cell, cell, col)

	for fl in flashes:
		var k: float = fl["t"] / 0.5
		draw_arc(fl["pos"], 20.0 + k * 90.0, 0, TAU, 32, _with_alpha(fl["color"], 1.0 - k), 4.0)

	if not hint.is_empty():
		var pulse := 0.5 + 0.5 * sin(time * 6.0)
		var hc2 := Color(1, 0.84, 0.4, pulse)
		draw_rect(slot_rect(hint.slot), hc2, false, 4.0)
		for v in hand[hint.slot].cells:
			var cp: Vector2i = hint.cell + v
			draw_rect(Rect2(cell_pos(cp.x, cp.y), Vector2(cell, cell)), hc2, false, 4.0)

	_btn(hint_rect(), "راهنما: %d سکه" % HINT_COST, Color("#140d2b"), 26)
	_btn(shuffle_rect(), "عوض کارت‌ها: %d سکه" % SHUFFLE_COST, Color("#140d2b"), 24)
	_btn(undo_rect(), "برگشت حرکت: %d سکه" % UNDO_COST, Color("#140d2b"), 24)
	_btn(rotate_rect(), "چرخش کارت: %d سکه" % ROTATE_COST, Color("#3a2a7a") if rot_mode else Color("#140d2b"), 24)
	_btn(shop_rect(), "خرید سکه", Color("#3a2a7a"), 22)
	_btn(records_rect(), "رکوردها", Color("#140d2b"), 22)

	if msg != "":
		draw_string(f, Vector2(0, 1252), msg, HORIZONTAL_ALIGNMENT_CENTER, 720, 24, Color("#d9d0ff"))

	if game_over:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.75))
		draw_string(f, Vector2(0, 540), "بازی تمام شد", HORIZONTAL_ALIGNMENT_CENTER, 720, 52, Color.WHITE)
		draw_string(f, Vector2(0, 590), "امتیاز: %d" % score, HORIZONTAL_ALIGNMENT_CENTER, 720, 30, Color("#d9d0ff"))
		_btn(cont_rect(), "ادامه (۳ حرکت برگرد): %d سکه" % CONTINUE_COST, Color("#3a2a7a"), 26)
		_btn(restart_rect(), "شروع از اول", Color("#140d2b"), 26)

	if panel != "":
		_draw_panel(vp, f)


func _draw_panel(vp: Vector2, f: Font) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.75))
	var pr := panel_rect()
	draw_rect(pr, Color("#1a1036"))
	draw_rect(pr, Color("#4b3a8a"), false, 3.0)
	var title: String = {"skins": "پوسته‌ها", "sound": "صدا", "profile": "پروفایل", "login": "ورود", "shop": "خرید سکه", "records": "رکوردها"}[panel]
	draw_string(f, Vector2(0, 330), title, HORIZONTAL_ALIGNMENT_CENTER, 720, 40, Color.WHITE)
	draw_string(f, Vector2(0, 370 if panel != "skins" else 1000), "سکه: %d" % _coins() if panel != "login" and panel != "name" else "",
		HORIZONTAL_ALIGNMENT_CENTER, 720, 24, Color("#ffd166"))
	match panel:
		"skins":
			for i in SKINS.size():
				var r := skin_rect(i)
				var sel: bool = Save.skin == i
				draw_rect(r, Color("#3a2a7a") if sel else Color("#140d2b"))
				draw_rect(r, Color("#ffd166") if sel else Color("#3c2a6e"), false, 2.0)
				for j in 5:
					draw_rect(Rect2(r.position + Vector2(16 + j * 36, 24), Vector2(30, 48)), Color(SKINS[i].colors[j]))
				var st: String = "انتخاب‌شده" if sel else ("مال شماست" if Save.owned.has(i) else "%d سکه" % SKINS[i].cost)
				draw_string(f, Vector2(r.position.x + 210, r.position.y + 58), "%s  -  %s" % [SKINS[i].name, st],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
		"shop":
			for i in PACKS.size():
				var r := pack_rect(i)
				draw_rect(r, Color("#140d2b"))
				draw_rect(r, Color("#3c2a6e"), false, 2.0)
				draw_string(f, Vector2(r.position.x + 20, r.position.y + 38), "%s" % PACKS[i].name, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
				draw_string(f, Vector2(r.position.x + 20, r.position.y + 72), "%d سکه  -  %d تومان" % [PACKS[i].coins, PACKS[i].price], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#ffd166"))
		"records":
			if records_state != "ok":
				draw_string(f, Vector2(0, 560), "در حال بارگذاری..." if records_state == "loading" else "دریافت رکوردها ممکن نشد", HORIZONTAL_ALIGNMENT_CENTER, 720, 26, Color("#d9d0ff"))
			else:
				for i in mini(records.size(), 10):
					var it: Dictionary = records[i]
					var y := 420.0 + i * 48
					draw_string(f, Vector2(80, y), "%d" % int(it.get("rank", i + 1)), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("#ffd166"))
					draw_string(f, Vector2(150, y), str(it.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
					draw_string(f, Vector2(450, y), "%d" % int(it.get("score", 0)), HORIZONTAL_ALIGNMENT_RIGHT, 170, 26, Color("#d9d0ff"))
		"sound":
			_btn(Rect2(Vector2(100, 440), Vector2(520, 70)), "صدا: خاموش (لمس کن)" if Save.muted else "صدا: روشن (لمس کن)", Color("#140d2b"), 26)
			var s := _slider_rect()
			draw_string(f, Vector2(0, 545), "میزان صدا", HORIZONTAL_ALIGNMENT_CENTER, 720, 24, Color("#d9d0ff"))
			draw_rect(s, Color("#2a1f4f"))
			draw_rect(Rect2(s.position, Vector2(s.size.x * Save.volume, s.size.y)), Color("#ff6ad5"))
			draw_circle(Vector2(s.position.x + s.size.x * Save.volume, s.position.y + 20), 24, Color.WHITE)
		"profile":
			_draw_avatar(Vector2(360, 440), 50)
			draw_string(f, Vector2(0, 540 - 70), "", HORIZONTAL_ALIGNMENT_CENTER, 720, 10)
			for i in AVATARS.size():
				var c := Vector2(110 + i * 95, 540)
				draw_circle(c, 36, Color(AVATARS[i]))
				if Save.avatar == i:
					draw_arc(c, 42, 0, TAU, 32, Color.WHITE, 4.0)
			var nm := "مهمان" if Api.token == "" else account_name
			draw_string(f, Vector2(0, 610), nm, HORIZONTAL_ALIGNMENT_CENTER, 720, 28, Color.WHITE)
			_btn(Rect2(Vector2(110, 640), Vector2(500, 70)), "ورود / ثبت‌نام" if Api.token == "" else "خروج از حساب", Color("#3a2a7a"), 26)
			if Api.token != "":
				_btn(Rect2(Vector2(110, 735), Vector2(500, 64)), "تغییر نام", Color("#2a1f55"), 26)
		"name":
			draw_string(f, Vector2(0, 318), "اسم خودت را بنویس (۲ تا ۱۲ حرف)", HORIZONTAL_ALIGNMENT_CENTER, 720, 24, Color("#d9d0ff"))
			var nr := Rect2(110, 330, 500, 56)
			draw_rect(nr, Color("#f4f0ff"))
			draw_rect(nr, Color("#ff6ad5"), false, 3.0)
			draw_string(f, Vector2(nr.position.x, nr.position.y + 38), name_text if name_text != "" else "نام", HORIZONTAL_ALIGNMENT_CENTER, nr.size.x, 30, Color("#140d2b") if name_text != "" else Color("#8a80b8"))
			draw_string(f, Vector2(0, 408), name_msg, HORIZONTAL_ALIGNMENT_CENTER, 720, 20, Color("#ffd166"))
			for i in NAME_KEYS.size():
				_btn(_name_key_rect(i), NAME_KEYS[i], Color("#2a1f55"), 22)
			_btn(Rect2(Vector2(110, 836), Vector2(500, 56)), "ذخیرهٔ نام", Color("#3a2a7a"), 26)
		"login":
			draw_string(f, Vector2(0, 372), "شمارهٔ موبایل (مثل 09123456789)" if not login_sent else "کد پیامک‌شده را وارد کن", HORIZONTAL_ALIGNMENT_CENTER, 720, 24, Color("#d9d0ff"))
			var fr := Rect2(110, 404, 500, 72)
			draw_rect(fr, Color("#f4f0ff"))
			draw_rect(fr, Color("#ff6ad5"), false, 3.0)
			var shown := login_text if login_text != "" else ("09xxxxxxxxx" if not login_sent else "------")
			draw_string(f, Vector2(fr.position.x, fr.position.y + 48), shown, HORIZONTAL_ALIGNMENT_CENTER, fr.size.x, 36, Color("#140d2b") if login_text != "" else Color("#8a80b8"))
			_btn(Rect2(Vector2(110, 500), Vector2(500, 64)), "ارسال کد" if not login_sent else "تأیید و ورود", Color("#3a2a7a"), 26)
			draw_string(f, Vector2(0, 596), login_msg, HORIZONTAL_ALIGNMENT_CENTER, 720, 22, Color("#ffd166"))
			var pad := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "حذف", "0", "پاک"]
			for i in pad.size():
				_btn(_pad_rect(i), pad[i], Color("#2a1f55"), 30)
	_btn(close_rect(), "بستن", Color("#140d2b"), 26)

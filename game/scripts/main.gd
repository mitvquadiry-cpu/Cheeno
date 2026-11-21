extends Node2D

# Cheeno: پازل بلوکی. تخته از ۶×۶ شروع می‌شود و تا ۱۰×۱۰ بزرگ می‌شود.

const MIN_N := 6
const MAX_N := 10
const BOARD_PX := 600.0
const LIFT := 110.0
const SCORE_PER_GROW := 30
const SCORE_PER_SHAPE := 10
const LINES_PER_COIN := 12       # هر ۱۲ ردیف پاک‌شده، ۱ سکه
const HINT_COST := 3
const SHUFFLE_COST := 3
const CONTINUE_COST := 6
const UNDO_COST := 2
const ROTATE_COST := 2
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
const FX := [
	{"name": "موج", "cost": 0}, {"name": "جرقه", "cost": 40}, {"name": "ستاره", "cost": 70},
	{"name": "انفجار", "cost": 100}, {"name": "آتش‌بازی", "cost": 150},
]
const FRAMES := [
	{"name": "ساده", "cost": 0}, {"name": "طلایی دوخطه", "cost": 50}, {"name": "نئون نورانی", "cost": 80},
	{"name": "رنگین‌کمان", "cost": 120}, {"name": "سلطنتی", "cost": 180},
]
var store_tab := 0
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
var pressed_pos := Vector2(-1, -1)
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
		await refresh_profile()
	_daily_check()


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
	elif what == NOTIFICATION_APPLICATION_RESUMED and Api.token != "":
		refresh_profile()


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
	return Rect2(Vector2(40, 1100), Vector2(310, 68))


func shuffle_rect() -> Rect2:
	return Rect2(Vector2(370, 1100), Vector2(310, 68))


func undo_rect() -> Rect2:
	return Rect2(Vector2(40, 1186), Vector2(310, 68))


func rotate_rect() -> Rect2:
	return Rect2(Vector2(370, 1186), Vector2(310, 68))


func shop_rect() -> Rect2:
	return Rect2(Vector2(30, 92), Vector2(200, 56))


func records_rect() -> Rect2:
	return Rect2(Vector2(490, 92), Vector2(200, 56))


func pack_rect(i: int) -> Rect2:
	return Rect2(Vector2(70, 400 + i * 100), Vector2(580, 88))


func avatar_center() -> Vector2:
	return Vector2(360, 120)


func panel_rect() -> Rect2:
	if panel == "profile" or panel == "name":
		return Rect2(Vector2(40, 230), Vector2(640, 860))
	return Rect2(Vector2(40, 280), Vector2(640, 720))


func close_rect() -> Rect2:
	if panel == "profile" or panel == "name":
		return Rect2(Vector2(220, 1080), Vector2(280, 56))
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
	# وقتی چت باز است، هیچ لمس یا کلیدی نباید به صفحه‌ی بازی برسد (مثلاً دکمه‌ی خروج)
	if get_node_or_null("ChatLayer") != null:
		return
	var event := ev.duplicate()
	if event is InputEventMouse:
		event.position.y -= top_off
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			pressed_pos = event.position
			_press(event.position)
		else:
			pressed_pos = Vector2(-1, -1)
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
			for t in 3:
				if Rect2(Vector2(70 + t * 195, 292), Vector2(190, 40)).has_point(p):
					store_tab = t
					return
			for i in 5:
				if skin_rect(i).has_point(p):
					_pick_item(store_tab, i)
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
			if Api.token != "" and Rect2(Vector2(110, 750), Vector2(500, 64)).has_point(p):
				panel = "name"
				name_text = ""
				name_msg = ""
			if Api.token != "" and Rect2(Vector2(110, 834), Vector2(500, 60)).has_point(p):
				panel = "redeem"
				login_text = ""
				login_msg = ""
			if Api.token != "" and is_admin and Rect2(Vector2(110, 912), Vector2(500, 60)).has_point(p):
				panel = "codes"
				_load_codes()
			if Api.token != "" and Rect2(Vector2(110, 990), Vector2(500, 60)).has_point(p) and not close_rect().has_point(p):
				_open_chat()
			if Rect2(Vector2(110, 650), Vector2(500, 70)).has_point(p):
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
		"redeem":
			_login_pad(p)
			if Rect2(Vector2(110, 500), Vector2(500, 64)).has_point(p):
				_redeem()
		"codes":
			if Rect2(Vector2(110, 850), Vector2(500, 56)).has_point(p):
				panel = "newcode"
				name_text = ""
				name_msg = ""
		"newcode":
			_name_pad(p)
			if Rect2(Vector2(110, 910), Vector2(500, 56)).has_point(p):
				_create_code()


func _redeem() -> void:
	if login_busy or login_text.length() < 4:
		return
	login_busy = true
	login_msg = "در حال بررسی…"
	var r: Dictionary = await Api.redeem_code(login_text)
	if r.ok:
		account_balance = int(r.data.get("balance", account_balance))
		login_msg = "%d سکه گرفتی!" % int(r.data.get("added", 0))
		login_text = ""
		refresh_profile()
	else:
		login_msg = str(r.data.get("message", "ثبت نشد"))
	login_busy = false


func _load_codes() -> void:
	var r: Dictionary = await Api.codes_list()
	if r.ok:
		codes_list = r.data.get("codes", [])


func _create_code() -> void:
	if name_busy:
		return
	var txt := name_text.strip_edges()
	if txt.length() < 2:
		name_msg = "نام مستعار حداقل ۲ حرف"
		return
	name_busy = true
	var r: Dictionary = await Api.codes_create(txt)
	if r.ok:
		name_msg = "کد ساخته شد: " + str(r.data.get("code", ""))
		name_text = ""
		_load_codes()
	else:
		name_msg = str(r.data.get("message", "ساخته نشد"))
	name_busy = false


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


var is_admin := false
var codes_list: Array = []
var name_text := ""
var name_msg := ""
var name_busy := false
const NAME_KEYS := ["ا","ب","پ","ت","ث","ج","چ","ح","خ","د","ذ","ر","ز","ژ","س","ش","ص","ض","ط","ظ","ع","غ","ف","ق","ک","گ","ل","م","ن","و","ه","ی","0","1","2","3","4","5","6","7","8","9","_","فاصله","حذف"]


func _name_key_rect(i: int) -> Rect2:
	return Rect2(45 + (i % 6) * 106, 500 + (i / 6) * 50, 100, 44)


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
			_reset_guest_progress()
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


func _pick_item(tab: int, i: int) -> void:
	if tab == 0:
		_pick_skin(i)
		if Api.token != "" and Save.owned.has(i):
			Api.equip("skin", i)
		return
	var kind := "fx" if tab == 1 else "frame"
	var own: Array = Save.owned_fx if tab == 1 else Save.owned_frames
	var cost: int = (FX if tab == 1 else FRAMES)[i].cost
	if not own.has(i):
		if not await _pay(cost, "%s_%d" % [kind, i]):
			_need_coins(cost)
			return
		own.append(i)
		msg = "خریداری شد"
	if tab == 1:
		Save.fx = i
	else:
		Save.frame = i
	Save.save()
	if Api.token != "":
		Api.equip(kind, i)


# پرداخت: با حساب وارد‌شده از سرور، وگرنه از سکه‌ی محلی
func _pay(amount: int, reason: String) -> bool:
	if Api.token != "":
		busy = true
		var r: Dictionary = await Api.spend(amount, reason)
		busy = false
		if not r.ok:
			return false
		account_balance = int(r.data.get("balance", account_balance))
		_apply_free(r.data)
		return true
	return Save.spend_coins(amount)


func _need_coins(amount: int) -> void:
	msg = "سکه کافی نیست (%d سکه لازم است). می‌توانی سکه بخری." % amount
	panel = "shop"


func _undo() -> void:
	if game_over or history.is_empty():
		msg = "حرکتی برای برگشت نیست"
		return
	if not await _pay_or_free("undo", UNDO_COST, "undo"):
		_need_coins(UNDO_COST)
		return
	_restore(history.pop_back())
	msg = "یک حرکت برگشت"
	_save_game()


func _rotate(i: int) -> void:
	if game_over or hand[i] == null:
		return
	var old_cells: Array = hand[i].cells
	var my := 0
	for v in old_cells:
		my = maxi(my, v.y)
	var out := []
	for v in old_cells:
		out.append(Vector2i(my - v.y, v.x))
	# چرخش فوری؛ پرداخت در پس‌زمینه و در صورت رد شدن برگردانده می‌شود
	var piece = hand[i]
	piece.cells = out
	hint = {}
	_play("pick")
	var ok: bool = await _pay_or_free("rotate", ROTATE_COST, "rotate")
	if not ok:
		piece.cells = old_cells
		_need_coins(ROTATE_COST)
		return
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
	if not await _pay_or_free("shuffle", SHUFFLE_COST, "shuffle"):
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
			"fx": Save.fx,
			"t": 0.0,
		})
		board[idx] = 0
	if lines > 0:
		score += lines
		_play("clear")
		# سکه خیلی آهسته؛ فقط برای حساب محلی (حساب سرور فقط با خرید شارژ می‌شود)
		if Api.token != "":
			_send_lines(lines)
		Save.line_acc += lines
		while Save.line_acc >= LINES_PER_COIN:
			Save.line_acc -= LINES_PER_COIN
			if Api.token == "":
				Save.coins += 1
		Save.save()


func _send_lines(k: int) -> void:
	var r: Dictionary = await Api.submit_lines(k)
	if r.ok:
		account_balance = int(r.data.get("balance", account_balance))


func _find_hint() -> Dictionary:
	# راهنمای هوشمند: هر جایگذاری را شبیه‌سازی می‌کند؛ بیشترین ردیف/ستون پاک‌شده،
	# بعد کمترین حفره و بیشترین پر شدن ردیف‌ها را ترجیح می‌دهد.
	var best := {}
	var best_score := -1000000.0
	for i in hand.size():
		if hand[i] == null:
			continue
		for r in n:
			for c in n:
				if not _can_place(hand[i].cells, Vector2i(c, r)):
					continue
				var sim: Array = board.duplicate()
				for v in hand[i].cells:
					sim[(r + v.y) * n + c + v.x] = 1
				var rows_full: Array = []
				var cols_full: Array = []
				for k in n:
					var rf := true
					var cf := true
					for m in n:
						if sim[k * n + m] == 0:
							rf = false
						if sim[m * n + k] == 0:
							cf = false
					if rf:
						rows_full.append(k)
					if cf:
						cols_full.append(k)
				for k in rows_full:
					for m in n:
						sim[k * n + m] = 0
				for k in cols_full:
					for m in n:
						sim[m * n + k] = 0
				var holes := 0
				var fill := 0.0
				for y in n:
					for x in n:
						if sim[y * n + x] != 0:
							fill += 1
							continue
						var free_nb := 0
						for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
							var nx: int = x + d.x
							var ny: int = y + d.y
							if nx >= 0 and ny >= 0 and nx < n and ny < n and sim[ny * n + nx] == 0:
								free_nb += 1
						if free_nb == 0:
							holes += 1
				var sc: float = (rows_full.size() + cols_full.size()) * 100.0 - holes * 30.0 + hand[i].cells.size() * 0.5
				if sc > best_score:
					best_score = sc
					best = {"slot": i, "cell": Vector2i(c, r)}
	return best


func _use_hint() -> void:
	if game_over or not hint.is_empty():
		return
	var found := _find_hint()
	if found.is_empty():
		msg = "جای قانونی‌ای پیدا نشد"
		return
	if not await _pay_or_free("hint", HINT_COST, "hint"):
		_need_coins(HINT_COST)
		return
	hint = found
	msg = "قطعه‌ی روشن‌شده را روی خانه‌ی روشن بگذار"


func refresh_profile() -> void:
	var r: Dictionary = await Api.balance()
	if r.ok:
		account_balance = int(r.data.get("balance", 0))
		account_name = str(r.data.get("name", ""))
		is_admin = bool(r.data.get("is_admin", false))
		account_best = int(r.data.get("best", 0))
		for s in r.data.get("skins", []):
			if not Save.owned.has(int(s)):
				Save.owned.append(int(s))
		for s in r.data.get("fx", []):
			if not Save.owned_fx.has(int(s)):
				Save.owned_fx.append(int(s))
		for s in r.data.get("frames", []):
			if not Save.owned_frames.has(int(s)):
				Save.owned_frames.append(int(s))
		Save.skin = int(r.data.get("sel_skin", Save.skin))
		Save.fx = int(r.data.get("sel_fx", Save.fx))
		Save.frame = int(r.data.get("sel_frame", Save.frame))
		Save.save()
	elif r.code == 403:
		Api.logout()
		account_balance = -1
		is_admin = false
		msg = "حساب شما مسدود شده است"


# با ورود، پیشرفت مهمان پاک می‌شود و حساب از صفر شروع می‌کند
func _reset_guest_progress() -> void:
	Save.coins = 0
	Save.best_score = 0
	Save.line_acc = 0
	Save.owned = [0]
	Save.skin = 0
	Save.fx = 0
	Save.frame = 0
	Save.owned_fx = [0]
	Save.owned_frames = [0]
	Save.free = {"hint": 0, "shuffle": 0, "undo": 0, "rotate": 0}
	Save.save()


func _handle_launch_uri() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("cheeno://auth"):
			var code := arg.get_slice("code=", 1).get_slice("&", 0).uri_decode()
			var r: Dictionary = await Api.login(code)
			if r.ok:
				_reset_guest_progress()
				await refresh_profile()
			return
		if arg.begins_with("cheeno://paid"):
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


func _badge(r: Rect2, key: String) -> void:
	var f := ThemeDB.fallback_font
	var c := Vector2(r.position.x + 6, r.position.y + 6)
	var n: int = int(Save.free.get(key, 0))
	draw_circle(c, 20, Color("#ffd166") if n > 0 else Color("#4a3f7a"))
	draw_arc(c, 20, 0, TAU, 32, Color.WHITE, 2.0)
	draw_string(f, Vector2(c.x - 20, c.y + 9), str(n), HORIZONTAL_ALIGNMENT_CENTER, 40, 26,
		Color("#140d2b") if n > 0 else Color.WHITE)


# با حساب وارد‌شده سرور سهمیهٔ رایگان را حساب می‌کند؛ وگرنه محلی
func _pay_or_free(key: String, amount: int, reason: String) -> bool:
	if Api.token != "":
		return await _pay(amount, reason)
	if int(Save.free.get(key, 0)) > 0:
		Save.free[key] = int(Save.free[key]) - 1
		Save.save()
		return true
	return await _pay(amount, reason)


func _apply_free(d: Dictionary) -> void:
	var f = d.get("free", null)
	if f is Dictionary:
		for k in ["hint", "shuffle", "undo", "rotate"]:
			Save.free[k] = int(f.get(k, 0))
		Save.save()


func _daily_check() -> void:
	if Api.token != "":
		var r: Dictionary = await Api.daily()
		if r.ok:
			_apply_free(r.data)
			account_balance = int(r.data.get("balance", account_balance))
			if r.data.get("claimed", false):
				panel = "daily"
		return
	var today := Time.get_date_string_from_system()
	if Save.daily_day == today:
		return
	Save.daily_day = today
	Save.free = {"hint": 3, "shuffle": 3, "undo": 3, "rotate": 3}
	Save.coins += 20
	Save.save()
	panel = "daily"


func _btn(r: Rect2, text: String, fill := Color("#140d2b"), fs := 24, tc := Color.WHITE) -> void:
	var f := ThemeDB.fallback_font
	var sb := StyleBoxFlat.new()
	var down: bool = pressed_pos.x >= 0 and r.has_point(pressed_pos)
	sb.bg_color = fill.lightened(0.35) if down else fill
	sb.set_corner_radius_all(int(minf(r.size.y * 0.3, 22.0)))
	sb.border_color = Color("#ffd166") if down else Color("#7b5cff")
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	draw_style_box(sb, r)
	draw_string(f, Vector2(r.position.x, r.position.y + r.size.y / 2 + fs * 0.35), text,
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, tc)


# آواتار: سر انسان با پوست، مو و چهره؛ ۶ مدل مو/شکل متفاوت
func _ellipse(c: Vector2, rx: float, ry: float, n := 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n:
		var a := TAU * k / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

func _draw_avatar(c: Vector2, r: float, idx := -1) -> void:
	if idx < 0:
		idx = Save.avatar
	var bg := Color(AVATARS[idx])
	var skin := Color("#f1c49a") if idx % 2 == 0 else Color("#c68a5c")
	var hair: Color = [Color("#3b2416"), Color("#ff4fa3"), Color("#2b2b3a"), Color("#8a4b1f"), Color("#1f1f1f"), Color("#5b3a8f")][idx]
	var dark := Color("#2a1a12")
	# پس‌زمینه دایره‌ای با حاشیه طلایی
	draw_circle(c + Vector2(0, 3), r + 6, Color(0, 0, 0, 0.3))
	draw_circle(c, r + 6, Color("#b8860b"))
	draw_circle(c, r + 3.5, Color("#ffd166"))
	draw_circle(c, r, bg.darkened(0.12))
	draw_circle(c + Vector2(0, -r * 0.2), r * 0.8, bg.lightened(0.08))
	# بدن (شانه‌ها)
	draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.95), r * 0.62, r * 0.42), bg.darkened(0.2))
	# مو پشت سر (برای مدل‌های بلند)
	if idx == 1 or idx == 5:
		draw_colored_polygon(_ellipse(c + Vector2(0, -r * 0.05), r * 0.5, r * 0.62), hair)
	# گردن
	draw_rect(Rect2(c + Vector2(-r * 0.16, r * 0.25), Vector2(r * 0.32, r * 0.35)), skin.darkened(0.08))
	# سر
	draw_colored_polygon(_ellipse(c + Vector2(0, -r * 0.1), r * 0.42, r * 0.5), skin)
	# گوش‌ها
	draw_circle(c + Vector2(-r * 0.41, -r * 0.05), r * 0.09, skin.darkened(0.05))
	draw_circle(c + Vector2(r * 0.41, -r * 0.05), r * 0.09, skin.darkened(0.05))
	# مو جلو سر بر اساس مدل
	match idx:
		0: # کوتاه
			draw_colored_polygon(_ellipse(c + Vector2(0, -r * 0.3), r * 0.44, r * 0.25), hair)
		1: # بلند با پونی
			draw_colored_polygon(_ellipse(c + Vector2(0, -r * 0.32), r * 0.46, r * 0.26), hair)
			draw_circle(c + Vector2(r * 0.42, -r * 0.2), r * 0.13, hair)
		2: # کلاه
			draw_colored_polygon(_ellipse(c + Vector2(0, -r * 0.36), r * 0.44, r * 0.2), Color("#ffd166"))
			draw_rect(Rect2(c + Vector2(-r * 0.46, -r * 0.4), Vector2(r * 0.92, r * 0.08)), Color("#e0a800"))
		3: # فر
			for k in 7:
				var a := PI + PI * k / 6.0
				draw_circle(c + Vector2(cos(a) * r * 0.36, -r * 0.3 + sin(a) * r * 0.22), r * 0.14, hair)
			draw_circle(c + Vector2(0, -r * 0.45), r * 0.18, hair)
		4: # سیخی
			for k in 5:
				var x := -r * 0.3 + k * r * 0.15
				draw_colored_polygon(PackedVector2Array([c + Vector2(x - r * 0.1, -r * 0.3), c + Vector2(x + r * 0.05, -r * 0.62), c + Vector2(x + r * 0.1, -r * 0.3)]), hair)
		_: # موی کناری بلند
			draw_colored_polygon(_ellipse(c + Vector2(-r * 0.12, -r * 0.34), r * 0.4, r * 0.24), hair)
	# چشم‌های طبیعی: سفیدی، عنبیه، مردمک و برق
	var iris: Color = [Color("#4a2e1a"), Color("#2e7d5b"), Color("#3a5fa8"), Color("#6b4a2a"), Color("#222222"), Color("#7a3fa8")][idx]
	for sx in [-1.0, 1.0]:
		var ec: Vector2 = c + Vector2(sx * r * 0.17, -r * 0.1)
		draw_colored_polygon(_ellipse(ec, r * 0.09, r * 0.06), Color.WHITE)
		draw_circle(ec + Vector2(0, r * 0.004), r * 0.05, iris)
		draw_circle(ec + Vector2(0, r * 0.004), r * 0.026, dark)
		draw_circle(ec + Vector2(-r * 0.02, -r * 0.02), r * 0.014, Color.WHITE)
		draw_arc(ec, r * 0.09, deg_to_rad(200), deg_to_rad(340), 8, dark, maxf(1.2, r * 0.025))
	# ابروها با حالت متفاوت برای هر آواتار
	var tilt: float = [0.0, -0.03, 0.04, -0.02, 0.05, 0.0][idx]
	var bw := maxf(1.5, r * 0.035)
	draw_line(c + Vector2(-r * 0.27, -r * (0.22 - tilt)), c + Vector2(-r * 0.08, -r * (0.23 + tilt)), hair.darkened(0.2), bw)
	draw_line(c + Vector2(r * 0.08, -r * (0.23 + tilt)), c + Vector2(r * 0.27, -r * (0.22 - tilt)), hair.darkened(0.2), bw)
	# بینی
	draw_arc(c + Vector2(0, r * 0.0), r * 0.05, deg_to_rad(20), deg_to_rad(160), 6, skin.darkened(0.25), maxf(1.2, r * 0.02))
	# دهان: حالت‌های مختلف
	var mc := c + Vector2(0, r * 0.1)
	var lipc := Color("#b5483f")
	match idx % 3:
		0: # لبخند ملایم
			draw_arc(mc + Vector2(0, -r * 0.08), r * 0.15, deg_to_rad(25), deg_to_rad(155), 14, lipc, maxf(2.0, r * 0.04))
		1: # لبخند باز با دندان
			draw_colored_polygon(_ellipse(mc + Vector2(0, r * 0.02), r * 0.13, r * 0.07), Color("#7a1f2b"))
			draw_rect(Rect2(mc + Vector2(-r * 0.1, -r * 0.03), Vector2(r * 0.2, r * 0.035)), Color.WHITE)
		_: # لبخند کج شیطون
			draw_arc(mc + Vector2(r * 0.02, -r * 0.07), r * 0.14, deg_to_rad(15), deg_to_rad(140), 14, lipc, maxf(2.0, r * 0.04))
	# گونه
	draw_circle(c + Vector2(-r * 0.27, r * 0.08), r * 0.07, Color(1, 0.4, 0.5, 0.3))
	draw_circle(c + Vector2(r * 0.27, r * 0.08), r * 0.07, Color(1, 0.4, 0.5, 0.3))


func _draw_fx(kind: int, pos: Vector2, k: float, col: Color) -> void:
	var a := 1.0 - k
	match kind:
		1: # جرقه
			for i in 8:
				var d := Vector2.from_angle(i * TAU / 8.0)
				draw_line(pos + d * (10 + k * 60), pos + d * (22 + k * 80), _with_alpha(col, a), 3.0)
		2: # ستاره
			for i in 5:
				var d := Vector2.from_angle(i * TAU / 5.0 + k * 3.0) * (8 + k * 50)
				draw_circle(pos + d, 7.0 * a + 1.0, _with_alpha(Color("#ffe98a"), a))
		3: # انفجار
			draw_circle(pos, 10 + k * 70, _with_alpha(Color("#ff7b00"), a * 0.6))
			draw_circle(pos, 6 + k * 35, _with_alpha(Color("#ffd000"), a))
		4: # آتش‌بازی
			for i in 12:
				var d := Vector2.from_angle(i * TAU / 12.0)
				var c2 := Color.from_hsv(float(i) / 12.0, 0.8, 1.0, a)
				draw_circle(pos + d * (k * 80) + Vector2(0, k * k * 30), 4.0, c2)
		_:
			draw_arc(pos, 20.0 + k * 90.0, 0, TAU, 32, _with_alpha(col, a), 4.0)


func _draw_frame(kind: int, r: Rect2, t: float) -> void:
	match kind:
		1:
			draw_rect(r, Color("#ffd166"), false, 3.0)
			draw_rect(r.grow(-6), Color("#ffd166"), false, 2.0)
		2:
			var g := 0.5 + 0.5 * sin(t * 4.0)
			for i in 4:
				draw_rect(r.grow(i * 3), Color(0.2, 1, 0.9, (0.5 - i * 0.1) * (0.5 + g)), false, 3.0)
			draw_rect(r, Color("#7dfcf0"), false, 2.0)
		3:
			draw_rect(r, Color.from_hsv(fposmod(t * 0.3, 1.0), 0.8, 1.0), false, 5.0)
			draw_rect(r.grow(-7), Color.from_hsv(fposmod(t * 0.3 + 0.5, 1.0), 0.8, 1.0), false, 2.0)
		4:
			draw_rect(r.grow(4), Color("#c9962b"), false, 6.0)
			draw_rect(r.grow(-3), Color("#fff2a8"), false, 2.0)
			for cp in [r.position, r.position + Vector2(r.size.x, 0), r.position + Vector2(0, r.size.y), r.end]:
				draw_circle(cp, 8.0, Color("#e0245e"))
				draw_circle(cp, 3.0, Color.WHITE)
		_:
			draw_rect(r, Color("#4b3a8a"), false, 2.0)


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
	_draw_frame(Save.frame, frame, time)
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
		_draw_fx(int(fl.get("fx", 0)), fl["pos"], fl["t"] / 0.5, fl["color"])

	if not hint.is_empty():
		var pulse := 0.5 + 0.5 * sin(time * 6.0)
		var hc2 := Color(1, 0.84, 0.4, pulse)
		draw_rect(slot_rect(hint.slot), hc2, false, 4.0)
		for v in hand[hint.slot].cells:
			var cp: Vector2i = hint.cell + v
			draw_rect(Rect2(cell_pos(cp.x, cp.y), Vector2(cell, cell)), hc2, false, 4.0)

	_btn(hint_rect(), "راهنما: %d سکه" % HINT_COST, Color("#140d2b"), 26)
	_btn(shuffle_rect(), "تعویض کارت‌ها: %d سکه" % SHUFFLE_COST, Color("#140d2b"), 24)
	_btn(undo_rect(), "برگشت حرکت: %d سکه" % UNDO_COST, Color("#140d2b"), 24)
	_btn(rotate_rect(), "چرخش کارت: %d سکه" % ROTATE_COST, Color("#3a2a7a") if rot_mode else Color("#140d2b"), 24)
	_badge(hint_rect(), "hint")
	_badge(shuffle_rect(), "shuffle")
	_badge(undo_rect(), "undo")
	_badge(rotate_rect(), "rotate")
	_btn(shop_rect(), "خرید سکه", Color("#3a2a7a"), 22)
	_btn(records_rect(), "رکوردها", Color("#140d2b"), 22)

	if msg != "":
		draw_string(f, Vector2(0, 1278), msg, HORIZONTAL_ALIGNMENT_CENTER, 720, 22, Color("#d9d0ff"))

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
	var title: String = {"skins": "پوسته‌ها", "sound": "صدا", "profile": "پروفایل", "login": "ورود", "shop": "خرید سکه", "records": "رکوردها", "name": "تغییر نام", "redeem": "کد هدیه", "codes": "کدهای هدیه", "newcode": "کد جدید", "daily": "هدیهٔ امروز"}.get(panel, "")
	draw_string(f, Vector2(0, 330), title, HORIZONTAL_ALIGNMENT_CENTER, 720, 40, Color.WHITE)
	draw_string(f, Vector2(0, 370 if panel != "skins" else 1000), "سکه: %d" % _coins() if not panel in ["login", "name", "redeem", "newcode"] else "",
		HORIZONTAL_ALIGNMENT_CENTER, 720, 24, Color("#ffd166"))
	match panel:
		"daily":
			draw_string(f, Vector2(60, 470), "۲۰ سکه هدیه گرفتی!", HORIZONTAL_ALIGNMENT_CENTER, 600, 32, Color("#ffd166"))
			draw_string(f, Vector2(60, 560), "امروز از هرکدام ۳ بار رایگان داری:", HORIZONTAL_ALIGNMENT_CENTER, 600, 26, Color.WHITE)
			draw_string(f, Vector2(60, 620), "راهنما، تعویض کارت‌ها، چرخش کارت، برگشت حرکت", HORIZONTAL_ALIGNMENT_CENTER, 600, 24, Color.WHITE)
			draw_string(f, Vector2(60, 700), "هر روز ساعت ۰۰:۰۰ دوباره پر می‌شود.", HORIZONTAL_ALIGNMENT_CENTER, 600, 22, Color("#b9a8ff"))
		"skins":
			for t in 3:
				var tr := Rect2(Vector2(70 + t * 195, 292), Vector2(190, 40))
				draw_rect(tr, Color("#3a2a7a") if store_tab == t else Color("#140d2b"))
				draw_rect(tr, Color("#ffd166") if store_tab == t else Color("#3c2a6e"), false, 2.0)
				draw_string(f, Vector2(tr.position.x, tr.position.y + 28), ["پوسته", "افکت", "قاب"][t], HORIZONTAL_ALIGNMENT_CENTER, 190, 22, Color.WHITE)
			for i in 5:
				var r := skin_rect(i)
				var items: Array = [SKINS, FX, FRAMES][store_tab]
				var own: Array = [Save.owned, Save.owned_fx, Save.owned_frames][store_tab]
				var cur: int = [Save.skin, Save.fx, Save.frame][store_tab]
				var sel: bool = cur == i
				draw_rect(r, Color("#3a2a7a") if sel else Color("#140d2b"))
				draw_rect(r, Color("#ffd166") if sel else Color("#3c2a6e"), false, 2.0)
				if store_tab == 0:
					for j in 5:
						draw_rect(Rect2(r.position + Vector2(16 + j * 36, 24), Vector2(30, 48)), Color(SKINS[i].colors[j]))
				elif store_tab == 1:
					_draw_fx(i, r.position + Vector2(90, 48), 0.6, Color("#ffd166"))
				else:
					_draw_frame(i, Rect2(r.position + Vector2(30, 18), Vector2(120, 60)), 0.0)
				var st: String = "انتخاب‌شده" if sel else ("مال شماست" if own.has(i) else "%d سکه" % items[i].cost)
				draw_string(f, Vector2(r.position.x + 210, r.position.y + 58), "%s  -  %s" % [items[i].name, st],
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
				for i in mini(records.size(), 8):
					var it: Dictionary = records[i]
					var cr := Rect2(Vector2(70, 380 + i * 92), Vector2(580, 80))
					var rk := int(it.get("rank", i + 1))
					var bc: Color = [Color("#ffd166"), Color("#c0c7d6"), Color("#cd7f32")][rk - 1] if rk >= 1 and rk <= 3 else Color("#7b5cff")
					draw_rect(cr, Color("#2a1f55"))
					draw_rect(cr, bc, false, 3.0)
					draw_rect(Rect2(cr.position + Vector2(6, 6), cr.size - Vector2(12, 12)), Color("#3c2a6e"), false, 1.0)
					draw_circle(cr.position + Vector2(44, 40), 28, bc)
					draw_string(f, cr.position + Vector2(16, 51), "%d" % rk, HORIZONTAL_ALIGNMENT_CENTER, 56, 30, Color("#140d2b"))
					draw_string(f, cr.position + Vector2(90, 52), str(it.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, 320, 28, Color.WHITE)
					draw_string(f, cr.position + Vector2(380, 52), "%d" % int(it.get("score", 0)), HORIZONTAL_ALIGNMENT_RIGHT, 180, 30, Color("#ffd166"))
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
				_draw_avatar(c, 34, i)
				if Save.avatar == i:
					draw_arc(c, 42, 0, TAU, 32, Color.WHITE, 4.0)
			var nm := "مهمان" if Api.token == "" else account_name
			draw_string(f, Vector2(0, 610), nm, HORIZONTAL_ALIGNMENT_CENTER, 720, 28, Color.WHITE)
			_btn(Rect2(Vector2(110, 650), Vector2(500, 70)), "ورود / ثبت‌نام" if Api.token == "" else "خروج از حساب", Color("#3a2a7a"), 26)
			if Api.token != "":
				_btn(Rect2(Vector2(110, 750), Vector2(500, 64)), "تغییر نام", Color("#2a1f55"), 26)
				_btn(Rect2(Vector2(110, 834), Vector2(500, 60)), "کد هدیه", Color("#2a1f55"), 24)
				if is_admin:
					_btn(Rect2(Vector2(110, 912), Vector2(500, 60)), "مدیریت کدها", Color("#5a2a55"), 22)
				_btn(Rect2(Vector2(110, 990), Vector2(500, 60)), "چت خصوصی", Color("#1f5a55"), 24)
		"redeem":
			draw_string(f, Vector2(0, 372), "کد هدیه را وارد کن", HORIZONTAL_ALIGNMENT_CENTER, 720, 24, Color("#d9d0ff"))
			var rr := Rect2(110, 404, 500, 72)
			draw_rect(rr, Color("#f4f0ff"))
			draw_rect(rr, Color("#ff6ad5"), false, 3.0)
			draw_string(f, Vector2(rr.position.x, rr.position.y + 48), login_text if login_text != "" else "--------", HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, 36, Color("#140d2b"))
			_btn(Rect2(Vector2(110, 500), Vector2(500, 64)), "ثبت کد", Color("#3a2a7a"), 26)
			draw_string(f, Vector2(0, 596), login_msg, HORIZONTAL_ALIGNMENT_CENTER, 720, 22, Color("#ffd166"))
			var rpad := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "حذف", "0", "پاک"]
			for i in rpad.size():
				_btn(_pad_rect(i), rpad[i], Color("#2a1f55"), 30)
		"codes":
			for i in mini(codes_list.size(), 8):
				var c: Dictionary = codes_list[i]
				var y := 410.0 + i * 54
				draw_string(f, Vector2(70, y), "%s  %s" % [str(c.get("alias", "")), str(c.get("code", ""))], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
				draw_string(f, Vector2(70, y + 26), "%d نفر  |  خرید کل: %d سکه" % [int(c.get("count", 0)), int(c.get("total", 0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#d9d0ff"))
			_btn(Rect2(Vector2(110, 850), Vector2(500, 56)), "ساخت کد جدید", Color("#3a2a7a"), 26)
		"newcode":
			draw_string(f, Vector2(0, 318), "نام مستعار کد را بنویس", HORIZONTAL_ALIGNMENT_CENTER, 720, 24, Color("#d9d0ff"))
			var cr := Rect2(110, 330, 500, 56)
			draw_rect(cr, Color("#f4f0ff"))
			draw_rect(cr, Color("#ff6ad5"), false, 3.0)
			draw_string(f, Vector2(cr.position.x, cr.position.y + 38), name_text if name_text != "" else "نام مستعار", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 30, Color("#140d2b") if name_text != "" else Color("#8a80b8"))
			draw_string(f, Vector2(0, 408), name_msg, HORIZONTAL_ALIGNMENT_CENTER, 720, 22, Color("#ffd166"))
			for i in NAME_KEYS.size():
				_btn(_name_key_rect(i), NAME_KEYS[i], Color("#2a1f55"), 22)
			_btn(Rect2(Vector2(110, 836), Vector2(500, 56)), "ساخت کد", Color("#3a2a7a"), 26)
		"name":
			draw_string(f, Vector2(0, 372), "اسم خودت را بنویس (۲ تا ۱۲ حرف)", HORIZONTAL_ALIGNMENT_CENTER, 720, 24, Color("#d9d0ff"))
			var nr := Rect2(110, 396, 500, 56)
			draw_rect(nr, Color("#f4f0ff"))
			draw_rect(nr, Color("#ff6ad5"), false, 3.0)
			draw_string(f, Vector2(nr.position.x, nr.position.y + 38), name_text if name_text != "" else "نام", HORIZONTAL_ALIGNMENT_CENTER, nr.size.x, 30, Color("#140d2b") if name_text != "" else Color("#8a80b8"))
			draw_string(f, Vector2(0, 476), name_msg, HORIZONTAL_ALIGNMENT_CENTER, 720, 20, Color("#ffd166"))
			for i in NAME_KEYS.size():
				_btn(_name_key_rect(i), NAME_KEYS[i], Color("#2a1f55"), 22)
			_btn(Rect2(Vector2(110, 910), Vector2(500, 56)), "ذخیرهٔ نام", Color("#3a2a7a"), 26)
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


func _open_chat() -> void:
	if get_node_or_null("ChatLayer") != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "ChatLayer"
	layer.layer = 50
	var bg := ColorRect.new()
	bg.color = Color("#140d2b")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(bg)
	var scr: Control = load("res://scripts/chat_screen.gd").new()
	layer.add_child(scr)
	scr.tree_exited.connect(func(): layer.queue_free())
	add_child(layer)

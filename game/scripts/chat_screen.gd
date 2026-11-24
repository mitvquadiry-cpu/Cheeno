extends Control

# صفحه‌ی چت خصوصی. همه‌ی UI در کد ساخته می‌شود تا نیازی به تغییر main.tscn نباشد.
# نام‌ها و پیام‌ها فقط از سرور می‌آیند؛ سرور همه‌ی قوانین (سکه، بلاک، محدودیت) را چک می‌کند.

const PhotoC := preload("res://scripts/photo_cache.gd")
const NAME_MAX := 40
const MSG_MAX := 200

var root: VBoxContainer
var status: Label
var content: VBoxContainer
var my_name := ""
var unlocked := false
var current_with := ""


var preview: PanelContainer
var chat_bg: Control
var bg_idx := 0
const BG_THEMES := [
	{"name": "کهکشان", "c": ["#0b0320", "#2a0f5c", "#0a1a3d"], "star": Color(1, 1, 1, 0.85)},
	{"name": "غروب", "c": ["#2b0a2e", "#8a2c3c", "#f08a4b"], "star": Color(1, 0.85, 0.5, 0.6)},
	{"name": "اقیانوس", "c": ["#021a24", "#063c4d", "#0f6f74"], "star": Color(0.6, 1, 0.95, 0.5)},
	{"name": "جنگل شب", "c": ["#04140b", "#0d3320", "#1d5a3a"], "star": Color(0.9, 1, 0.7, 0.7)},
	{"name": "طلایی لوکس", "c": ["#120c02", "#3d2a06", "#7a5612"], "star": Color(1, 0.9, 0.5, 0.8)},
]
var _stars: Array = []
var preview_lbl: Label


func _bg_load() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://chat_bg.cfg") == OK:
		bg_idx = clampi(int(cf.get_value("bg", "idx", 0)), 0, BG_THEMES.size() - 1)
	_bg_apply()


func _bg_apply() -> void:
	var th: Dictionary = BG_THEMES[bg_idx]
	var cols: Array = th.c
	var g := Gradient.new()
	g.set_color(0, Color(cols[0]))
	g.set_color(1, Color(cols[2]))
	g.add_point(0.5, Color(cols[1]))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.25)
	gt.fill_to = Vector2(1.0, 1.0)
	gt.width = 512
	gt.height = 512
	chat_bg.set_meta("tex", gt)
	chat_bg.set_meta("star", th.star)
	_stars.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = bg_idx * 7919 + 1
	for i in 90:
		_stars.append([Vector2(rng.randf(), rng.randf()), rng.randf_range(1.0, 3.2), rng.randf()])
	chat_bg.queue_redraw()


func _draw_bg() -> void:
	var sz := chat_bg.size
	var gt: Texture2D = chat_bg.get_meta("tex")
	chat_bg.draw_texture_rect(gt, Rect2(Vector2.ZERO, sz), false)
	var sc: Color = chat_bg.get_meta("star")
	var t := Time.get_ticks_msec() / 1000.0
	for s in _stars:
		var a: float = sc.a * (0.45 + 0.55 * sin(t * 1.5 + s[2] * 6.28))
		chat_bg.draw_circle(s[0] * sz, s[1], Color(sc.r, sc.g, sc.b, a))


func _bg_cycle() -> void:
	bg_idx = (bg_idx + 1) % BG_THEMES.size()
	var cf := ConfigFile.new()
	cf.set_value("bg", "idx", bg_idx)
	cf.save("user://chat_bg.cfg")
	_bg_apply()
	_set_status("پس‌زمینه: " + str(BG_THEMES[bg_idx].name))


func _process(_d: float) -> void:
	if chat_bg and is_instance_valid(chat_bg):
		chat_bg.queue_redraw()
	if preview == null:
		return
	var fo := get_viewport().gui_get_focus_owner()
	var kb := DisplayServer.virtual_keyboard_get_height()
	if root != null:
		var vs0 := get_viewport().get_visible_rect().size
		var r0 := vs0.y / maxf(1.0, float(DisplayServer.window_get_size().y))
		var lift := kb * r0 if kb > 0 else 0.0
		var nh := vs0.y - 110 - lift
		if absf(root.size.y - nh) > 1.0:
			root.size = Vector2(vs0.x - 40, nh)
			_to_bottom(true)
	if false and fo is LineEdit and kb > 0 and (fo as LineEdit).text != "":
		var vs := get_viewport().get_visible_rect().size
		var ratio := vs.y / maxf(1.0, float(DisplayServer.window_get_size().y))
		preview_lbl.text = (fo as LineEdit).text
		preview.size = Vector2(vs.x - 40, 0)
		preview.position = Vector2(20, vs.y - kb * ratio - preview.size.y - 90)
		preview.visible = true
	else:
		preview.visible = false


func _ready() -> void:
	# والد CanvasLayer است و اندازه ندارد؛ پس اندازه را صریح می‌دهیم (علت صفحه‌ی خالی)
	var vs := get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	size = vs
	custom_minimum_size = vs
	chat_bg = Control.new()
	chat_bg.size = vs
	chat_bg.draw.connect(_draw_bg)
	add_child(chat_bg)
	_bg_load()
	mouse_filter = Control.MOUSE_FILTER_STOP
	preview = PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color("#4a35a8")
	psb.set_corner_radius_all(14)
	psb.set_content_margin_all(12)
	preview.add_theme_stylebox_override("panel", psb)
	preview_lbl = Label.new()
	preview_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_lbl.add_theme_font_size_override("font_size", 26)
	preview.add_child(preview_lbl)
	preview.visible = false
	preview.z_index = 50
	root = VBoxContainer.new()
	root.position = Vector2(20, 90)
	root.size = vs - Vector2(40, 110)
	root.add_theme_constant_override("separation", 14)
	add_child(root)
	add_child(preview)

	var top := HBoxContainer.new()
	root.add_child(top)
	var back := Button.new()
	back.text = "بازگشت"
	_sbtn(back, Color("#3a2a7a"))
	back.pressed.connect(func(): queue_free())
	top.add_child(back)
	var bgb := Button.new()
	bgb.text = "پس‌زمینه"
	_sbtn(bgb, Color("#3a2a7a"))
	bgb.pressed.connect(_bg_cycle)
	top.add_child(bgb)
	var title := Label.new()
	title.text = "چت خصوصی"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("#ffd166"))
	top.add_child(title)

	status = Label.new()
	status.add_theme_color_override("font_color", Color("#ffd166"))
	root.add_child(status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 40
	scroll.name = "Scroll"
	root.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

	_load_state()
	_poll_incoming()


# کارت قاب‌دار؛ فرزند را داخل آن می‌گذارد
func _card(parent: Control, child: Control, col := Color("#2a1f55")) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(2)
	sb.border_color = Color("#7b5cff")
	sb.set_content_margin_all(16)
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_child(child)
	parent.add_child(p)
	return p


func _label(t: String, fs := 24) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", fs)
	return l


func _sbtn(b: Button, col := Color("#5b3fd6")) -> void:
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.lightened(0.15) if st == "hover" else (col.darkened(0.25) if st in ["pressed", "disabled"] else col)
		sb.set_corner_radius_all(16)
		sb.set_content_margin_all(12)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_font_size_override("font_size", 24)
	b.custom_minimum_size.y = 64


func _sinput(e: LineEdit) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#2a1f55")
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(2)
	sb.border_color = Color("#7b5cff")
	sb.set_content_margin_all(14)
	e.add_theme_stylebox_override("normal", sb)
	e.add_theme_stylebox_override("focus", sb)
	e.add_theme_font_size_override("font_size", 24)
	e.custom_minimum_size = Vector2(0, 64)


func _avatar_circle(name_: String, sz := 56) -> Control:
	return PhotoC.make(name_, sz)

func _empty_note(parent: Control, t: String) -> void:
	var l := _label(t, 22)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.modulate = Color("#b9a8ff")
	parent.add_child(l)


func _set_status(t: String) -> void:
	status.text = t


func _clear() -> void:
	for c in content.get_children():
		c.queue_free()


func _err(r: Dictionary, fallback: String) -> String:
	var msg := str(r.data.get("message", ""))
	return msg if msg != "" else fallback


func _load_state() -> void:
	_set_status("در حال بارگذاری...")
	var r: Dictionary = await Api.chat_state()
	if not r.ok:
		_set_status("خطا در اتصال. دوباره تلاش کن.")
		return
	my_name = str(r.data.get("name", ""))
	unlocked = bool(r.data.get("unlocked", false))
	_set_status("")
	if my_name == "":
		_show_name_form()
	elif not unlocked:
		_show_unlock(int(r.data.get("unlock_price", 100)), int(r.data.get("balance", 0)))
	else:
		_show_threads()


func _show_name_form() -> void:
	_clear()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.add_child(_label("یک نام برای چت انتخاب کن (۳ تا %d حرف). دیگران با این نام تو را پیدا می‌کنند. شماره‌ی تلفن نمایش داده نمی‌شود." % NAME_MAX))
	var input := LineEdit.new()
	input.max_length = NAME_MAX
	input.placeholder_text = "نام چت"
	input.custom_minimum_size = Vector2(0, 64)
	box.add_child(input)
	var btn := Button.new()
	btn.text = "ثبت نام"
	btn.custom_minimum_size = Vector2(0, 64)
	box.add_child(btn)
	_card(content, box)
	btn.pressed.connect(func():
		btn.disabled = true
		var r: Dictionary = await Api.chat_set_name(input.text.strip_edges())
		btn.disabled = false
		if r.ok:
			_load_state()
		else:
			_set_status(_err(r, "ثبت نام انجام نشد."))
	)


func _show_unlock(price: int, balance: int) -> void:
	_clear()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.add_child(_label("برای باز کردن چت خصوصی %d سکه یک‌بار پرداخت می‌شود. بعد از آن هر پیام ۲ سکه هزینه دارد.\nموجودی تو: %d سکه." % [price, balance]))
	var btn := Button.new()
	btn.text = "باز کردن چت (%d سکه)" % price
	btn.custom_minimum_size = Vector2(0, 64)
	box.add_child(btn)
	_card(content, box)
	btn.pressed.connect(func():
		btn.disabled = true
		var r: Dictionary = await Api.chat_unlock()
		btn.disabled = false
		if r.ok:
			unlocked = true
			_show_threads()
		else:
			_set_status(_err(r, "باز کردن چت انجام نشد."))
	)
	var rules := _label("قوانین: ادمین سایت می‌تواند همه‌ی پیام‌های چت را ببیند. توهین، تهدید و کلاهبرداری ممنوع است و حساب می‌تواند مسدود شود.", 20)
	rules.modulate = Color(1, 0.85, 0.4)
	_card(content, rules, Color("#3a2a1a"))


func _show_threads() -> void:
	_clear()
	var search_row := HBoxContainer.new()
	content.add_child(search_row)
	var input := LineEdit.new()
	input.placeholder_text = "نام یا شماره موبایل..."
	_sinput(input)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_row.add_child(input)
	var go := Button.new()
	go.text = "جست‌وجو"
	_sbtn(go, Color("#ffb300"))
	go.add_theme_color_override("font_color", Color("#2a1f55"))
	search_row.add_child(go)
	var fhdr := _label("دوستان من", 24)
	fhdr.modulate = Color("#b9a8ff")
	content.add_child(fhdr)
	var flist := VBoxContainer.new()
	flist.add_theme_constant_override("separation", 10)
	content.add_child(flist)
	_load_friends(flist)
	var hdr := _label("گفتگوهای تو", 24)
	hdr.modulate = Color("#b9a8ff")
	var clr_all := Button.new()
	clr_all.text = "پاک کردن همه"
	_sbtn(clr_all, Color("#a83255"))
	clr_all.pressed.connect(func():
		var rr: Dictionary = await Api.chat_clear("")
		if rr.ok:
			_show_threads()
		else:
			_set_status(_err(rr, "پاک نشد."))
	)
	var hrow := HBoxContainer.new()
	hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(hdr)
	hrow.add_child(clr_all)
	content.add_child(hrow)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(list)
	go.pressed.connect(func(): _search(input.text.strip_edges(), list))
	input.text_submitted.connect(func(t): _search(t.strip_edges(), list))

	var fr: Dictionary = await Api.soc_friends()
	var fset := {}
	if fr.ok:
		for f0 in fr.data.get("items", []):
			fset[str(f0.get("name", ""))] = true
	var r: Dictionary = await Api.chat_threads()
	if r.ok and is_inside_tree():
		var its: Array = r.data.get("items", [])
		if its.is_empty():
			_empty_note(list, "هنوز گفتگویی نداری\nبالا نام یک بازیکن را جست‌وجو کن و شروع کن.")
		for it in its:
			var pn := str(it.get("name", ""))
			_add_partner_button(list, pn, fr.ok and not fset.has(pn))


func _search(q: String, list: VBoxContainer) -> void:
	if q.length() < 2:
		_set_status("حداقل ۲ حرف یا یک شماره لازم است.")
		return
	for c in list.get_children():
		c.queue_free()
	var r: Dictionary = await Api.soc_find(q)
	if not r.ok:
		_set_status(_err(r, "جست‌وجو انجام نشد."))
		return
	_set_status("")
	var items: Array = r.data.get("items", [])
	if items.is_empty():
		_empty_note(list, "کسی با این نام پیدا نشد\nنام را همان‌طور که در بازی ثبت شده بنویس.")
	for it in items:
		_add_partner_button(list, str(it.get("name", "")), true)


func _add_partner_button(list: VBoxContainer, partner: String, searched := false) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(_avatar_circle(partner))
	var n := Button.new()
	n.text = partner
	n.flat = true
	n.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	n.focus_mode = Control.FOCUS_NONE
	n.add_theme_font_size_override("font_size", 28)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.custom_minimum_size.y = 64
	n.pressed.connect(func(): _open_thread(partner))
	row.add_child(n)
	var uc := int(Api.unread_by_name.get(partner, 0))
	if uc > 0:
		var bd := Label.new()
		bd.text = " %d " % mini(uc, 99)
		bd.add_theme_font_size_override("font_size", 22)
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color("#e5334b")
		bsb.set_corner_radius_all(16)
		bd.add_theme_stylebox_override("normal", bsb)
		bd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(bd)
	if searched:
		var ab := Button.new()
		ab.text = "افزودن دوست"
		_sbtn(ab, Color("#1f8a55"))
		ab.pressed.connect(func():
			ab.disabled = true
			var rr: Dictionary = await Api.soc_add(partner)
			if rr.ok:
				_show_threads()
				_set_status("به دوستان اضافه شد.")
			else:
				ab.disabled = false
				_set_status(_err(rr, "اضافه نشد."))
		)
		row.add_child(ab)
	_card(list, row)


func _open_thread(partner: String) -> void:
	if not is_inside_tree():
		return
	current_with = partner
	_clear()
	var top := HBoxContainer.new()
	content.add_child(top)
	var back := Button.new()
	back.text = "گفتگوها"
	_sbtn(back, Color("#3a2a7a"))
	back.pressed.connect(func(): _show_threads())
	top.add_child(back)
	var who := HBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_theme_constant_override("separation", 10)
	who.add_child(_avatar_circle(partner, 44))
	who.add_child(_label(partner, 26))
	top.add_child(who)
	var block := Button.new()
	block.text = "بلاک"
	_sbtn(block, Color("#a83255"))
	top.add_child(block)
	block.pressed.connect(func(): _toggle_block(block))
	var clr := Button.new()
	clr.text = "حذف"
	_sbtn(clr, Color("#6b5a9e"))
	clr.pressed.connect(func():
		var rr: Dictionary = await Api.chat_clear(partner)
		if rr.ok:
			_show_threads()
		else:
			_set_status(_err(rr, "پاک نشد."))
	)
	top.add_child(clr)
	_live_loop(partner)
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 8)
	content.add_child(acts)
	var gb := Button.new()
	gb.text = "هدیه سکه"
	_sbtn(gb, Color("#ffb300"))
	gb.add_theme_color_override("font_color", Color("#2a1f55"))
	gb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gb.pressed.connect(func(): _gift_dialog(partner))
	acts.add_child(gb)
	var cb := Button.new()
	cb.text = "مکالمه صوتی"
	_sbtn(cb, Color("#1f8a55"))
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb.pressed.connect(func(): _call_start(partner))
	acts.add_child(cb)
	var afb := Button.new()
	afb.text = "افزودن دوست"
	_sbtn(afb, Color("#3a2a7a"))
	afb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	afb.pressed.connect(func():
		afb.disabled = true
		var ar: Dictionary = await Api.soc_add(partner)
		_set_status("به دوستان اضافه شد." if ar.ok else _err(ar, "اضافه نشد."))
		if ar.ok:
			afb.visible = false
		else:
			afb.disabled = false
	)
	acts.add_child(afb)

	var msgs := VBoxContainer.new()
	msgs.name = "Msgs"
	msgs.add_theme_constant_override("separation", 10)
	msgs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(msgs)

	var row := HBoxContainer.new()
	content.add_child(row)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 40)
	content.add_child(pad)
	var input := LineEdit.new()
	input.max_length = MSG_MAX
	input.placeholder_text = "پیام (حداکثر ۲۰۰ حرف، ۲ سکه)"
	_sinput(input)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	var send := Button.new()
	send.text = "ارسال"
	_sbtn(send, Color("#2fbf71"))
	row.add_child(send)
	send.pressed.connect(func(): _send(input, send))
	input.text_submitted.connect(func(_t): _send(input, send))
	input.focus_entered.connect(func(): _to_bottom(true))

	await _refresh_messages(msgs)
	_to_bottom(true)


func _to_bottom(delay := false) -> void:
	var sc := root.get_node_or_null("Scroll") as ScrollContainer
	if sc == null:
		return
	if delay:
		await get_tree().create_timer(0.35).timeout
	await get_tree().process_frame
	if is_instance_valid(sc):
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)


func _refresh_messages(msgs: VBoxContainer) -> void:
	var r: Dictionary = await Api.chat_messages(current_with)
	if not r.ok:
		_set_status(_err(r, "خطا در بارگذاری پیام‌ها."))
		return
	for c in msgs.get_children():
		c.queue_free()
	var items: Array = r.data.get("items", [])
	if items.is_empty():
		_empty_note(msgs, "هنوز پیامی نیست. اولین پیام را بفرست")
	for m in items:
		var mine: bool = m.get("mine", false)
		var txt := str(m.get("text", ""))
		var l := _label(txt, 24)
		l.custom_minimum_size.x = mini(80 + txt.length() * 16, 440)
		var box := HBoxContainer.new()
		box.add_child(l)
		var mid := int(m.get("id", 0))
		if not mine:
			var rep := Button.new()
			rep.text = "گزارش"
			rep.flat = true
			rep.pressed.connect(func():
				var rr: Dictionary = await Api.chat_report(mid)
				_set_status("گزارش ثبت شد." if rr.ok else _err(rr, "گزارش انجام نشد."))
			)
			box.add_child(rep)
		var wrap := HBoxContainer.new()
		wrap.alignment = BoxContainer.ALIGNMENT_END if mine else BoxContainer.ALIGNMENT_BEGIN
		msgs.add_child(wrap)
		var col := Color("#2b5278") if mine else Color("#182533")
		var bp := PanelContainer.new()
		var bs := StyleBoxFlat.new()
		bs.bg_color = col
		bs.set_corner_radius_all(22)
		if mine:
			bs.corner_radius_bottom_right = 5
		else:
			bs.corner_radius_bottom_left = 5
		bs.content_margin_left = 18
		bs.content_margin_right = 18
		bs.content_margin_top = 10
		bs.content_margin_bottom = 8
		bp.add_theme_stylebox_override("panel", bs)
		var tm := Time.get_datetime_dict_from_unix_time(int(m.get("time", 0)) + 12600)
		var tstr := "%02d:%02d" % [tm.hour, tm.minute]
		var is_read: bool = mine and m.get("read", false)
		if mine:
			tstr += "  ✓✓" if is_read else "  ✓"
		var tl := _label(tstr, 16)
		tl.modulate = Color(0.55, 0.85, 1, 0.95) if is_read else Color(1, 1, 1, 0.55)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var bv := VBoxContainer.new()
		bv.add_theme_constant_override("separation", 2)
		box.get_parent()
		bv.add_child(box)
		bv.add_child(tl)
		bp.add_child(bv)
		bp.size_flags_horizontal = Control.SIZE_SHRINK_END if mine else Control.SIZE_SHRINK_BEGIN
		wrap.add_child(bp)


func _live_loop(partner: String) -> void:
	while is_inside_tree():
		await get_tree().create_timer(3.0).timeout
		if not is_inside_tree() or current_with != partner:
			return
		var msgs := content.get_node_or_null("Msgs") as VBoxContainer
		if msgs == null:
			return
		await _refresh_messages(msgs)


func _send(input: LineEdit, btn: Button) -> void:
	var text := input.text.strip_edges()
	if text == "":
		return
	btn.disabled = true
	var r: Dictionary = await Api.chat_send(current_with, text)
	btn.disabled = false
	if r.ok:
		input.text = ""
		_snd("msg_out")
		_set_status("موجودی: %d سکه" % int(r.data.get("balance", 0)))
		var msgs := content.get_node_or_null("Msgs") as VBoxContainer
		if msgs:
			await _refresh_messages(msgs)
	else:
		_set_status(_err(r, "ارسال انجام نشد."))


func _toggle_block(btn: Button) -> void:
	var on := btn.text == "بلاک"
	var r: Dictionary = await Api.chat_block(current_with, on)
	if r.ok:
		btn.text = "آنبلاک" if on else "بلاک"
		_set_status("بلاک شد." if on else "آنبلاک شد.")
	else:
		_set_status(_err(r, "انجام نشد."))


# ---------- دوستان، هدیه، تماس ----------
var call_unlocked := false
var friends_balance := 0


func _load_friends(flist: VBoxContainer) -> void:
	var r: Dictionary = await Api.soc_friends()
	if not r.ok or not is_inside_tree():
		return
	call_unlocked = bool(r.data.get("call_unlocked", false))
	friends_balance = int(r.data.get("balance", 0))
	var its: Array = r.data.get("items", [])
	if its.is_empty():
		_empty_note(flist, "هنوز دوستی نداری. بالا جست‌وجو کن و «افزودن دوست» بزن.")
	for it in its:
		var nm := str(it.get("name", ""))
		var box := VBoxContainer.new()
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 12)
		top.add_child(_avatar_circle(nm, 48))
		var l := _label(nm, 26)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		top.add_child(l)
		box.add_child(top)
		var btns := HBoxContainer.new()
		btns.add_theme_constant_override("separation", 8)
		box.add_child(btns)
		for spec in [["چت", Color("#5b3fd6"), 0], ["هدیه", Color("#ffb300"), 1], ["تماس", Color("#1f8a55"), 2], ["حذف", Color("#a83255"), 3]]:
			var b := Button.new()
			b.text = spec[0]
			_sbtn(b, spec[1])
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var k: int = spec[2]
			b.pressed.connect(func(): _friend_action(k, nm))
			btns.add_child(b)
		_card(flist, box)


func _friend_action(k: int, nm: String) -> void:
	match k:
		0: _open_thread(nm)
		1: _gift_dialog(nm)
		2: _call_start(nm)
		3:
			await Api.soc_remove(nm)
			_show_threads()


func _popup(title: String) -> VBoxContainer:
	var old := get_node_or_null("Popup")
	if old:
		old.name = "PopupOld"
		old.queue_free()
	var dim := ColorRect.new()
	dim.name = "Popup"
	dim.color = Color(0, 0, 0, 0.75)
	dim.size = size
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	var c := _card(dim, v)
	c.position = Vector2(40, 380)
	c.size = Vector2(size.x - 80, 10)
	v.add_child(_label(title, 28))
	return v


func _close_popup() -> void:
	var p := get_node_or_null("Popup")
	if p:
		p.name = "PopupOld"
		p.queue_free()


func _gift_dialog(nm: String) -> void:
	var v := _popup("هدیه‌ی سکه به " + nm)
	var amt := LineEdit.new()
	amt.placeholder_text = "تعداد سکه (۱ تا ۵۰۰۰)"
	amt.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_sinput(amt)
	v.add_child(amt)
	var msg := _label("", 22)
	msg.modulate = Color("#ffd166")
	v.add_child(msg)
	var ok := Button.new()
	ok.text = "ارسال هدیه"
	_sbtn(ok, Color("#ffb300"))
	ok.pressed.connect(func():
		var n := int(amt.text.strip_edges())
		if n < 1 or n > 5000:
			msg.text = "عدد بین ۱ تا ۵۰۰۰ بنویس."
			return
		var r: Dictionary = await Api.soc_gift(nm, n)
		if r.ok:
			_close_popup()
			_set_status("%d سکه برای %s فرستاده شد." % [n, nm])
		else:
			msg.text = _err(r, "ارسال نشد.")
	)
	v.add_child(ok)
	var cn := Button.new()
	cn.text = "انصراف"
	_sbtn(cn, Color("#3a2a7a"))
	cn.pressed.connect(_close_popup)
	v.add_child(cn)


var call_id := 0
var call_active := false


func _call_start(nm: String) -> void:
	if not call_unlocked:
		var v := _popup("تماس صوتی قفل است")
		v.add_child(_label("باز کردن یک‌بار ۱۰۰۰ سکه. هر دقیقه تماس ۱۰ سکه از تماس‌گیرنده کم می‌شود.", 22))
		var ok := Button.new()
		ok.text = "باز کردن با ۱۰۰۰ سکه"
		_sbtn(ok, Color("#1f8a55"))
		ok.pressed.connect(func():
			var r: Dictionary = await Api.soc_call_unlock()
			if r.ok:
				call_unlocked = true
				_close_popup()
				_call_start(nm)
			else:
				_set_status(_err(r, "باز نشد."))
				_close_popup()
		)
		v.add_child(ok)
		var cn := Button.new()
		cn.text = "انصراف"
		_sbtn(cn, Color("#3a2a7a"))
		cn.pressed.connect(_close_popup)
		v.add_child(cn)
		return
	var r2: Dictionary = await Api.soc_call("start", {"name": nm})
	if not r2.ok:
		_set_status(_err(r2, "تماس برقرار نشد."))
		return
	call_id = int(r2.data.get("id", 0))
	call_ready = false
	_audio_start(true, r2.data.get("turn", {}))
	if audio:
		audio.mute_send = true
	_ring("back")
	_call_ui("در حال زنگ زدن به " + nm + "...", false)
	_call_loop(true)


func _call_ui(t: String, incoming: bool) -> void:
	var v := _popup(t)
	var cardp := v.get_parent() as Control
	cardp.position = Vector2(30, 160)
	cardp.size = Vector2(size.x - 60, 900)
	(v.get_child(0) as Label).add_theme_font_size_override("font_size", 40)
	(v.get_child(0) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var big := _label("00:00", 90)
	big.name = "CallTimer"
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(big)
	var cl := _label("", 30)
	cl.name = "CallCoins"
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cl.modulate = Color("#ffd166")
	v.add_child(cl)
	_call_tick_ui()
	if incoming:
		var ac := Button.new()
		ac.text = "پاسخ"
		_sbtn(ac, Color("#1f8a55"))
		ac.pressed.connect(func():
			var r: Dictionary = await Api.soc_call("accept", {"id": call_id})
			incoming_ringing = false
			if r.ok:
				_ring("")
				call_t0 = Time.get_ticks_msec()
				_audio_start(false, r.data.get("turn", {}))
				_call_ui("تماس برقرار است", false)
				_call_loop(false)
			else:
				_close_popup()
		)
		v.add_child(ac)
	var en := Button.new()
	en.text = "پایان تماس"
	_sbtn(en, Color("#a83255"))
	en.pressed.connect(func():
		call_active = false
		incoming_ringing = false
		_ring("")
		_audio_stop()
		await Api.soc_call("end", {"id": call_id})
		_close_popup()
	)
	v.add_child(en)


var call_t0 := 0
var call_ready := false
var _loop_n := 0
var call_caller := false


func _call_tick_ui() -> void:
	var p := get_node_or_null("Popup")
	if p == null:
		return
	var tl := p.find_child("CallTimer", true, false) as Label
	var cl := p.find_child("CallCoins", true, false) as Label
	if tl == null or cl == null:
		return
	var sec := 0
	if call_t0 > 0:
		sec = (Time.get_ticks_msec() - call_t0) / 1000
	tl.text = "%02d:%02d" % [sec / 60, sec % 60]
	if call_caller:
		var spent := int(ceil(sec / 60.0)) * 10 if sec > 0 else 0
		cl.text = "موجودی: %d سکه\nمصرف: ۱۰ سکه در دقیقه (تا الان %d)" % [maxi(0, friends_balance - spent), spent]
	else:
		cl.text = "هزینه‌ی تماس با تماس‌گیرنده است"
	var st := "صدا: وصل نشده"
	if audio and is_instance_valid(audio):
		st = ("صدا: وصل شد  ارسال %d دریافت %d میک %.2f تلاش %d" % [audio.sent, audio.recv, audio.peak, audio.retries]) if audio.connected else ("صدا: در حال اتصال... (%d/%d)" % [audio.pc.get_connection_state(), audio.pc.get_gathering_state()])
	else:
		st = "صدا: غیرفعال"
	if audio and is_instance_valid(audio):
		st += "\nمیک: " + (str(audio.nat.recInfo()) + (" روشن" if audio.nat_on else " خاموش") if audio.nat != null else "بدون پلاگین")
	cl.text += "\n" + st


func _call_loop(is_caller: bool) -> void:
	call_active = true
	call_caller = is_caller
	if is_caller:
		call_t0 = 0
	while call_active and is_inside_tree():
		await get_tree().create_timer(1.0).timeout
		_call_tick_ui()
		if call_t0 == 0 and (not is_caller or call_ready):
			call_t0 = Time.get_ticks_msec()
		_loop_n += 1
		if _loop_n % 3 != 0 or not call_active:
			continue
		var r: Dictionary = await Api.soc_call("tick" if is_caller else "poll", {"id": call_id})
		if not call_active:
			return
		if r.ok and r.data.get("state", "") in ["active", "ended"]:
			_ring("")
			if audio and is_instance_valid(audio):
				audio.mute_send = false
			if r.data.get("state", "") == "active":
				call_ready = true
		if r.ok and r.data.get("state", "") == "ended":
			call_active = false
			_audio_stop()
			_close_popup()
			_set_status("تماس تمام شد.")


func _poll_incoming() -> void:
	while is_inside_tree():
		await get_tree().create_timer(4.0).timeout
		if not is_inside_tree() or call_active:
			continue
		if get_node_or_null("Popup"):
			if call_id > 0 and incoming_ringing:
				var pr: Dictionary = await Api.soc_call("poll", {"id": call_id})
				if pr.ok and pr.data.get("state", "") != "ringing" and incoming_ringing:
					incoming_ringing = false
					_ring("")
					_close_popup()
					_set_status("تماس از دست رفت.")
			continue
		var r: Dictionary = await Api.soc_call("incoming")
		if r.ok and r.data.get("call", null) != null:
			call_id = int(r.data.call.id)
			_ring("ring")
			incoming_ringing = true
			_call_ui("تماس از " + str(r.data.call.from), true)


var audio: Node
var incoming_ringing := false


func _audio_start(caller: bool, turn: Dictionary) -> void:
	_audio_stop()
	audio = load("res://scripts/call_audio.gd").new()
	add_child(audio)
	if not audio.start(call_id, caller, turn):
		_set_status("مکالمه‌ی صوتی روی این دستگاه پشتیبانی نمی‌شود.")
		audio.queue_free()
		audio = null


func _audio_stop() -> void:
	if audio and is_instance_valid(audio):
		audio.stop()
	audio = null


func _snd(n: String) -> void:
	var m := get_tree().current_scene
	if m and m.has_method("_play"):
		m._play(n)


func _ring(kind: String) -> void:
	var m := get_tree().current_scene
	if not m:
		return
	if kind == "":
		m.ring_stop()
	else:
		m.ring_start(kind)


func _exit_tree() -> void:
	var m := get_tree().current_scene if get_tree() else null
	if m and m.has_method("ring_stop"):
		m.ring_stop()

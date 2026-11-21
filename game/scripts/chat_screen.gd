extends Control

# صفحه‌ی چت خصوصی. همه‌ی UI در کد ساخته می‌شود تا نیازی به تغییر main.tscn نباشد.
# نام‌ها و پیام‌ها فقط از سرور می‌آیند؛ سرور همه‌ی قوانین (سکه، بلاک، محدودیت) را چک می‌کند.

const NAME_MAX := 40
const MSG_MAX := 200

var root: VBoxContainer
var status: Label
var content: VBoxContainer
var my_name := ""
var unlocked := false
var current_with := ""


func _ready() -> void:
	# والد CanvasLayer است و اندازه ندارد؛ پس اندازه را صریح می‌دهیم (علت صفحه‌ی خالی)
	var vs := get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	size = vs
	custom_minimum_size = vs
	var bg := ColorRect.new()
	bg.color = Color("#140d2b")
	bg.size = vs
	add_child(bg)
	mouse_filter = Control.MOUSE_FILTER_STOP
	root = VBoxContainer.new()
	root.position = Vector2(20, 20)
	root.size = vs - Vector2(40, 40)
	root.add_theme_constant_override("separation", 14)
	add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	var back := Button.new()
	back.text = "‹ بازگشت"
	_sbtn(back, Color("#3a2a7a"))
	back.pressed.connect(func(): queue_free())
	top.add_child(back)
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
	root.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

	_load_state()


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
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var h := float(abs(name_.hash()) % 360) / 360.0
	sb.bg_color = Color.from_hsv(h, 0.55, 0.85)
	sb.set_corner_radius_all(sz / 2)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(sz, sz)
	var l := Label.new()
	l.text = name_.substr(0, 1)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", Color.WHITE)
	p.add_child(l)
	return p


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
	input.placeholder_text = "🔍 نام بازیکن را بنویس..."
	_sinput(input)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_row.add_child(input)
	var go := Button.new()
	go.text = "جست‌وجو"
	_sbtn(go, Color("#ffb300"))
	go.add_theme_color_override("font_color", Color("#2a1f55"))
	search_row.add_child(go)
	var hdr := _label("گفتگوهای تو", 24)
	hdr.modulate = Color("#b9a8ff")
	content.add_child(hdr)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(list)
	go.pressed.connect(func(): _search(input.text.strip_edges(), list))
	input.text_submitted.connect(func(t): _search(t.strip_edges(), list))

	var r: Dictionary = await Api.chat_threads()
	if r.ok:
		var its: Array = r.data.get("items", [])
		if its.is_empty():
			_empty_note(list, "هنوز گفتگویی نداری 💬\nبالا نام یک بازیکن را جست‌وجو کن و شروع کن.")
		for it in its:
			_add_partner_button(list, str(it.get("name", "")))


func _search(q: String, list: VBoxContainer) -> void:
	if q.length() < 2:
		_set_status("حداقل ۲ حرف لازم است.")
		return
	for c in list.get_children():
		c.queue_free()
	var r: Dictionary = await Api.chat_search(q)
	if not r.ok:
		_set_status(_err(r, "جست‌وجو انجام نشد."))
		return
	_set_status("")
	var items: Array = r.data.get("items", [])
	if items.is_empty():
		_empty_note(list, "کسی با این نام پیدا نشد 😕\nنام را همان‌طور که در بازی ثبت شده بنویس.")
	for it in items:
		_add_partner_button(list, str(it.get("name", "")))


func _add_partner_button(list: VBoxContainer, partner: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(_avatar_circle(partner))
	var n := _label(partner, 28)
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(n)
	var arrow := _label("💬", 28)
	arrow.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(arrow)
	var card := _card(list, row)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
			_open_thread(partner)
	)


func _open_thread(partner: String) -> void:
	current_with = partner
	_clear()
	var top := HBoxContainer.new()
	content.add_child(top)
	var back := Button.new()
	back.text = "‹ گفتگوها"
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

	var msgs := VBoxContainer.new()
	msgs.name = "Msgs"
	msgs.add_theme_constant_override("separation", 10)
	msgs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(msgs)

	var row := HBoxContainer.new()
	content.add_child(row)
	var input := LineEdit.new()
	input.max_length = MSG_MAX
	input.placeholder_text = "پیام (حداکثر ۲۰۰ حرف، ۲ سکه)"
	_sinput(input)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	var send := Button.new()
	send.text = "ارسال ➤"
	_sbtn(send, Color("#2fbf71"))
	row.add_child(send)
	send.pressed.connect(func(): _send(input, send))
	input.text_submitted.connect(func(_t): _send(input, send))

	await _refresh_messages(msgs)


func _refresh_messages(msgs: VBoxContainer) -> void:
	var r: Dictionary = await Api.chat_messages(current_with)
	if not r.ok:
		_set_status(_err(r, "خطا در بارگذاری پیام‌ها."))
		return
	for c in msgs.get_children():
		c.queue_free()
	var items: Array = r.data.get("items", [])
	if items.is_empty():
		_empty_note(msgs, "هنوز پیامی نیست. اولین پیام را بفرست 👋")
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
			rep.text = "⚑"
			rep.flat = true
			rep.pressed.connect(func():
				var rr: Dictionary = await Api.chat_report(mid)
				_set_status("گزارش ثبت شد." if rr.ok else _err(rr, "گزارش انجام نشد."))
			)
			box.add_child(rep)
		var wrap := HBoxContainer.new()
		wrap.alignment = BoxContainer.ALIGNMENT_END if mine else BoxContainer.ALIGNMENT_BEGIN
		msgs.add_child(wrap)
		var bub := _card(wrap, box, Color("#4a35a8") if mine else Color("#2a1f55"))
		bub.size_flags_horizontal = Control.SIZE_SHRINK_END if mine else Control.SIZE_SHRINK_BEGIN


func _send(input: LineEdit, btn: Button) -> void:
	var text := input.text.strip_edges()
	if text == "":
		return
	btn.disabled = true
	var r: Dictionary = await Api.chat_send(current_with, text)
	btn.disabled = false
	if r.ok:
		input.text = ""
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

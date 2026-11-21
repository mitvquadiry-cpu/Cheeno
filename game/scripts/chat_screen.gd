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
	root = VBoxContainer.new()
	root.position = Vector2(20, 20)
	root.size = vs - Vector2(40, 40)
	root.add_theme_constant_override("separation", 14)
	add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	var back := Button.new()
	back.text = "بازگشت"
	back.pressed.connect(func(): queue_free())
	top.add_child(back)
	var title := Label.new()
	title.text = "چت خصوصی"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	top.add_child(title)

	status = Label.new()
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
	input.placeholder_text = "جست‌وجوی نام..."
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_row.add_child(input)
	var go := Button.new()
	go.text = "جست‌وجو"
	search_row.add_child(go)
	input.custom_minimum_size = Vector2(0, 64)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(list)
	go.pressed.connect(func(): _search(input.text.strip_edges(), list))
	input.text_submitted.connect(func(t): _search(t.strip_edges(), list))

	var r: Dictionary = await Api.chat_threads()
	if r.ok:
		for it in r.data.get("items", []):
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
		var l := Label.new()
		l.text = "کسی با این نام پیدا نشد."
		list.add_child(l)
	for it in items:
		_add_partner_button(list, str(it.get("name", "")))


func _add_partner_button(list: VBoxContainer, partner: String) -> void:
	var b := Button.new()
	b.text = "💬  " + partner
	b.custom_minimum_size = Vector2(0, 70)
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(func(): _open_thread(partner))
	list.add_child(b)


func _open_thread(partner: String) -> void:
	current_with = partner
	_clear()
	var top := HBoxContainer.new()
	content.add_child(top)
	var back := Button.new()
	back.text = "لیست گفتگوها"
	back.pressed.connect(func(): _show_threads())
	top.add_child(back)
	var block := Button.new()
	block.text = "بلاک"
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
	input.custom_minimum_size = Vector2(0, 64)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	var send := Button.new()
	send.text = "ارسال"
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
	for m in r.data.get("items", []):
		var mine: bool = m.get("mine", false)
		var l := _label("%s: %s" % ["تو" if mine else current_with, str(m.get("text", ""))], 22)
		var row := HBoxContainer.new()
		row.add_child(l)
		if not mine:
			var rep := Button.new()
			rep.text = "گزارش"
			var mid := int(m.get("id", 0))
			rep.pressed.connect(func():
				var rr: Dictionary = await Api.chat_report(mid)
				_set_status("گزارش ثبت شد." if rr.ok else _err(rr, "گزارش انجام نشد."))
			)
			row.add_child(rep)
		_card(msgs, row, Color("#3b2a7a") if mine else Color("#2a1f55"))


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

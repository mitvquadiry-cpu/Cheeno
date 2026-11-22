class_name PhotoCache
extends Control
# کش عکس پروفایل: نام → آدرس عکس، و آدرس → بافت دانلودشده

static var urls := {}      # name -> photo url
static var tex := {}       # url -> Texture2D
static var loading := {}   # url -> true


# از هر پاسخ سرور که آرایه‌ی آیتم‌های کاربر دارد، آدرس عکس‌ها را یاد می‌گیرد
static func learn(d: Dictionary) -> void:
	var lists: Array = []
	for k in ["items", "friends", "users"]:
		if d.get(k) is Array:
			lists.append(d[k])
	if d.get("with") is Dictionary:
		lists.append([d["with"]])
	for lst in lists:
		for it in lst:
			if it is Dictionary and str(it.get("photo", "")) != "" and it.has("name"):
				urls[str(it.name)] = str(it.photo)


static func get_tex(parent: Node, url: String) -> Texture2D:
	if url == "":
		return null
	if tex.has(url):
		return tex[url]
	if loading.has(url):
		return null
	loading[url] = true
	var h := HTTPRequest.new()
	parent.add_child(h)
	h.request(url)
	var res: Array = await h.request_completed
	h.queue_free()
	loading.erase(url)
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return null
	var body: PackedByteArray = res[3]
	var img := Image.new()
	if img.load_jpg_from_buffer(body) != OK and img.load_png_from_buffer(body) != OK and img.load_webp_from_buffer(body) != OK:
		return null
	var t := ImageTexture.create_from_image(img)
	tex[url] = t
	return t


# دایره‌ی آواتار: اگر عکس باشد نشان می‌دهد، وگرنه حرف اول نام
var nm := ""
var sz := 56.0
var tint := Color.GRAY
var pic: Texture2D


static func make(name_: String, s := 56) -> PhotoCache:
	var c := PhotoCache.new()
	c.nm = name_
	c.sz = float(s)
	c.custom_minimum_size = Vector2(s, s)
	c.tint = Color.from_hsv(float(abs(name_.hash()) % 360) / 360.0, 0.55, 0.85)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.gui_input.connect(c._tap)
	var u := str(urls.get(name_, ""))
	if u != "" and tex.has(u):
		c.pic = tex[u]
	elif u != "":
		c.call_deferred("_fetch", u)
	return c


func _fetch(u: String) -> void:
	var t: Texture2D = await PhotoCache.get_tex(self, u)
	if is_instance_valid(self) and t:
		pic = t
		queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var r := sz / 2.0
	if pic == null:
		draw_circle(c, r, tint)
		var f := ThemeDB.fallback_font
		var ch := nm.substr(0, 1)
		var fs := int(sz * 0.5)
		var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(f, Vector2(c.x - w / 2.0, c.y + fs * 0.35), ch, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color.WHITE)
		return
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for k in 48:
		var a := TAU * k / 48.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
		uvs.append(Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5))
	draw_colored_polygon(pts, Color.WHITE, uvs, pic)


func _tap(e: InputEvent) -> void:
	var hit: bool = (e is InputEventScreenTouch and not e.pressed) or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT)
	if not hit or pic == null:
		return
	accept_event()
	var layer := CanvasLayer.new()
	layer.layer = 100
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var tr := TextureRect.new()
	tr.texture = pic
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(tr)
	bg.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
			layer.queue_free())
	get_tree().root.add_child(layer)

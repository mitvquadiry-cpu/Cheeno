extends Node
const Page = preload("res://scripts/call_media_page.gd")
var bridge
var id := 0
var caller := false
var cfg := {"iceServers":[{"urls":["stun:stun.l.google.com:19302"]}]}
var state := "permission"
var live := false
var launched := false
var started := false
var timeout_at := 0
var outbound: Array = []
var sending := false
var mute_send := false:
	set(value):
		mute_send = value
		if started and live:
			_cmd({"op":"mute", "muted":value})

func start(call_id: int, is_caller: bool, turn: Dictionary) -> bool:
	if not Engine.has_singleton("CheenoPicker"):
		return false
	bridge = Engine.get_singleton("CheenoPicker")
	if not bridge.has_method("mediaStart"):
		return false
	id = call_id
	caller = is_caller
	mute_send = caller
	if turn.has("urls"):
		cfg.iceServers.append(turn)
	live = true
	timeout_at = Time.get_ticks_msec() + 30000
	if not "android.permission.RECORD_AUDIO" in OS.get_granted_permissions():
		OS.request_permission("RECORD_AUDIO")
	return true

func _cmd(msg: Dictionary) -> void:
	bridge.mediaCommand(JSON.stringify(msg))

func _process(_dt: float) -> void:
	if not live:
		return
	if not started and Time.get_ticks_msec() >= timeout_at:
		_fail()
		return
	if not launched:
		if "android.permission.RECORD_AUDIO" in OS.get_granted_permissions():
			launched = true
			state = "starting"
			bridge.mediaStart(Page.HTML)
		return
	for _i in 32:
		var raw: String = bridge.mediaPop()
		if raw.is_empty(): break
		var e = JSON.parse_string(raw)
		if not e is Dictionary: continue
		if e.has("ready"):
			_cmd({"op":"start", "caller":caller, "cfg":cfg, "muted":mute_send})
		elif e.has("started") and not started:
			started = true
			_cmd({"op":"mute", "muted":mute_send})
			_poll()
		elif e.has("signal"):
			outbound.append(e.signal)
			if not sending: _send_loop()
		elif e.has("state"):
			state = str(e.state)
			if state == "failed":
				_fail()
				return

func _send_loop() -> void:
	sending = true
	while live and not outbound.is_empty():
		var msg = outbound.pop_front()
		msg["media"] = 1
		var r: Dictionary = await Api.soc_call("sig_send", {"id":id,"data":JSON.stringify(msg)})
		if not r.ok:
			if live: _fail()
			break
	sending = false

func _poll() -> void:
	while live and is_inside_tree():
		var r: Dictionary = await Api.soc_call("sig_get", {"id":id})
		if not live or not is_inside_tree(): return
		if r.ok:
			for raw in r.data.get("items", []):
				var msg = JSON.parse_string(str(raw))
				if not msg is Dictionary: continue
				if not msg.has("media"):
					_fail()
					return
				_cmd({"op":"signal", "data":msg})
		await get_tree().create_timer(0.7 if state != "connected" else 3.0).timeout

func media_status() -> String:
	return {"permission":"در انتظار مجوز میکروفون", "failed":"صدای تماس برقرار نشد", "connected":"مسیر صوتی متصل است", "disconnected":"مسیر صوتی قطع است"}.get(state, "در حال اتصال صدا…")

func _fail() -> void:
	state = "failed"
	_release()

func _release() -> void:
	if live and launched: bridge.mediaEnd()
	live = false
	outbound.clear()

func stop() -> void:
	_release()
	queue_free()

func _exit_tree() -> void:
	_release()

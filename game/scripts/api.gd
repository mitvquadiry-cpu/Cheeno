extends Node

# کلاینت API افزونه‌ی cheeno-wallet.
# فعلاً در بازی استفاده نمی‌شود؛ برای اتصال حساب و خرید در مراحل بعد.
const BASE := "https://game.donitoo.ir/?rest_route=/cheeno/v1/"

var token := ""
const TOKEN_FILE := "user://token.txt"


func _ready() -> void:
	if FileAccess.file_exists(TOKEN_FILE):
		token = FileAccess.get_file_as_string(TOKEN_FILE).strip_edges()


func device_id() -> String:
	return OS.get_unique_id()


func _store_token() -> void:
	var f := FileAccess.open(TOKEN_FILE, FileAccess.WRITE)
	if f:
		f.store_string(token)


func logout() -> void:
	token = ""
	_store_token()


func otp_send(phone: String) -> Dictionary:
	return await _request("otp/send", HTTPClient.METHOD_POST, {"phone": phone})


func otp_verify(phone: String, code: String) -> Dictionary:
	var r := await _request("otp/verify", HTTPClient.METHOD_POST, {"phone": phone, "code": code, "device": device_id()})
	if r.ok:
		token = str(r.data.get("token", ""))
		_store_token()
	return r


func set_profile(avatar: int, name := "") -> Dictionary:
	var body := {"avatar": avatar}
	if name != "":
		body["name"] = name
	return await _request("profile", HTTPClient.METHOD_POST, body)


func login(code: String) -> Dictionary:
	var r := await _request("login", HTTPClient.METHOD_POST, {"code": code})
	if r.ok:
		token = str(r.data.get("token", ""))
	return r


func balance() -> Dictionary:
	return await _request("balance&device=%s&coins=%d" % [device_id().uri_encode(), Save.coins], HTTPClient.METHOD_GET)


func submit_score(score: int) -> Dictionary:
	return await _request("score", HTTPClient.METHOD_POST, {"score": score})


func create_order(pack: String) -> Dictionary:
	return await _request("orders", HTTPClient.METHOD_POST, {"pack": pack, "device": device_id()})


func submit_lines(lines: int) -> Dictionary:
	return await _request("lines", HTTPClient.METHOD_POST, {"lines": lines})


func redeem_code(code: String) -> Dictionary:
	return await _request("code/redeem", HTTPClient.METHOD_POST, {"code": code})


func codes_list() -> Dictionary:
	return await _request("admin/codes", HTTPClient.METHOD_GET)


func codes_create(alias: String) -> Dictionary:
	return await _request("admin/codes/create", HTTPClient.METHOD_POST, {"alias": alias})


func daily() -> Dictionary:
	return await _request("daily", HTTPClient.METHOD_POST)


func leaderboard() -> Dictionary:
	return await _request("leaderboard", HTTPClient.METHOD_GET)


func equip(kind: String, id: int) -> Dictionary:
	return await _request("equip", HTTPClient.METHOD_POST, {"kind": kind, "id": id})


func spend(amount: int, reason: String) -> Dictionary:
	return await _request("spend", HTTPClient.METHOD_POST, {"amount": amount, "reason": reason})


# ---------- چت خصوصی ----------

func chat_state() -> Dictionary:
	return await _request("chat/state", HTTPClient.METHOD_GET)


func chat_set_name(name: String) -> Dictionary:
	return await _request("chat/name", HTTPClient.METHOD_POST, {"name": name})


func chat_unlock() -> Dictionary:
	return await _request("chat/unlock", HTTPClient.METHOD_POST)


func chat_search(q: String) -> Dictionary:
	return await _request("chat/search&q=%s" % q.uri_encode(), HTTPClient.METHOD_GET)


func chat_threads() -> Dictionary:
	return await _request("chat/threads", HTTPClient.METHOD_GET)


func chat_messages(with_name: String) -> Dictionary:
	return await _request("chat/messages&with=%s" % with_name.uri_encode(), HTTPClient.METHOD_GET)


func chat_send(to_name: String, text: String) -> Dictionary:
	return await _request("chat/send", HTTPClient.METHOD_POST, {"to": to_name, "text": text})


func chat_block(with_name: String, on: bool) -> Dictionary:
	return await _request("chat/block", HTTPClient.METHOD_POST, {"with": with_name, "on": on})


func chat_report(message_id: int) -> Dictionary:
	return await _request("chat/report", HTTPClient.METHOD_POST, {"id": message_id})


func _request(path: String, method: int, body: Dictionary = {}) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)

	var headers := ["Content-Type: application/json"]
	if token != "":
		headers.append("Authorization: Bearer " + token)

	var payload := "" if method == HTTPClient.METHOD_GET else JSON.stringify(body)
	var err := http.request(BASE + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		return {"ok": false, "code": 0, "data": {}}

	var res: Array = await http.request_completed
	http.queue_free()

	var code: int = res[1]
	var parsed = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	return {"ok": code >= 200 and code < 300, "code": code, "data": data}


func chat_clear(with_name: String = "") -> Dictionary:
	return await _request("chat/clear", HTTPClient.METHOD_POST, {"with": with_name})


# --- دوستان / هدیه / تماس ---
func soc_find(q: String) -> Dictionary:
	return await _request("social/find&q=%s" % q.uri_encode(), HTTPClient.METHOD_GET)

func soc_friends() -> Dictionary:
	return await _request("social/friends", HTTPClient.METHOD_GET)

func soc_add(name: String) -> Dictionary:
	return await _request("social/add", HTTPClient.METHOD_POST, {"name": name})

func soc_remove(name: String) -> Dictionary:
	return await _request("social/remove", HTTPClient.METHOD_POST, {"name": name})

func soc_gift(name: String, amount: int) -> Dictionary:
	return await _request("social/gift", HTTPClient.METHOD_POST, {"name": name, "amount": amount})

func soc_call_unlock() -> Dictionary:
	return await _request("social/call_unlock", HTTPClient.METHOD_POST, {})

func soc_call(action: String, data: Dictionary = {}) -> Dictionary:
	data["action"] = action
	return await _request("social/call", HTTPClient.METHOD_POST, data)


func chat_unread() -> Dictionary:
	return await _request("chat/unread", HTTPClient.METHOD_GET)


func admin_grant(target: String, amount: int, note: String) -> Dictionary:
	return await _request("admin/grant", HTTPClient.METHOD_POST, {"target": target, "amount": amount, "note": note})

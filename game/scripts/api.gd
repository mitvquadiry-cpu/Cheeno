extends Node

# کلاینت API افزونه‌ی cheeno-wallet.
# فعلاً در بازی استفاده نمی‌شود؛ برای اتصال حساب و خرید در مراحل بعد.
const BASE := "https://game.donitoo.ir/?rest_route=/cheeno/v1/"

var token := ""


func login(code: String) -> Dictionary:
	var r := await _request("login", HTTPClient.METHOD_POST, {"code": code})
	if r.ok:
		token = str(r.data.get("token", ""))
	return r


func balance() -> Dictionary:
	return await _request("balance", HTTPClient.METHOD_GET)


func spend(amount: int, reason: String) -> Dictionary:
	return await _request("spend", HTTPClient.METHOD_POST, {"amount": amount, "reason": reason})


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

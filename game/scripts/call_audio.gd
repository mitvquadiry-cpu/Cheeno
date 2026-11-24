extends Node
# انتقال صدا با WebRTC DataChannel (بدون ترک صوتی؛ PCM16 در 16kHz)
const RATE := 16000
const CHUNK := 640
var pc: WebRTCPeerConnection
var ch: WebRTCDataChannel
var call_id := 0
var is_caller := false
var running := false
var connected := false
var cap: AudioEffectCapture
var mic: AudioStreamPlayer
var out: AudioStreamPlayer
var gen: AudioStreamGeneratorPlayback
var mute_send := false
var sendbuf := PackedFloat32Array()
var phase := 0.0
var mic_fixed := false
var _chk := 0.0
var _dead := 0.0
var retries := 0
var nat = null
var nat_play := false
var nat_try := 0
var nat_on := false
var sent := 0
var recv := 0
var peak := 0.0
signal failed


var diag_source := "default"
var diag_local_relay := 0
var diag_remote_relay := 0
var diag_sdp := "-"
var diag_errors := 0
var diag_first := "-"
var diag_last := "-"
var was_open := false
var opens := 0
var losses := 0
var loss_snapshot := "-"
var pc_before := -1

func _remember_loss(before: int, after: int, channel: int, pending: int) -> void:
	if loss_snapshot != "-":
		return
	var states := ["new", "connecting", "connected", "disconnected", "failed", "closed"]
	var channels := ["connecting", "open", "closing", "closed"]
	loss_snapshot = "%s>%s %s Q:%d" % [states[before] if before >= 0 and before < states.size() else str(before), states[after] if after >= 0 and after < states.size() else str(after), channels[channel] if channel >= 0 and channel < channels.size() else str(channel), pending]
var rx_peak := 0
var native_calls := 0
var gen_ok := 0
var dropped := 0
var tx_fail := 0

func _track_channel(is_open: bool) -> void:
	if is_open != was_open:
		if is_open:
			opens += 1
		else:
			losses += 1
		was_open = is_open

func _record_error(op: String, code: int) -> void:
	diag_errors += 1
	diag_last = "%s:%d" % [op, code]
	if diag_errors == 1:
		diag_first = diag_last

func diagnostic() -> String:
	return "TURN: %s | relay L/R: %d/%d\nSDP: %s | errors: %d | channel: %s" % [diag_source, diag_local_relay, diag_remote_relay, diag_sdp, diag_errors, "open" if ch.get_ready_state() == WebRTCDataChannel.STATE_OPEN else "not open"] + "\nfirst: %s | last: %s" % [diag_first, diag_last] + "\nopen/lost %d/%d | TX ok/fail %d/%d\nRX peak %d | out N/G/drop %d/%d/%d" % [opens, losses, sent, tx_fail, rx_peak, native_calls, gen_ok, dropped] + "\nLoss: " + loss_snapshot

func start(id: int, caller: bool, turn: Dictionary = {}) -> bool:
	call_id = id
	is_caller = caller
	if OS.get_name() == "Android":
		OS.request_permissions()
	pc = WebRTCPeerConnection.new()
	var cfg := {"iceServers": [{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]},
		{"urls": ["turn:openrelay.metered.ca:80", "turn:openrelay.metered.ca:443", "turn:openrelay.metered.ca:443?transport=tcp"], "username": "openrelayproject", "credential": "openrelayproject"}]}
	if turn.has("urls") and turn.has("username") and turn.has("credential"):
		cfg.iceServers[1] = turn
		diag_source = "WP"
	if pc.initialize(cfg) != OK:
		return false
	ch = pc.create_data_channel("a", {"negotiated": true, "id": 1, "ordered": false, "maxRetransmits": 0})
	if ch == null:
		return false
	pc.session_description_created.connect(func(t: String, sdp: String):
		var err := pc.set_local_description(t, sdp)
		if err != OK:
			_record_error("localSDP", err)
		_send({"k": "sd", "t": t, "s": sdp}))
	pc.ice_candidate_created.connect(func(m: String, i: int, n: String):
		if " typ relay " in (n + " "):
			diag_local_relay += 1
		_send({"k": "ic", "m": m, "i": i, "n": n}))
	if OS.get_name() == "Android" and Engine.has_singleton("CheenoPicker"):
		var pk = Engine.get_singleton("CheenoPicker")
		nat = pk
	_setup_audio()
	running = true
	if caller:
		var err := pc.create_offer()
		if err != OK:
			_record_error("offer", err)
	_sig_loop()
	return true


func _setup_audio() -> void:
	var bi := AudioServer.get_bus_index("CallMic")
	if bi < 0:
		AudioServer.add_bus()
		bi = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, "CallMic")
		cap = AudioEffectCapture.new()
		AudioServer.add_bus_effect(bi, cap)
		var am := AudioEffectAmplify.new()
		am.volume_db = 0.0
		AudioServer.add_bus_effect(bi, am)
	else:
		cap = AudioServer.get_bus_effect(bi, 0)
	if nat == null:
		mic = AudioStreamPlayer.new()
		mic.stream = AudioStreamMicrophone.new()
		mic.bus = "CallMic"
		add_child(mic)
		mic.play()
	_setup_out()


func _setup_out() -> void:
	out = AudioStreamPlayer.new()
	var g := AudioStreamGenerator.new()
	g.mix_rate = RATE
	g.buffer_length = 0.4
	out.stream = g
	add_child(out)
	out.play()
	gen = out.get_stream_playback()


func _send(d: Dictionary) -> void:
	var result: Dictionary = await Api.soc_call("sig_send", {"id": call_id, "data": JSON.stringify(d)})
	if not result.ok:
		_record_error("sendICE" if d.k == "ic" else "sendSDP", int(result.get("code", 0)))


var remote_sdp_ready := false
var early_ice: Array[Dictionary] = []

func _add_remote_ice(d: Dictionary) -> void:
	var err := pc.add_ice_candidate(d.m, int(d.i), d.n)
	if err != OK:
		_record_error("addRelay" if " typ relay " in (str(d.n) + " ") else "addICE", err)

func _sig_loop() -> void:
	while running and is_inside_tree():
		var r: Dictionary = await Api.soc_call("sig_get", {"id": call_id})
		if r.ok:
			for it in r.data.get("items", []):
				var d = JSON.parse_string(str(it))
				if d is Dictionary:
					if d.k == "sd":
						diag_sdp = str(d.t) if d.t in ["offer", "answer"] else "other"
						var err := pc.set_remote_description(d.t, d.s)
						if err != OK:
							_record_error("remoteSDP", err)
						else:
							remote_sdp_ready = true
							for candidate in early_ice:
								_add_remote_ice(candidate)
							early_ice.clear()
					elif d.k == "ic":
						if " typ relay " in (str(d.n) + " "):
							diag_remote_relay += 1
						if remote_sdp_ready:
							_add_remote_ice(d)
						elif early_ice.size() < 128:
							early_ice.append(d)
						else:
							_record_error("iceQueueFull", ERR_OUT_OF_MEMORY)
		else:
			_record_error("sigGet", int(r.get("code", 0)))
		await get_tree().create_timer(0.7 if not connected else 3.0).timeout


func _process(_dt: float) -> void:
	if not running or pc == null:
		return
	pc.poll()
	if nat != null and not nat_on:
		_chk += _dt
		if _chk > 1.0:
			_chk = 0.0
			if OS.get_name() != "Android" or "android.permission.RECORD_AUDIO" in OS.get_granted_permissions():
				nat_on = bool(nat.recStart())
	if not mic_fixed and nat == null:
		_chk += _dt
		if _chk > 1.0:
			_chk = 0.0
			if OS.get_name() != "Android" or "android.permission.RECORD_AUDIO" in OS.get_granted_permissions():
				mic_fixed = true
				mic.stop()
				mic.play()
	var channel_state := ch.get_ready_state()
	var pc_now := pc.get_connection_state()
	if was_open and channel_state != WebRTCDataChannel.STATE_OPEN and loss_snapshot == "-":
		_remember_loss(pc_before, pc_now, channel_state, ch.get_available_packet_count())
	pc_before = pc_now
	_track_channel(channel_state == WebRTCDataChannel.STATE_OPEN)
	if not was_open:
		return
	connected = true
	# ارسال
	if nat != null and nat_on:
		var b64 := str(nat.recRead())
		var raw: PackedByteArray = Marshalls.base64_to_raw(b64) if b64 != "" else PackedByteArray()
		for i in raw.size() / 2:
			var fv := float(raw.decode_s16(i * 2)) / 32768.0
			peak = maxf(peak, absf(fv))
			sendbuf.append(fv)
	var step := float(AudioServer.get_mix_rate()) / RATE
	var frames := PackedVector2Array()
	if nat == null:
		frames = cap.get_buffer(cap.get_frames_available())
	for f in frames:
		peak = maxf(peak, absf(f.x))
		phase += 1.0
		if phase >= step:
			phase -= step
			sendbuf.append((f.x + f.y) * 0.5)
	while sendbuf.size() >= CHUNK:
		var pcm := PackedByteArray()
		pcm.resize(CHUNK * 2)
		for i in CHUNK:
			pcm.encode_s16(i * 2, int(clampf(sendbuf[i] * 1.5, -1.0, 1.0) * 32767.0))
		sendbuf = sendbuf.slice(CHUNK)
		if not mute_send:
			var result := ch.put_packet(pcm)
			if result == OK:
				sent += 1
			else:
				tx_fail += 1
				_record_error("sendPCM", result)
	# دریافت
	while ch.get_available_packet_count() > 0:
		var pk := ch.get_packet()
		recv += 1
		var n := pk.size() / 2
		for i in n:
			rx_peak = maxi(rx_peak, absi(pk.decode_s16(i * 2)))
		if nat != null and nat_on and not nat_play and nat_try < 5:
			nat_try += 1
			nat_play = bool(nat.playStart())
		if nat_play:
			nat.playWrite(Marshalls.raw_to_base64(pk))
			native_calls += 1
			continue
		if gen.get_frames_available() < n:
			dropped += 1
			continue
		var all_ok := n > 0
		for i in n:
			var v := float(pk.decode_s16(i * 2)) / 32768.0
			if not gen.push_frame(Vector2(v, v)):
				all_ok = false
		if all_ok:
			gen_ok += 1
		else:
			dropped += 1


func _exit_tree() -> void:
	if nat != null:
		nat.playStop()
		nat.recStop()


func stop() -> void:
	running = false
	if nat != null:
		nat.playStop()
		nat.recStop()
	if mic:
		mic.stop()
		mic.stream = null
		remove_child(mic)
		mic.queue_free()
		mic = null
	var bi := AudioServer.get_bus_index("CallMic")
	if bi >= 0:
		AudioServer.remove_bus(bi)
	cap = null
	if out:
		out.stop()
	if ch:
		ch.close()
	if pc:
		pc.close()
	queue_free()

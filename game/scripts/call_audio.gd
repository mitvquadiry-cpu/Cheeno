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
var sendbuf := PackedFloat32Array()
var phase := 0.0
var mic_fixed := false
var _chk := 0.0
var sent := 0
var recv := 0
var peak := 0.0
signal failed


func start(id: int, caller: bool) -> bool:
	call_id = id
	is_caller = caller
	if OS.get_name() == "Android":
		OS.request_permissions()
	pc = WebRTCPeerConnection.new()
	var cfg := {"iceServers": [{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]},
		{"urls": ["turn:openrelay.metered.ca:80", "turn:openrelay.metered.ca:443", "turn:openrelay.metered.ca:443?transport=tcp"], "username": "openrelayproject", "credential": "openrelayproject"}]}
	if pc.initialize(cfg) != OK:
		return false
	ch = pc.create_data_channel("a", {"negotiated": true, "id": 1, "ordered": false, "maxRetransmits": 0})
	if ch == null:
		return false
	pc.session_description_created.connect(func(t: String, sdp: String):
		pc.set_local_description(t, sdp)
		_send({"k": "sd", "t": t, "s": sdp}))
	pc.ice_candidate_created.connect(func(m: String, i: int, n: String):
		_send({"k": "ic", "m": m, "i": i, "n": n}))
	_setup_audio()
	running = true
	if caller:
		pc.create_offer()
	_sig_loop()
	return true


func _setup_audio() -> void:
	var bi := AudioServer.get_bus_index("CallMic")
	if bi < 0:
		AudioServer.add_bus()
		bi = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, "CallMic")
		AudioServer.set_bus_volume_db(bi, -80.0)
		cap = AudioEffectCapture.new()
		AudioServer.add_bus_effect(bi, cap)
	else:
		cap = AudioServer.get_bus_effect(bi, 0)
	mic = AudioStreamPlayer.new()
	mic.stream = AudioStreamMicrophone.new()
	mic.bus = "CallMic"
	add_child(mic)
	mic.play()
	out = AudioStreamPlayer.new()
	var g := AudioStreamGenerator.new()
	g.mix_rate = RATE
	g.buffer_length = 0.4
	out.stream = g
	add_child(out)
	out.play()
	gen = out.get_stream_playback()


func _send(d: Dictionary) -> void:
	Api.soc_call("sig_send", {"id": call_id, "data": JSON.stringify(d)})


func _sig_loop() -> void:
	while running and is_inside_tree():
		var r: Dictionary = await Api.soc_call("sig_get", {"id": call_id})
		if r.ok:
			for it in r.data.get("items", []):
				var d = JSON.parse_string(str(it))
				if d is Dictionary:
					if d.k == "sd":
						pc.set_remote_description(d.t, d.s)
					elif d.k == "ic":
						pc.add_ice_candidate(d.m, int(d.i), d.n)
		await get_tree().create_timer(0.7 if not connected else 3.0).timeout


func _process(_dt: float) -> void:
	if not running or pc == null:
		return
	pc.poll()
	if not mic_fixed:
		_chk += _dt
		if _chk > 1.0:
			_chk = 0.0
			if OS.get_name() != "Android" or "android.permission.RECORD_AUDIO" in OS.get_granted_permissions():
				mic_fixed = true
				mic.stop()
				mic.play()
	if ch.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return
	connected = true
	# ارسال
	var step := float(AudioServer.get_mix_rate()) / RATE
	var frames := cap.get_buffer(cap.get_frames_available())
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
		ch.put_packet(pcm)
		sent += 1
	# دریافت
	while ch.get_available_packet_count() > 0:
		var pk := ch.get_packet()
		recv += 1
		var n := pk.size() / 2
		if gen.get_frames_available() < n:
			continue
		for i in n:
			var v := float(pk.decode_s16(i * 2)) / 32768.0
			gen.push_frame(Vector2(v, v))


func stop() -> void:
	running = false
	if ch:
		ch.close()
	if pc:
		pc.close()
	queue_free()

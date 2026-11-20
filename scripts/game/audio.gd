# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends Node
## Dźwięk (autoload „Audio”): muzyka z przenikaniem, pętle ambientu, efekty z pulą odtwarzaczy, głośność szyn.
## Pliki: res://assets/audio/{music,ambient,sfx}/<id>.wav; warianty efektu jako <id>_1.wav, <id>_2.wav…
## Brak pliku = cisza (gra działa bez audio).

const DIR := "res://assets/audio/"
const BUSES := ["Music", "Ambient", "SFX", "Voice"]
const DEFAULT_VOLUME := {"Master": 0.9, "Music": 0.55, "Ambient": 0.5, "SFX": 0.8, "Voice": 0.9}
const VOICE_DUCK_DB := -7.0            # muzyka i ambient ciszej, kiedy ktoś mówi
const SETTINGS := "user://settings.cfg"
const SFX_POOL := 12

var _music: Array[AudioStreamPlayer] = []
var _music_cur := 0
var _music_id := ""
var _ambient: Dictionary = {}          # id -> AudioStreamPlayer
var _sfx: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _variants := {}                    # id -> Array[AudioStream]
var _rng := RandomNumberGenerator.new()
var _log := "--audiolog" in OS.get_cmdline_user_args()   # debug: wypisuje każde wywołanie
var _voice: AudioStreamPlayer
var _duck: Tween
var tts_fallback := false              # synteza mowy systemu, gdy węzeł nie ma nagrania (ustawienie)
var voice_lang := "en"                 # język nagrań głosów; tekst w grze może być w innym (napisy)
var narrator := true                   # narrator czyta opisy w dialogach (ustawienie)
var control_companions := true         # w walce gracz steruje towarzyszami (ustawienie; wyłączone = AI)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, b)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		_music.append(p)
	for i in SFX_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx.append(p)
	_voice = AudioStreamPlayer.new()
	_voice.bus = "Voice"
	_voice.finished.connect(_on_voice_finished)
	add_child(_voice)
	_setup_voice_analyzer()
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_STARTED, _on_tts_started)
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, _on_tts_ended)
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED, _on_tts_ended)
	_load_settings()


# ------------------------------------------------------------------ ładowanie

func _stream(path: String, loop: bool) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStream = load(path)
	if s == null:
		push_error("Audio: %s istnieje, ale nie da się go wczytać" % path)
		return null
	if loop and s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	return s


func _sfx_variants(id_: String) -> Array:
	if _variants.has(id_):
		return _variants[id_]
	var out := []
	var one := _stream(DIR + "sfx/%s.wav" % id_, false)
	if one:
		out.append(one)
	for i in range(1, 9):
		var s := _stream(DIR + "sfx/%s_%d.wav" % [id_, i], false)
		if s == null:
			break
		out.append(s)
	_variants[id_] = out
	return out


# ------------------------------------------------------------------ muzyka i ambient

## Przenika do utworu (pętla, jeśli loop). Ten sam utwór nie zaczyna się od nowa.
func play_music(id_: String, fade := 1.5, loop := true) -> void:
	if id_ == _music_id:
		return
	if _log:
		print("AUDIO music ", id_)
	_music_id = id_
	var old := _music[_music_cur]
	_music_cur = 1 - _music_cur
	var nxt := _music[_music_cur]
	var s := _stream(DIR + "music/%s.wav" % id_, loop) if id_ != "" else null
	if old.playing:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -60.0, fade)
		tw.tween_callback(old.stop)
	if s:
		nxt.stream = s
		nxt.volume_db = -60.0
		nxt.play()
		create_tween().tween_property(nxt, "volume_db", 0.0, fade)


func stop_music(fade := 1.5) -> void:
	play_music("", fade)


## Zatrzymuje również wybrzmiewające efekty przed zamknięciem silnika.
func stop_for_exit() -> void:
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null


## Ustawia zestaw pętli ambientu (np. ["market", "wind_planar"]); reszta wycisza się.
func set_ambient(ids: Array, fade := 2.0) -> void:
	for id_ in _ambient.keys():
		if not id_ in ids:
			var p: AudioStreamPlayer = _ambient[id_]
			_ambient.erase(id_)
			var tw := create_tween()
			tw.tween_property(p, "volume_db", -60.0, fade)
			tw.tween_callback(p.queue_free)
	if _log:
		print("AUDIO ambient ", ids)
	for id_ in ids:
		if _ambient.has(id_):
			continue
		var s := _stream(DIR + "ambient/%s.wav" % id_, true)
		if s == null:
			continue
		var p := AudioStreamPlayer.new()
		p.bus = "Ambient"
		p.stream = s
		p.volume_db = -60.0
		add_child(p)
		p.play(_rng.randf() * s.get_length())
		create_tween().tween_property(p, "volume_db", 0.0, fade)
		_ambient[id_] = p


# ------------------------------------------------------------------ efekty

## Efekt (losowy wariant, lekka zmiana wysokości). volume_db względem szyny SFX.
func sfx(id_: String, volume_db := 0.0, pitch_var := 0.06) -> void:
	var vs := _sfx_variants(id_)
	if _log:
		print("AUDIO sfx ", id_, " (", vs.size(), " war.)")
	if vs.is_empty():
		return
	var p := _sfx[_sfx_next]
	_sfx_next = (_sfx_next + 1) % SFX_POOL
	p.stream = vs[_rng.randi() % vs.size()]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_var, pitch_var)
	p.play()


## Dźwięk czaru wg typu obrażeń / rodzaju.
func spell(sp: Dictionary) -> void:
	var id_ := "spell_generic"
	match sp.get("damage_type", ""):
		"fire": id_ = "spell_fire"
		"cold": id_ = "spell_frost"
		"force": id_ = "spell_force"
	if sp.get("type", "") == "heal":
		id_ = "spell_heal"
	elif sp.get("type", "") in ["buff", "reaction"]:
		id_ = "spell_shield"
	sfx(id_, -2.0)


# ------------------------------------------------------------------ głosy postaci i narrator

signal voice_segment(who: String)      # zaczyna się fragment: "speaker" | "narrator"
signal voice_done                      # węzeł przeczytany do końca albo urwany

var _queue: Array = []                 # pozostałe fragmenty bieżącego węzła: [{"who", "path"}]
var _speaking := ""                    # kto teraz mówi ("" = cisza)
var _tts_who := {}                     # id wypowiedzi systemowej -> who
var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _level := 0.0


## Węzeł dialogu na głos: fragmenty po kolei (narrator opisuje, postać mówi kwestie), z nagrań
## assets/audio/voice; bez nagrań (jeśli włączone) synteza systemu. Zwraca "clip", "tts" albo "" (cisza).
## Poprzedni węzeł zawsze się urywa.
func voice_line(dialogue_id: String, node_id: String, node: Dictionary) -> String:
	stop_voice()
	var queue := []
	for c in VoiceLines.clips(voice_lang, dialogue_id, node_id):
		if c.who == "speaker" or narrator:
			queue.append(c)
	if not queue.is_empty():
		_queue = queue
		_set_duck(true)
		_next_segment()
		return "clip"
	if tts_fallback and _tts_node(dialogue_id, str(node.get("text", ""))):
		return "tts"
	return ""


func _next_segment() -> void:
	while not _queue.is_empty():
		var c: Dictionary = _queue.pop_front()
		var s: AudioStream = load(c.path)
		if s == null:
			continue
		if _log:
			print("AUDIO voice ", c.path)
		_voice.stream = s
		_voice.play()
		_speaking = c.who
		voice_segment.emit(c.who)
		return
	_finish_voice()


func _on_voice_finished() -> void:
	if _queue.is_empty():
		_finish_voice()
	else:
		get_tree().create_timer(0.25).timeout.connect(func(): if _speaking != "" and not _voice.playing: _next_segment())


func _finish_voice() -> void:
	var was := _speaking != ""
	_speaking = ""
	_queue.clear()
	_unduck()
	if was:
		voice_done.emit()


func stop_voice() -> void:
	_queue.clear()
	_tts_who.clear()
	if _voice and _voice.playing:
		_voice.stop()
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH) and DisplayServer.tts_is_speaking():
		DisplayServer.tts_stop()
	_finish_voice()


func is_voice_playing() -> bool:
	return _speaking != ""


## Kto teraz mówi: "speaker", "narrator" albo "".
func speaking() -> String:
	return _speaking


## Głośność bieżącej wypowiedzi 0..1 (do ożywienia portretu).
func voice_level() -> float:
	return _level


func _process(delta: float) -> void:
	var target := 0.0
	if _spectrum and _voice and _voice.playing:
		var m := _spectrum.get_magnitude_for_frequency_range(150.0, 3500.0)
		target = clampf((linear_to_db(maxf(m.length(), 1e-6)) + 52.0) / 36.0, 0.0, 1.0)
	_level = lerpf(_level, target, 1.0 - exp(-delta * 18.0))


func _setup_voice_analyzer() -> void:
	var i := AudioServer.get_bus_index("Voice")
	if i < 0:
		return
	var fx := AudioEffectSpectrumAnalyzer.new()
	fx.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_512
	AudioServer.add_bus_effect(i, fx)
	_spectrum = AudioServer.get_bus_effect_instance(i, AudioServer.get_bus_effect_count(i) - 1)


## Synteza systemu dla całego węzła: fragmenty w kolejce, każdy głosem postaci albo narratora.
func _tts_node(dialogue_id: String, text: String) -> bool:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return false
	var cast := VoiceLines.cast()
	var any := false
	for seg in VoiceLines.segments(text):
		var prof: Dictionary
		if seg.who == "speaker" and cast.has(dialogue_id):
			prof = cast[dialogue_id]
		elif narrator:
			prof = cast.get(VoiceLines.NARRATOR, {})
		else:
			continue
		var uid := _tts_speak(seg.text, prof)
		if uid < 0:
			return any
		_tts_who[uid] = seg.who
		any = true
	if any:
		_set_duck(true)
	return any


## Systemowy głos dla języka gry, dobrany do płci postaci; wysokość i tempo z obsady. Zwraca id wypowiedzi albo -1.
var _tts_next_id := 1


func _tts_speak(text: String, prof: Dictionary) -> int:
	var voices := DisplayServer.tts_get_voices_for_language(Loc.lang)
	if voices.is_empty():
		return -1
	var want: String = str(prof.get("tts_gender", ""))
	var pick: String = voices[0]
	for v in DisplayServer.tts_get_voices():
		if v.id in voices and want != "" and want in str(v.name).to_lower():
			pick = v.id
			break
	var vol := int(round(get_volume("Voice") * get_volume("Master") * 100.0))
	var uid := _tts_next_id
	_tts_next_id += 1
	DisplayServer.tts_speak(text, pick, vol, float(prof.get("tts_pitch", 1.0)), float(prof.get("tts_rate", 1.0)), uid, false)
	return uid


func _on_tts_started(uid: int) -> void:
	if _tts_who.has(uid):
		_speaking = _tts_who[uid]
		voice_segment.emit(_speaking)


func _on_tts_ended(uid: int) -> void:
	_tts_who.erase(uid)
	if _tts_who.is_empty():
		_finish_voice()


func set_narrator(on: bool) -> void:
	narrator = on
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", "narrator", on)
	cfg.save(SETTINGS)


func _set_duck(on: bool) -> void:
	if _duck:
		_duck.kill()
	_duck = create_tween().set_parallel()
	for b in ["Music", "Ambient"]:
		var i := AudioServer.get_bus_index(b)
		if i < 0:
			continue
		if AudioServer.get_bus_effect_count(i) == 0:
			AudioServer.add_bus_effect(i, AudioEffectAmplify.new(), 0)
		var fx := AudioServer.get_bus_effect(i, 0) as AudioEffectAmplify
		if fx:
			_duck.tween_property(fx, "volume_db", VOICE_DUCK_DB if on else 0.0, 0.25 if on else 0.8)


func _unduck() -> void:
	_set_duck(false)


func set_voice_lang(l: String) -> void:
	voice_lang = l
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", "voice_lang", l)
	cfg.save(SETTINGS)


func set_tts_fallback(on: bool) -> void:
	tts_fallback = on
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", "tts_fallback", on)
	cfg.save(SETTINGS)


# ------------------------------------------------------------------ głośność

func get_volume(bus: String) -> float:
	var i := AudioServer.get_bus_index(bus)
	return db_to_linear(AudioServer.get_bus_volume_db(i)) if i >= 0 else 0.0


func set_volume(bus: String, linear: float, save := true) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(i, linear <= 0.001)
	if save:
		_save_settings()


func set_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("display", "fullscreen", on)
	cfg.save(SETTINGS)


func set_control_companions(on: bool) -> void:
	control_companions = on
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("game", "control_companions", on)
	cfg.save(SETTINGS)


func set_difficulty(id_: String) -> void:
	Difficulty.current = id_
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("game", "difficulty", id_)
	cfg.save(SETTINGS)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	Difficulty.current = str(cfg.get_value("game", "difficulty", Difficulty.GAME_DEFAULT))
	tts_fallback = bool(cfg.get_value("audio", "tts_fallback", false))
	voice_lang = str(cfg.get_value("audio", "voice_lang", "en"))
	narrator = bool(cfg.get_value("audio", "narrator", true))
	control_companions = bool(cfg.get_value("game", "control_companions", true))
	for b in DEFAULT_VOLUME.keys():
		set_volume(b, float(cfg.get_value("audio", b, DEFAULT_VOLUME[b])), false)
	if cfg.get_value("display", "fullscreen", false) and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	for b in DEFAULT_VOLUME.keys():
		cfg.set_value("audio", b, get_volume(b))
	cfg.save(SETTINGS)

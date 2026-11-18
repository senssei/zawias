extends Node
## Dźwięk (autoload „Audio”): muzyka z przenikaniem, pętle ambientu, efekty z pulą odtwarzaczy, głośność szyn.
## Pliki: res://assets/audio/{music,ambient,sfx}/<id>.wav; warianty efektu jako <id>_1.wav, <id>_2.wav…
## Brak pliku = cisza (gra działa bez audio).

const DIR := "res://assets/audio/"
const BUSES := ["Music", "Ambient", "SFX"]
const DEFAULT_VOLUME := {"Master": 0.9, "Music": 0.55, "Ambient": 0.5, "SFX": 0.8}
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

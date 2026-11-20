# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
class_name VoiceLines
extends RefCounted
## Głosy w dialogach.
##
## Tekst węzła dzieli się na fragmenty w kolejności: to, co w cudzysłowie („…” po polsku, "…"/“…” po angielsku),
## mówi postać ("speaker"), a opis wokół czyta narrator ("narrator", głos NARRATOR z obsady; można go wyłączyć).
## Nagrania: res://assets/audio/voice/<lang>/<dialog>/<węzeł>_<n>.ogg, opisane w <lang>/manifest.json
## ({"<dialog>/<węzeł>": {"segments": [{"who", "text", "file", "seconds"}]}}), generowane przez
## `tools/pipeline/pipeline.sh voice` (OmniVoice w ComfyUI) według obsady z CAST.
## Język głosów jest niezależny od języka tekstu (ustawienie, domyślnie angielski): tekst w oknie dialogu
## służy wtedy za napisy. Ta sama reguła podziału jest w tools/pipeline/comfy/comfy_voice.py
## (manifest trzyma tekst każdego fragmentu, test pilnuje zgodności z dialogami).

const DIR := "res://assets/audio/voice/"
const CAST := DIR + "voices.json"
const NARRATOR := "_narrator"

static var _cast := {}
static var _manifests := {}
static var _re: RegEx
static var _letters: RegEx


static func _quote_re() -> RegEx:
	if _re == null:
		_re = RegEx.create_from_string("[„“\"]([^„“”\"]+)[”\"]")
		_letters = RegEx.create_from_string("\\p{L}")
	return _re


static func _clean(s: String) -> String:
	s = s.replace("…", "...").strip_edges()
	while s != "" and s[0] in ".,;:—–- ":
		s = s.substr(1).strip_edges()
	return s


## Fragmenty węzła po kolei: [{"who": "speaker"|"narrator", "text"}]. Sąsiednie fragmenty tego samego
## mówiącego (np. dwie kwestie rozdzielone samym myślnikiem) łączą się w jeden.
static func segments(text: String) -> Array:
	var out := []
	var pos := 0
	var re := _quote_re()
	var parts := []
	for m in re.search_all(text):
		parts.append(["narrator", text.substr(pos, m.get_start() - pos)])
		parts.append(["speaker", m.get_string(1)])
		pos = m.get_end()
	parts.append(["narrator", text.substr(pos)])
	for p in parts:
		var s := _clean(p[1])
		if _letters.search(s) == null:
			continue
		if not out.is_empty() and out[-1].who == p[0]:
			out[-1].text += " " + s
		else:
			out.append({"who": p[0], "text": s})
	return out


## Tekst okrzyku (data/barks.json) tak, jak trafia do nagrania.
static func bark_text(text: String) -> String:
	_quote_re()
	return _clean(text)


## Sama wypowiedź postaci (bez narracji); "" gdy postać nic nie mówi na głos.
static func spoken(text: String) -> String:
	var parts := PackedStringArray()
	for s in segments(text):
		if s.who == "speaker":
			parts.append(s.text)
	return " ".join(parts)


## Obsada głosów: {dialog_id | NARRATOR: {"instruct", "ref_text", "seed", "speed", "tts_pitch", "tts_rate", "tts_gender"}}.
static func cast() -> Dictionary:
	if _cast.is_empty() and FileAccess.file_exists(CAST):
		var j = JSON.parse_string(FileAccess.get_file_as_string(CAST))
		if j is Dictionary:
			_cast = j.get("voices", {})
	return _cast


static func has_voice(dialogue_id: String) -> bool:
	return cast().has(dialogue_id)


static func manifest(lang: String) -> Dictionary:
	if not _manifests.has(lang):
		var p := DIR + lang + "/manifest.json"
		var j = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
		_manifests[lang] = j if j is Dictionary else {}
	return _manifests[lang]


static func clear_cache() -> void:
	_cast = {}
	_manifests = {}


## Języki, w których są nagrania (katalogi assets/audio/voice/<lang>/ z manifestem).
static func voice_langs() -> Array:
	var out := []
	for l in Loc.LANGS.keys():
		if FileAccess.file_exists(DIR + l + "/manifest.json"):
			out.append(l)
	return out


## Nagrania węzła w języku głosów (bez nich: w dowolnym innym): [{"who", "path", "text"}]; [] gdy brak.
static func clips(voice_lang: String, dialogue_id: String, node_id: String) -> Array:
	var order := [voice_lang]
	for l in Loc.LANGS.keys():
		if not l in order:
			order.append(l)
	for l in order:
		var entry: Dictionary = manifest(l).get("%s/%s" % [dialogue_id, node_id], {})
		var out := []
		for s in entry.get("segments", []):
			var p := DIR + "%s/%s/%s" % [l, dialogue_id, s.file]
			if ResourceLoader.exists(p):
				out.append({"who": s.who, "path": p, "text": s.text})
		if not out.is_empty():
			return out
	return []

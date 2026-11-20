# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends Node
## Język gry (autoload „Loc”). Polski jest językiem źródłowym: napisy w kodzie i danych są po polsku,
## a tłumaczenie to nakładka:
##   i18n/<lang>/ui.json    – napisy z kodu: {"tekst polski": "tłumaczenie"}; kod woła Loc.t("tekst polski"),
##                            a te same pary trafiają do TranslationServer (kontrolki z dokładnym tekstem tłumaczą się same);
##   i18n/<lang>/data.json  – dane i dialogi: {"spells:fire_bolt/name": "Fire Bolt", "dialogues/mirela:nodes/start/text": "..."}.
## Brak tłumaczenia = tekst polski. Wybór: --lang=en, zmienna ZAWIAS_LANG, ustawienie [game] language w user://settings.cfg,
## domyślnie język systemu (pl → polski, inaczej angielski).

const LANGS := {"pl": "Polski", "en": "English"}
const SETTINGS := "user://settings.cfg"

var lang := "pl"
var _ui := {}
var _data := {}
var _translation: Translation


func _init() -> void:
	var l := "pl" if OS.get_locale_language() == "pl" else "en"
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		l = str(cfg.get_value("game", "language", l))
	if OS.get_environment("ZAWIAS_LANG") != "":   # np. testy: ZAWIAS_LANG=pl (run_tests.sh)
		l = OS.get_environment("ZAWIAS_LANG")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			l = a.substr(7)
	set_lang(l, false)


## Przełącza język. save=true zapisuje wybór. Dane z DB trzeba wczytać od nowa (DB.clear_cache()).
func set_lang(l: String, save := true) -> void:
	lang = l if LANGS.has(l) else "pl"
	_ui = _read("res://i18n/%s/ui.json" % lang) if lang != "pl" else {}
	_data = _read("res://i18n/%s/data.json" % lang) if lang != "pl" else {}
	if _translation:
		TranslationServer.remove_translation(_translation)
		_translation = null
	if lang != "pl":
		_translation = Translation.new()
		_translation.locale = lang
		for k in _ui.keys():
			_translation.add_message(k, _ui[k])
		TranslationServer.add_translation(_translation)
	TranslationServer.set_locale(lang)
	if save:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS)
		cfg.set_value("game", "language", lang)
		cfg.save(SETTINGS)


## Napis z kodu w bieżącym języku.
func t(s: String) -> String:
	return _ui.get(s, s) if lang != "pl" else s


## Nakłada tłumaczenia na wczytany plik danych (klucz = ścieżka pliku względem data/, bez .json).
func apply_data(file_key: String, d: Variant) -> void:
	if _data.is_empty():
		return
	var prefix := file_key + ":"
	for k in _data.keys():
		if k.begins_with(prefix):
			_set_path(d, k.substr(prefix.length()).split("/"), _data[k])


func _set_path(node: Variant, parts: PackedStringArray, value: String) -> void:
	for i in parts.size():
		var p := parts[i]
		var last := i == parts.size() - 1
		if node is Dictionary:
			if not node.has(p):
				return
			if last:
				if node[p] is String:
					node[p] = value
				return
			node = node[p]
		elif node is Array:
			var idx := int(p)
			if idx < 0 or idx >= node.size():
				return
			if last:
				if node[idx] is String:
					node[idx] = value
				return
			node = node[idx]
		else:
			return


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var j = JSON.parse_string(FileAccess.get_file_as_string(path))
	return j if j is Dictionary else {}

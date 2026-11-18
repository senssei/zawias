extends GutTest
## Tłumaczenie angielskie: pokrycie napisów z kodu, zgodność znaczników formatu i BBCode, poprawność nakładki danych.

const LANG := "en"


func after_all():
	Loc.set_lang("pl", false)
	DB.clear_cache()


func _json(path: String) -> Dictionary:
	var j = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(j is Dictionary, path + " to poprawny JSON")
	return j if j is Dictionary else {}


## Napisy przekazywane w kodzie do Loc.t("...") (dosłowne literały).
func _code_strings() -> Array:
	var re := RegEx.create_from_string('Loc\\.t\\("((?:[^"\\\\]|\\\\.)*)"\\)')
	var out := []
	var dirs := ["res://scripts/"]
	while not dirs.is_empty():
		var d: String = dirs.pop_back()
		for sub in DirAccess.get_directories_at(d):
			dirs.append(d + sub + "/")
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd") and f != "loc.gd":
				for m in re.search_all(FileAccess.get_file_as_string(d + f)):
					var s := m.get_string(1).c_unescape()
					if not s in out:
						out.append(s)
	return out


func _placeholders(s: String) -> Array:
	var re := RegEx.create_from_string("%[-+0-9.]*[sdf%]")
	return re.search_all(s).map(func(m): return m.get_string())


func _tags(s: String) -> Array:
	var re := RegEx.create_from_string("\\[/?[a-z_]+(=[^\\]]*)?\\]")
	var t := re.search_all(s).map(func(m): return m.get_string())
	t.sort()
	return t


func test_every_code_string_translated():
	var ui := _json("res://i18n/%s/ui.json" % LANG)
	var missing := []
	for s in _code_strings():
		if not ui.has(s):
			missing.append(s)
	assert_eq(missing, [], "napisy bez tłumaczenia w i18n/%s/ui.json" % LANG)


func test_placeholders_and_bbcode_match():
	var ui := _json("res://i18n/%s/ui.json" % LANG)
	for k in ui.keys():
		assert_eq(_placeholders(ui[k]), _placeholders(k), "znaczniki formatu: " + k)
		assert_eq(_tags(ui[k]), _tags(k), "BBCode: " + k)


func test_data_overlay_paths_exist_and_apply():
	var data := _json("res://i18n/%s/data.json" % LANG)
	assert_gt(data.size(), 400)
	Loc.set_lang(LANG, false)
	DB.clear_cache()
	for k in data.keys():
		var file_key: String = k.split(":")[0]
		var path: PackedStringArray = k.substr(file_key.length() + 1).split("/")
		var node: Variant = DB.table(file_key)
		for p in path:
			node = node.get(p) if node is Dictionary else (node[int(p)] if node is Array and int(p) < node.size() else null)
			if node == null:
				break
		assert_eq(node, data[k], "nakładka %s" % k)
	assert_eq(DB.entry("spells", "fire_bolt").name, "Fire Bolt")
	assert_eq(Loc.t("Nowa gra"), "New Game")
	Loc.set_lang("pl", false)
	DB.clear_cache()
	assert_eq(DB.entry("spells", "fire_bolt").name, "Ognisty pocisk", "powrót do polskiego")

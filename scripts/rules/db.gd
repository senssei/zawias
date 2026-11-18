class_name DB
extends RefCounted
## Statyczny dostęp do danych JSON w res://data. Liczby z JSON są float: rzutuj na int.

static var _cache := {}


static func table(table_name: String) -> Dictionary:
	if not _cache.has(table_name):
		_cache[table_name] = _load("res://data/%s.json" % table_name)
		var loc = Engine.get_main_loop().root.get_node_or_null("Loc") if Engine.get_main_loop() is SceneTree else null   # notr
		if loc:
			loc.apply_data(table_name, _cache[table_name])   # tłumaczenie (nakładka i18n/<lang>/data.json)
	return _cache[table_name]


## Po zmianie języka: dane wczytają się od nowa z nową nakładką.
static func clear_cache() -> void:
	_cache.clear()


static func entry(table_name: String, id: String) -> Dictionary:
	return table(table_name).get(id, {})


static func dialogue(id: String) -> Dictionary:
	return table("dialogues/" + id)


static func map(id: String) -> Dictionary:
	return table("maps/" + id)


static func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Brak pliku danych: " + path)
		return {}
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		push_error("Błąd JSON w %s (linia %d): %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	return json.data if json.data is Dictionary else {}

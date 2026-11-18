class_name Dice
extends RefCounted
## Kości: rzuty, wyrażenia "2d6+3", przewaga/utrudnienie.
## RNG jest globalny i seedowalny; testy mogą wymusić konkretne wyniki przez force().

static var rng := RandomNumberGenerator.new()
static var _forced: Array[int] = []


static func seed_rng(s: int) -> void:
	rng.seed = s


## Kolejne rzuty zwrócą podane wartości (do testów).
static func force(values: Array) -> void:
	_forced.clear()
	for v in values:
		_forced.append(int(v))


static func clear_forced() -> void:
	_forced.clear()


static func roll_die(sides: int) -> int:
	if not _forced.is_empty():
		return _forced.pop_front()
	return rng.randi_range(1, sides)


static func roll(count: int, sides: int) -> Array[int]:
	var out: Array[int] = []
	for i in count:
		out.append(roll_die(sides))
	return out


## mode: 1 = przewaga, -1 = utrudnienie, 0 = zwykły rzut
static func d20(mode: int = 0) -> Dictionary:
	var a := roll_die(20)
	if mode == 0:
		return {"natural": a, "rolls": [a]}
	var b := roll_die(20)
	var nat := maxi(a, b) if mode > 0 else mini(a, b)
	return {"natural": nat, "rolls": [a, b]}


static func combine_mode(adv: bool, dis: bool) -> int:
	if adv and not dis:
		return 1
	if dis and not adv:
		return -1
	return 0


static func parse(expr: String) -> Dictionary:
	var e := expr.replace(" ", "").to_lower()
	if e.is_valid_int():
		return {"count": 0, "sides": 0, "bonus": e.to_int()}
	var re := RegEx.create_from_string("^(\\d*)d(\\d+)([+-]\\d+)?$")
	var m := re.search(e)
	if m == null:
		push_error("Niepoprawne wyrażenie kości: " + expr)
		return {"count": 0, "sides": 0, "bonus": 0}
	var c := 1 if m.get_string(1) == "" else m.get_string(1).to_int()
	var b := m.get_string(3).to_int() if m.get_string(3) != "" else 0
	return {"count": c, "sides": m.get_string(2).to_int(), "bonus": b}


## dice_mult = 2 przy trafieniu krytycznym (podwaja kości, nie premię).
static func roll_expr(expr: String, dice_mult: int = 1) -> Dictionary:
	var p := parse(expr)
	var rolls := roll(int(p.count) * dice_mult, int(p.sides))
	var t := int(p.bonus)
	for r in rolls:
		t += r
	return {"total": t, "rolls": rolls, "bonus": int(p.bonus)}


static func average(expr: String) -> int:
	var p := parse(expr)
	return int(floor(int(p.count) * (int(p.sides) + 1) / 2.0)) + int(p.bonus)

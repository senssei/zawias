class_name CharacterBuilder
extends RefCounted
## Tworzy postać gracza z wyborów kreatora oraz potwory z monsters.json.


## opts: name, species, background, class, scores (bazowe), bonus {cecha: +n},
##       skills [], expertise [], extra_skill, choice (styl walki / porządek)
static func build(opts: Dictionary) -> Creature:
	var c := Creature.new()
	c.id = "player"
	c.kind = "pc"
	c.team = "party"
	c.is_player = true
	c.name = opts.get("name", Loc.t("Bezimienny"))
	c.species_id = opts.species
	c.background_id = opts.background
	c.class_id = opts["class"]

	var base: Dictionary = opts.get("scores", {})
	for ab in Abilities.LIST:
		c.scores[ab] = int(base.get(ab, 10))
	var bonus: Dictionary = opts.get("bonus", {})
	for ab in bonus.keys():
		c.scores[ab] = mini(20, int(c.scores[ab]) + int(bonus[ab]))

	var sp := DB.entry("species", c.species_id)
	c.speed = int(sp.get("speed", 30))
	c.darkvision = int(sp.get("darkvision", 0))
	c.resistances = sp.get("resistances", []).duplicate()
	c.tags = sp.get("tags", []).duplicate()
	_add_all(c.features, sp.get("features", []))
	_add_all(c.skill_profs, sp.get("skills", []))
	for cid in sp.get("cantrips", []):
		_add(c.cantrips, cid)
		c.spell_ability_overrides[cid] = sp.get("cantrip_ability", "int")
	if c.has_feature("resourceful"):
		c.heroic_inspiration = true

	var bg := DB.entry("backgrounds", c.background_id)
	_add_all(c.skill_profs, bg.get("skills", []))
	_add(c.features, bg.get("feat", ""))
	for cid in bg.get("feat_cantrips", []):
		_add(c.cantrips, cid)
		if not c.spell_ability_overrides.has(cid):
			c.spell_ability_overrides[cid] = bg.get("feat_ability", "int")

	var cls := DB.entry("classes", c.class_id)
	c.hit_die = int(cls.hit_die)
	c.save_profs = cls.saves.duplicate()
	c.armor_profs = cls.get("armor", []).duplicate()
	c.weapon_profs = cls.get("weapons", []).duplicate()
	_add_all(c.skill_profs, opts.get("skills", []))
	if opts.get("extra_skill", "") != "":
		_add(c.skill_profs, opts.extra_skill)
	if int(cls.get("expertise_count", 0)) > 0:
		var exp: Array = opts.get("expertise", [])
		if exp.is_empty():
			exp = c.skill_profs.slice(-int(cls.expertise_count))
		c.expertise = exp.slice(0, int(cls.expertise_count))
	c.spell_ability = cls.get("spellcasting", "")
	_add_all(c.cantrips, cls.get("cantrips", []))
	_add_all(c.spells, cls.get("spells", []))

	var st: Dictionary = cls.get("starting", {})
	c.armor_id = st.get("armor", "")
	c.shield = st.get("shield", false)
	c.weapons = st.get("weapons", []).duplicate()
	c.inventory = st.get("items", []).duplicate()
	c.gold = int(st.get("gold", 0)) + int(bg.get("gold", 0))
	var mc := int(cls.get("mastery_count", 0))
	for w in c.weapons:
		if c.mastery.size() >= mc:
			break
		if DB.entry("weapons", w).get("mastery", "") != "":
			c.mastery.append(w)

	if cls.has("choice"):
		var ch: Dictionary = cls.choice
		var pick: String = opts.get("choice", ch.options.keys()[0])
		c.choices[ch.id] = pick
		if pick == "protector":
			_add(c.armor_profs, "heavy")
			_add(c.weapon_profs, "martial")
			c.armor_id = "chain_mail"
		elif pick == "thaumaturge":
			_add(c.cantrips, "light")

	Leveling.grant_level(c, 1)
	c.xp = 0
	return c


static func create_monster(monster_id: String, instance_id: String, display_name: String = "") -> Creature:
	var m := DB.entry("monsters", monster_id)
	var c := Creature.new()
	c.id = instance_id
	c.kind = "monster"
	c.team = "enemy"
	c.template_id = monster_id
	c.name = display_name if display_name != "" else m.get("name", monster_id)
	for ab in Abilities.LIST:
		c.scores[ab] = int(m.get("scores", {}).get(ab, 10))
	c.monster_ac = int(m.get("ac", 10))
	c.max_hp = Difficulty.monster_hp(Dice.average(m.get("hp", "1d8")))
	c.hp = c.max_hp
	c.speed = int(m.get("speed", 30))
	c.save_profs = m.get("saves", []).duplicate()
	c.resistances = m.get("resistances", []).duplicate()
	c.vulnerabilities = m.get("vulnerabilities", []).duplicate()
	c.immunities = m.get("immunities", []).duplicate()
	c.condition_immunities = m.get("condition_immunities", []).duplicate()
	c.tags = m.get("tags", []).duplicate()
	c.monster_attacks = m.get("attacks", []).duplicate(true)
	c.multiattack = int(m.get("multiattack", 1))
	c.xp_value = int(m.get("xp", 0))
	c.choices["pb"] = int(m.get("pb", 2))
	return c


static func _add(arr: Array, v) -> void:
	if v != "" and v != null and not v in arr:
		arr.append(v)


static func _add_all(arr: Array, vals: Array) -> void:
	for v in vals:
		_add(arr, v)

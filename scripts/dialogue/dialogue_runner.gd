# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
class_name DialogueRunner
extends RefCounted
## Graf dialogowy z JSON: węzły, wybory z warunkami, testy umiejętności i efekty.
##
## Format: {"start": "id", "nodes": {"id": {"speaker", "text", "effects": [], "choices": [
##   {"text", "next", "if": {...}, "effects": [], "once": bool,
##    "check": {"skill"|"ability", "dc", "success", "fail"}, "end": true}
## ]}}}
## Węzeł może mieć "redirect": [{"if": {...}, "next": "id"}] i wtedy przekierowuje automatycznie.

signal node_shown(node: Dictionary, choices: Array)
signal check_rolled(text: String, success: bool, natural: int)
signal finished

var data := {}
var dialogue_id := ""
var current_id := ""
var state: Node   # GameState
var used_once := {}


func _init(gs: Node = null) -> void:
	state = gs


func start(id: String, gs: Node = null) -> bool:
	if gs:
		state = gs
	dialogue_id = id
	data = DB.dialogue(id)
	if data.is_empty():
		return false
	var start_id: String = data.get("start", "start")
	for alt in data.get("starts", []):
		if state.check(alt.get("if", {})):
			start_id = alt.next
			break
	goto(start_id)
	return true


func goto(node_id: String) -> void:
	if node_id == "" or node_id == "end":
		finished.emit()
		return
	var node: Dictionary = data.nodes.get(node_id, {})
	if node.is_empty():
		push_error("Dialog %s: brak węzła %s" % [dialogue_id, node_id])
		finished.emit()
		return
	for r in node.get("redirect", []):
		if state.check(r.get("if", {})):
			goto(r.next)
			return
	current_id = node_id
	state.apply_effects(node.get("effects", []))
	node_shown.emit(node, visible_choices())


func current_node() -> Dictionary:
	return data.get("nodes", {}).get(current_id, {})


func _once_key(i: int) -> String:
	return "dlg_%s_%s_%d" % [dialogue_id, current_id, i]


## Lista widocznych wyborów: [{index, text, choice}]
func visible_choices() -> Array:
	var out := []
	var node := current_node()
	var choices: Array = node.get("choices", [])
	for i in choices.size():
		var ch: Dictionary = choices[i]
		if not state.check(ch.get("if", {})):
			continue
		if ch.get("once", false) and state.has_flag(_once_key(i)):
			continue
		out.append({"index": i, "text": choice_label(ch), "choice": ch})
	if out.is_empty():
		out.append({"index": -1, "text": Loc.t("[Odejdź]"), "choice": {"end": true}})
	return out


func choice_label(ch: Dictionary) -> String:
	var t: String = ch.get("text", "...")
	if ch.has("check"):
		var chk: Dictionary = ch.check
		var name: String = Loc.t(str(Abilities.SKILL_NAMES.get(chk.get("skill", ""), Abilities.NAMES.get(chk.get("ability", ""), "?"))))
		t = Loc.t("[%s, ST %d] %s") % [name, int(chk.dc), t]
	return t


func choose(index: int) -> void:
	if index < 0:
		finished.emit()
		return
	var node := current_node()
	var ch: Dictionary = node.choices[index]
	if ch.get("once", false):
		state.flags[_once_key(index)] = true
	state.apply_effects(ch.get("effects", []))
	if ch.has("check"):
		var res := roll_check(ch.check)
		check_rolled.emit(res.text, res.success, int(res.natural))
		state.apply_effects(ch.check.get("success_effects" if res.success else "fail_effects", []))
		goto(ch.check.success if res.success else ch.check.fail)
		return
	if ch.get("end", false) or not ch.has("next"):
		finished.emit()
		return
	goto(ch.next)


## Test z automatycznym użyciem Heroicznej inspiracji przy porażce.
func roll_check(chk: Dictionary) -> Dictionary:
	var pc: Creature = state.player
	var dc := int(chk.dc)
	var adv := false
	if chk.has("adv_if") and state.check(chk.adv_if):
		adv = true
	var res: Dictionary
	if chk.has("skill"):
		res = Checks.skill_check(pc, chk.skill, dc, adv)
	else:
		res = Checks.ability_check(pc, chk.ability, dc, adv)
	var text: String = res.text
	if not res.success and pc.heroic_inspiration:
		pc.heroic_inspiration = false
		var res2: Dictionary
		if chk.has("skill"):
			res2 = Checks.skill_check(pc, chk.skill, dc, adv)
		else:
			res2 = Checks.ability_check(pc, chk.ability, dc, adv)
		text += Loc.t("\n  Heroiczna inspiracja, przerzut: ") + res2.text
		res = res2
	res.text = text
	return res

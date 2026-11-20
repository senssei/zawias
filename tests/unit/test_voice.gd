# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends GutTest
## Głosy: podział tekstu na narratora i kwestie postaci, obsada, kolejka fragmentów w grze,
## zgodność nagrań z bieżącym tekstem dialogów.


func after_all():
	Loc.set_lang("pl", false)
	DB.clear_cache()


func _segs(text: String) -> Array:
	return VoiceLines.segments(text).map(func(s): return [s.who, s.text])


func test_segments_split_narration_and_speech_in_order():
	assert_eq(_segs("Kobieta przekłada klucze. „Nie kupujesz? To nie zawracaj mi…”"),
		[["narrator", "Kobieta przekłada klucze."], ["speaker", "Nie kupujesz? To nie zawracaj mi..."]])
	assert_eq(_segs("„Nie”. Pióro znów skrzypi. „Dziesięć sztuk albo do widzenia”."),
		[["speaker", "Nie"], ["narrator", "Pióro znów skrzypi."], ["speaker", "Dziesięć sztuk albo do widzenia"]])
	assert_eq(_segs("She smiles. \"Fine.\" — “Go.”"), [["narrator", "She smiles."], ["speaker", "Fine. Go."]],
		"kwestie rozdzielone samym myślnikiem łączą się")
	assert_eq(_segs("Mirela nawet na ciebie nie patrzy."), [["narrator", "Mirela nawet na ciebie nie patrzy."]])
	assert_eq(VoiceLines.spoken("A. „B”. C. „D”"), "B D")


func test_cast_matches_dialogues():
	var cast := VoiceLines.cast()
	assert_true(cast.has(VoiceLines.NARRATOR), "głos narratora w obsadzie")
	for did in cast.keys():
		if did != VoiceLines.NARRATOR:
			assert_false(DB.dialogue(did).is_empty(), "głos %s ma dialog" % did)
		for k in ["instruct", "ref_text", "seed"]:
			assert_true(cast[did].has(k), "%s.%s" % [did, k])


func test_voice_line_without_recording_is_silent():
	var au: Node = get_tree().root.get_node("Audio")
	var was: bool = au.tts_fallback
	au.tts_fallback = false
	assert_eq(au.voice_line("mirela", "_brak_", {"text": "„Halo”"}), "", "brak nagrania i syntezy = cisza")
	au.tts_fallback = was


func test_voice_queue_plays_segments_and_narrator_toggle():
	if VoiceLines.voice_langs().is_empty():
		pending("brak nagrań (tools/pipeline/pipeline.sh voice)")
		return
	var au: Node = get_tree().root.get_node("Audio")
	var clips := VoiceLines.clips("en", "mirela", "start")
	assert_gt(clips.size(), 0, "mirela/start ma nagrania")
	var whos := clips.map(func(c): return c.who)
	var started := []
	var cb := func(who): started.append(who)
	au.voice_segment.connect(cb)
	var was: bool = au.narrator
	au.narrator = true
	var node: Dictionary = DB.dialogue("mirela").nodes.start   # tekst po polsku, głos angielski = napisy
	assert_eq(au.voice_line("mirela", "start", node), "clip")
	assert_true(au.is_voice_playing())
	assert_eq(started, [whos[0]], "pierwszy fragment: " + str(whos[0]))
	au.stop_voice()
	assert_false(au.is_voice_playing(), "urwane")
	if "narrator" in whos and "speaker" in whos:
		started.clear()
		au.narrator = false
		au.voice_line("mirela", "start", node)
		assert_eq(started, ["speaker"], "bez narratora od razu kwestia postaci")
		au.stop_voice()
	au.narrator = was
	au.voice_segment.disconnect(cb)


## Każdy fragment w manifeście istnieje i ma dokładnie bieżący tekst węzła (inaczej: pipeline.sh voice).
func test_recordings_match_current_text():
	var checked := 0
	for lang in Loc.LANGS.keys():
		var man: Dictionary = VoiceLines.manifest(lang)
		if man.is_empty():
			continue
		Loc.set_lang(lang, false)
		DB.clear_cache()
		for key in man.keys():
			var parts: PackedStringArray = key.split("/")
			var want: Array
			if parts[0] == "barks":
				var npc := parts[1].substr(0, parts[1].rfind("_"))
				var items: Array = DB.table("barks").get(npc, [])
				var bi := int(parts[1].substr(parts[1].rfind("_") + 1))
				assert_lt(bi, items.size(), "%s: okrzyk istnieje" % key)
				want = [{"who": "speaker", "text": VoiceLines.bark_text(str(items[bi].text))}] if bi < items.size() else []
			else:
				var node: Dictionary = DB.dialogue(parts[0]).get("nodes", {}).get(parts[1], {})
				assert_false(node.is_empty(), "%s: węzeł istnieje" % key)
				want = VoiceLines.segments(str(node.get("text", "")))
			for rec in man[key].segments:
				var i := int(str(rec.file).get_basename().get_slice("_", str(rec.file).get_basename().get_slice_count("_") - 1))
				assert_lt(i, want.size(), "%s: fragment %s istnieje w tekście" % [key, rec.file])
				if i < want.size():
					assert_eq([rec.who, rec.text], [want[i].who, want[i].text],
						"%s/%s [%s]: tekst aktualny (tools/pipeline/pipeline.sh voice --lang %s)" % [key, rec.file, lang, lang])
				assert_true(ResourceLoader.exists(VoiceLines.DIR + "%s/%s/%s" % [lang, parts[0], rec.file]), "%s: plik %s" % [key, rec.file])
				checked += 1
	Loc.set_lang("pl", false)
	DB.clear_cache()
	gut.p("sprawdzone fragmenty: %d" % checked)
	assert_true(true)

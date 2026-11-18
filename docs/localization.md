# Localization

Polish is the source language: strings in code and data are written in Polish, and translations are overlays.
The game ships Polish and English. Players switch language in **Settings → Language**. The default follows the
system locale (Polish system → Polish, anything else → English); `--lang=en` and the `ZAWIAS_LANG` environment
variable override it.

## Code strings: `i18n/<lang>/ui.json`

Every visible string in code is wrapped: `Loc.t("Nowa gra")`. The file maps the Polish source to the translation:

```json
{ "Nowa gra": "New Game", "%s atakuje %s (%s): k20 %s %s%s = %d vs KP %d%s": "%s attacks %s (%s): d20 %s %s%s = %d vs AC %d%s" }
```

Format placeholders (`%s`, `%d`) must keep their order and count; BBCode tags must match (`test_i18n` checks both).
The same pairs are registered with Godot's `TranslationServer`, so a control whose text equals a source string is
translated even if the code forgot `Loc.t()`.

Constant tables (ability and skill names, damage types, action names, quest stages, difficulty presets) stay in
Polish in code and are translated where they are displayed: `Loc.t(str(Abilities.SKILL_NAMES[sk]))`.

## Data strings: `i18n/<lang>/data.json`

A flat map from a JSON path to the translation, applied by `DB` when a file is loaded:

```json
{
  "spells:fire_bolt/name": "Fire Bolt",
  "dialogues/mirela:nodes/start/choices/0/text": "What happened?"
}
```

The key is `<file under data/, without .json>:<path>`, path segments are dictionary keys or array indices.
Missing keys fall back to Polish (proper names like Mirela or Sever don't need entries).

## Tools

```bash
python3 tools/i18n/extract.py                        # strings in code that look translatable
python3 tools/i18n/wrap.py --dry-run                 # wrap them in Loc.t(); skips constants, defaults, debug lines
python3 tools/i18n/extract_data.py                   # all translatable data strings as a flat map
python3 tools/i18n/extract_data.py --missing i18n/en/data.json   # only the ones not translated yet
```

Mark a line with `# notr` to keep `wrap.py` away from it (node names, theme types, identifiers).

## Adding a language

1. Add it to `Loc.LANGS` (`scripts/game/loc.gd`), e.g. `"de": "Deutsch"`.
2. Create `i18n/de/ui.json` (copy the English keys) and `i18n/de/data.json` (from `extract_data.py`).
3. Point `test_i18n.gd` at the new language (or loop over `Loc.LANGS`) and run the tests.
4. The credits text has a per-language constant in `scripts/ui/main_menu.gd`.

## Conventions used in English

SRD 5.2 terminology (Hit Points, Armor Class, Difficulty Class, Weapon Mastery, Heroic Inspiration).
Distances stay in meters, as in the Polish rules text and the HUD. Place names are translated
(Rusty Market, Unravelers, Inscribed, Doorless Arch); the city keeps its name, Zawias.

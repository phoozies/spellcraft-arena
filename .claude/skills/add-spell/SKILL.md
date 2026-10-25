---
name: add-spell
description: Process for adding or tuning a spell in Spellcraft Arena (SpellDefinitions row, glyph, balance budgets, registry entry, model, particles, pose, sounds). Use when asked to add, rebalance, or restyle a spell.
---

# Adding or tuning a spell

Spells are **data**; behaviour comes from an archetype. The long version is `docs/SPELLS.md` ("Adding a spell"); this is the checklist.

1. **Definition.** Add a row to `src/shared/Spells/SpellDefinitions.luau`: unique `id`, `element`, `slot`, `role`, its `glyph` (`Glyphs.ROLE[role]`), plain-word `aliases`, `sfx` cue names (from `src/shared/Audio/Cues.luau`), `archetype`, `cooldown`, `stats`, and a primitive `visual`. Every spell needs one distinct glyph and an element can't repeat a shape, so if none is free add a role and a glyph in `Glyphs.luau` and `GlyphRecognizer.luau`. Add the id to its element's list in `Spells/Elements.luau`, or make it a crate spell with a rarity.
2. **New behaviour?** Do not add a code path per spell. Add a new optional stat that an archetype in `src/server/Services/Archetypes/` reads, and document it in `docs/SPELLS.md` ("Stats the spells read") and `Types.luau`.
3. **Look and feel.** Add an entry to `src/shared/Spells/SpellRegistry.luau` (model, particle style in `Spells/VfxStyles`, cast pose from `Spells/CastPoses`, sounds). Models come from `tools/blender/block_models.py`: regenerate `Models/BlockModels.luau` (never hand-edit it), name the model in `visual.model`, and keep a plain-shape fallback. Then run `python tools/gen-spell-registry.py` to refresh `docs/semantic/spell_registry.yaml`.
4. **Balance.** Budgets live in `tests/Balance.spec.luau` (no one-shots, ultimates at least 15s cooldown and 30+ damage, timed buffs at most 60% uptime, ...). Aliases must be unique (`tests/WordMatcher.spec.luau`) and glyphs distinct (`tests/Glyphs.spec.luau`).
5. **Run the tests** (`test-in-studio`). They fail for alias collisions, repeated shapes, wrong cue names, balance breaks, or a missing registry entry.
6. **Docs.** Spell table in `docs/SPELLS.md`, `docs/semantic/features.yaml` if a feature changed, then `CHANGELOG.md` (`ship-change`).

Tunables stay out of systems: spell numbers in `SpellDefinitions`, odds in `Spells/Rarity`, element prices in `Spells/Elements`, the crate price in `Economy/Crates`.

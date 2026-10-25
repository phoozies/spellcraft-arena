# Classes (planned, NOT built)

> **Status: design note only.** Nothing in the game implements classes yet. This file records what has been decided so far, so the element system built today doesn't get in the way of adding them later.

## What exists today: elements

Every player equips **one element** (Fire, Water, Earth, or Air). An element is five spells, each drawn with a shape that depends on its kind of move (a circle for a basic attack, a slash for a fast attack, and so on; see [SPELLS.md](SPELLS.md)). The first element is a free pick; the other three are unlocked with **Element Crates**.

Classes are meant to sit **on top of** elements, not replace them.

## What we know about classes

- They are a **second choice layered on the equipped element** (element + class), as the design brief says: "an element + class system".
- The reference game's **Variants** screen (a "Fire Variants" panel with an *Evolution Quest*) is the closest thing we've seen: each element has variants that you unlock by completing a quest, and you equip one. That is **inspiration, not a decision**.
- They must not break the one-shape-per-spell draw system, the server-authoritative rules, or the balance budgets (`tests/Balance.spec.luau`).

## Open questions (to decide before building)

1. What is a class: a passive/role bonus (tank, assassin, support), a set of spell modifiers, or a replacement for one or more spell slots?
2. How are classes earned: quests, coins, crates, level-like progression (there is none today), or a free pick per element?
3. Is there one class per element or classes shared across elements? Can a player mix any class with any owned element?
4. Do classes change anything in matches only (like boosts), or in the hub too?
5. What are the classes? (The brief says "make a note of the classes", but doesn't list them yet.)

## Where classes would plug in

| Piece | Where it would go |
|---|---|
| Which class a player has | `profile.class` next to `profile.element` (a schema bump in `PlayerDataService`) |
| Owning/equipping | An `ElementService`-style owner (or an extension of it) that is the only writer |
| Effects on spells | Optional stats read by archetypes, or a multiplier like the match boosts (`BoostService`) |
| UI | A tab or row in the Spellbook panel (`MenuController`) |
| Tests | A spec like `tests/Economy.spec.luau`, plus new rows in `tests/Balance.spec.luau` |

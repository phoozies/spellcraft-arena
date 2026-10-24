# Imported 3D models

Source FBX files for the game's hand-made models, plus how they get from here
into the game.

| File | Used for | Mesh parts (imported as MeshParts) |
|---|---|---|
| `Fireball.fbx` | The **Fireball** bolt (also the Dragon's fireballs) | `Fireball_Core`, `Fireball_Outer`, `Fireball_Tail` |
| `WaterBubble.fbx` | The **Water Lock** bolt, and the bubble around a trapped player | `Bubble_Shell`, `Bubble_Inner`, `Bubble_Highlight` |
| `RockWall.fbx` | The **Rock Wall** ("earth wall") spell | `Wall_Base`, `Wall_Pillars`, `Wall_Rubble` |
| `Arena.fbx` | The hub's **sparring arena** around the Sparring Ring | `Arena_Floor`, `Arena_Pillars`, `Arena_RuneRing`, `Arena_Seating` |
| `Grimoire.fbx` | Not used yet (stored coloured, ready for the Spellbook kiosk) | `Grimoire_Cover`, `Grimoire_Gold`, `Grimoire_Gem`, `Grimoire_Pages` |

## How they get into the game

The FBX files are the source of truth, but the game uses the meshes that
Studio uploaded when they were imported. Those live **in the place file**, not
in the Rojo project:

1. **Import:** Studio → Home → **Import 3D** → pick the files here → Import.
   This uploads the meshes to Roblox under the importing account. The raw
   models appear in Workspace.
2. **Prepare:** run [`tools/prepare-models.luau`](../../tools/prepare-models.luau)
   in Studio's command bar (Edit mode). It scales each model to game size
   (the FBX units are hundreds of studs), centers the pivot, applies the
   colours and materials listed in that script, sets collision, and moves the
   result to `ReplicatedStorage.Models`.
3. **Save/publish the place** so the models (and their uploaded mesh assets) go
   with it.

Imported mesh asset ids (from the first import, for reference):

| Model | Part | MeshId |
|---|---|---|
| Fireball | Core / Outer / Tail | `96606848412415` / `76924214785582` / `122924746151253` |
| WaterBubble | Shell / Inner / Highlight | `95513654066435` / `126316603893062` / `96514476796602` |
| Arena | Floor / Pillars / RuneRing / Seating | `104722144999525` / `132023013253762` / `105655736544333` / `132545857906199` |
| Grimoire | Cover / Gem / Gold / Pages | `84817276487006` / `102534698956698` / `134590942603150` / `87995336138237` |

(RockWall's ids are in the place; read them from `ReplicatedStorage.Models.RockWall`.)

## In code

`src/shared/ModelKit.luau` reads `ReplicatedStorage.Models`. Because the models
are in the place and not the project, a place built by CI (`rojo build`) won't
have them, so **every use has a fallback to plain shapes**:

- Fireball / Water Lock bolts: `FxController` (`BOLT_MODELS`) draws the model, else a plain shape.
- Water Lock's trap bubble: `server/Services/TrapBubble.luau`, else a glass orb.
- Rock Wall: `Archetypes/Placeable.luau` builds from the model (each mesh part is its own breakable chunk), else a block grid.
- Sparring arena: `HubService.placeSparringArena` swaps in the model, else the red mat and corner posts stay.

To change a colour, edit `tools/prepare-models.luau` and re-import and prepare,
or edit the part in `ReplicatedStorage.Models` directly (then update the script
to match so the repo stays the record of the look).

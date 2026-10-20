# Platform Racing 2 Client

This repository is the Haxe/OpenFL port of the Platform Racing 2 Flash client.
The current migration source is the extracted Adobe Animate XFL under
`flash/platform-racing-2-xfl/`. Normal development should build from committed
Haxe/OpenFL source and committed generated assets, without requiring Adobe
Animate.

## License
Art: Rights belong to credited artits, otherwise https://creativecommons.org/licenses/by-nc/4.0/
Music: Rights belong to credited artists
Code: MIT

## Quick Start

For classic/mobile release builds and the dual-UI development preview, see
[UI configurations and migration status](docs/ui-implementation.md).

Run the browser build from the repository root:

```sh
haxelib run openfl test html5
```

The client boots into the intro screens by default. A `?screen=` flag selects
the boot screen so development and automated tests can jump straight to one:

- `?screen=intro` (default): Jiggmin and Kongregate intro flow, then login.
  - `?intro=jiggmin` or `?intro=kongregate` plays just that one intro (testing).
- `?screen=login`: the (stub) login page.
- `?screen=campaign&debug=campaign`: debug-only campaign harness. Loads a real
  campaign level through the configured API host/proxy, renders the decoded block
  layer, and places the character at the first start block. Accepts `page` and
  `levelId` (or `level`) to choose a listed campaign level.
  - `&localLevel=<name>` instead builds a synthetic level entirely client-side
    (no server fetch) and mounts it in the same `Course`/`ServerLevelRenderer`
    path — the offline gameplay sandbox. Layouts: `rotate` (a boxed-in room with
    a rotate block over the spawn) and `flat` (a wide open floor).
- `?screen=symbol&symbol=<name>&scale=4&bg=FFFFFF`: renders one generated
  library symbol through the vector renderer for visual comparison work.

`IntroPage` publishes its progress to the `data-pr2-intro-state` body attribute
(`intro-jiggmin`, `intro-kongregate`, `login`) for harness observation.

Build without launching:

```sh
haxelib run openfl build html5
```

Run the lightweight runtime tests:

```sh
./test.sh
./test.sh real-server
```

The deterministic suite runs one representative test from every test class by
default. Run `./test.sh --full` to execute every deterministic test.

Run complete tests for one or more related domains by passing flags; multiple
flags select their union:

```sh
./test.sh --physics --blocks
./test.sh --level-rendering
./test.sh --lobby --items
./test.sh --level-editor
```

Use `./test.sh --help` to list every domain flag.

Run the complete local verification gate (deterministic and protocol tests,
HTML5 build, and required character parity sequences):

```sh
tools/test_all.sh
```

Per-stage logs are written to `test/output/test-all/`; parity screenshots are
written to `test/output/`.

Capture the maintained character parity matrix (default transitions/both
facings, recolors, mixed parts/items, tricky silhouettes, all hats, Fred in all
states, effect attachments, and live Djinn ice pixels) after an HTML5 build:

```sh
for case in default colors mixed-parts tricky-parts all-hats fred-states attachments djinn-ice; do python3 tools/openfl_driver.py sequence test/sequences/openfl/character-$case.json; done
```

The exhaustive paged matrices render all 141 standard parts and all 38 authored
held-item frames without fitting hundreds of characters into one unreadable image:

```sh
python3 tools/openfl_driver.py sequence test/sequences/openfl/character-all-parts.json
python3 tools/openfl_driver.py sequence test/sequences/openfl/character-all-items.json
```

Local server/API overrides can live in ignored shell env files. On sys targets,
set `PR2_API_HOST` to point API calls at a proxy or local endpoint:

```sh
PR2_API_HOST=/api haxe test/real-server.hxml
```

## Project Layout

- `project.xml`: OpenFL project file.
- `haxe/src/`: Haxe/OpenFL source.
- `haxe/test/`: Haxe test entry points.
- `assets/`: OpenFL app assets.
- `flash/platform-racing-2-xfl/`: extracted Animate/XFL migration source.
- `tools/`: asset extraction, generation, rasterization, and harness helpers.
- `art/svg/`: SVG exports from Animate.
- `art/png/timeline/`: generated PNG fallbacks for timeline artwork whose SVG
  features OpenFL cannot render directly.
- `docs/`: migration notes and inventories.
- `docs/browser-platform-differences.md`: audited, platform-required HTML5
  differences and their parity boundaries.
- `docs/deflash-symbol-inventory.md`: generated inventory of the production
  `PR2MovieClip` root symbols, grouped by feature owner and native replacement
  shape; regenerate it with `tools/generate_deflash_symbol_inventory.py`.
- `docs/deflash-coupling-inventory.md`: generated deletion ledger of handwritten
  timeline navigation, name lookup, `Fl*` control, reflection, and legacy
  dependency sites, grouped by migration owner.
- `TODO.md`: current porting plan and next steps.

## Porting Status

The port targets a faithful Haxe/OpenFL browser build of the original Flash
client: 550x400 stage, 30 FPS timing, Flash-compatible gameplay behavior, and
visual parity measured by deterministic state and screenshot comparisons. Normal
development and CI should use committed Haxe/OpenFL source and generated assets;
Adobe Animate is only a migration tool for regenerating source assets.

Current foundation:

- Production presentation is made from typed native views, controls, rigs, and
  explicitly referenced SVG/bitmap/audio assets. The HTML5 bundle does not
  include the XFL symbol catalog, `PR2MovieClip`, or the `Fl*` compatibility
  controls.
- Generated XFL catalogs and the old timeline player remain archival migration
  inputs only. Production code cannot import them; the post-build compatibility
  gate checks both Haxe source and the minified JavaScript bundle.
- The `?screen=campaign&localLevel=<name>` sandbox can run synthetic levels
  without login/lobby/server flow and exposes deterministic debug state for
  movement checks.

### Native Presentation Architecture

Runtime linkage lookup has been replaced by explicitly constructed, typed
views. New production presentation code follows this shape:

Legacy migration input:

```haxe
art = PR2MovieClip.fromLinkage("SomePopupGraphic");
nameBox = LobbyArt.text(art, "nameBox");
button = DisplayUtil.findByName(art, "ok_bt");
```

Production:

```haxe
class ConfirmDialogView extends Sprite {
    public final message:TextField;
    public final confirmButton:GameButton;
    public final cancelButton:GameButton;

    public function new() {
        super();
        // Explicit construction and layout.
    }
}
```

This is a code-structure and asset-pipeline change only; visuals and behavior
must remain unchanged. The native conventions are documented in
[`docs/native-presentation-foundation.md`](docs/native-presentation-foundation.md)
and the first production-slice rules in
[`docs/deflash-native-conventions.md`](docs/deflash-native-conventions.md).

## Haxe/OpenFL Commands

### Pinned Native Toolchain

The repository currently uses Haxe 4.3.7, OpenFL 9.5.2, Lime 8.3.2, and the
official hxcpp `v4.3.146` GitHub release. Do not use hxcpp 4.3.2 from Haxelib
for Android builds: it can produce an application that packages successfully
but fails at startup because `__atomic_compare_exchange_4` cannot be resolved.

The `.haxelib/` directory is repository-local and ignored by Git. Install the
pinned hxcpp tag and compile its command-line tool from the repository root:

```sh
tools/setup_hxcpp.sh
```

Confirm that the local Git checkout is on the expected release before making a
native build:

```sh
git -C .haxelib/hxcpp/git describe --tags --exact-match
```

This should print `v4.3.146`. The Git checkout's `haxelib.json` reports the
API-series version `4.3.0`; the Git tag is the authoritative pinned release.

Sharp rendering in the browser:

- `pr2.runtime.Html5PixelRatioSync` follows `devicePixelRatio` after load.
  Lime and OpenFL read it once, so browser zoom or a move to another monitor
  left the canvas at the old density, stretched and blurry.
- `haxe/src/openfl/display/_internal/Context3DBitmap.hx` is OpenFL 9.5.2's
  file with one change (marked in it): a bitmap with smoothing off and
  `PixelSnapping.ALWAYS` (every block, as Flash's `Block` makes them) is
  drawn unsmoothed when the stage is scaled up, like Flash, instead of
  OpenFL smoothing every bitmap on a scaled stage. Re-copy it when OpenFL is
  upgraded.
- `haxe/src/openfl/display/_internal/Context3DTextField.hx` is OpenFL 9.5.2's
  file with one change (marked in it): text is rasterized at the full output
  scale (devicePixelRatio times the stage scale). OpenFL used devicePixelRatio
  alone, so text on the scaled-up stage was drawn small and stretched. Re-copy
  it when OpenFL is upgraded.
- `haxe/src/openfl/display/_internal/Context3DGraphics.hx` is OpenFL 9.5.2's
  file with one change (marked in it): shapes with a scale9Grid (the panels
  and buttons) are rasterized at the full output scale too, so their outlines
  stay sharp. Re-copy it when OpenFL is upgraded.

Browser development path:

```sh
haxelib run openfl test html5
haxelib run openfl build html5
```

Optional macOS target for local debugging:

```sh
haxelib run openfl display mac
MACOSX_VER=26.5 haxelib run openfl test mac
MACOSX_VER=26.5 haxelib run openfl build mac
```

If your installed macOS SDK suffix differs, check it with:

```sh
xcodebuild -showsdks
```

### One-way legacy asset migration

The XFL tree under `flash/platform-racing-2-xfl/` is the visual and behavioral
specification, not a production runtime dependency. Migration tools read XFL
and Animate exports and commit neutral SVG, bitmap, audio, rig, or layout data.
Native Haxe code then references only those committed outputs. Data never flows
from the generated symbol catalog back into the production build.

Verify that boundary after an HTML5 build:

```sh
python3 tools/check_no_compat_runtime.py
```

## Archival Generated Haxe Assets

Extract XFL metadata summary:

```sh
python3 tools/xfl_metadata.py --summary
```

## Vector Art Inventory

Regenerate the vector-art inventory:

```sh
python3 tools/vector_art_inventory.py
python3 tools/verify_deferred_linkages.py
```

Recover bitmap files retained only as XFL `bin/*.dat` payloads:

```sh
python3 tools/extract_xfl_bitmaps.py
python3 tools/extract_xfl_bitmaps.py --check
```

Extract embedded sound effects and regenerate the audio inventory (including
streamed music metadata and authored playback parameters):

```sh
python3 tools/extract_xfl_audio.py
python3 tools/extract_xfl_audio.py --check
```

The default inventory output is `docs/vector-art-inventory.json`.

## Adobe Animate SVG Export

Adobe Animate is only needed when regenerating SVGs from the original XFL/FLA
source. Normal OpenFL builds should not require it.

Regenerate the character SVG export JSFL:

```sh
python3 tools/generate_animate_svg_export_jsfl.py
```

Generate a small smoke-test JSFL:

```sh
python3 tools/generate_animate_svg_export_jsfl.py --limit 8 --out art/export-character-svg-smoke.jsfl
```

Run a JSFL file through Adobe Animate on macOS:

```sh
open -a "/Applications/Adobe Animate 2024/Adobe Animate 2024.app" art/export-character-svg.jsfl
open -a "/Applications/Adobe Animate 2024/Adobe Animate 2024.app" art/export-character-svg-smoke.jsfl
```

The direct Animate executable also runs JSFL scripts:

```sh
"/Applications/Adobe Animate 2024/Adobe Animate 2024.app/Contents/MacOS/Adobe Animate 2024" art/export-character-svg-smoke.jsfl
```

This was verified with the smoke export. The command stays attached while
Animate remains open, so unattended automation still needs a quit/wrapper
decision.

The static channel export flattens every layer except `colorMC` and `colorMC2`.
In the XFL most parts stack outlines, shading and eyes above `colorMC2`, so
after a re-export (or after `tools/generate_character_hat_overlays.py`) split
each part's static art back into its Flash layer bands. The runtime draws
`static_below.svg`, primary, `static.svg`, secondary, then `static_above.svg`:

```sh
python3 tools/split_character_static_layers.py
python3 tools/split_character_static_layers.py --check
```

Then add the new files to the rig (`tools/generate_character_rig.py`) and
rebuild the SVG packs (`tools/generate_svg_packs.py`).

Other generated JSFL entry points:

```sh
python3 tools/generate_other_assets_jsfl.py
open -a "/Applications/Adobe Animate 2024/Adobe Animate 2024.app" art/export-other-assets-svg.jsfl

python3 tools/generate_block_bitmap_jsfl.py
open -a "/Applications/Adobe Animate 2024/Adobe Animate 2024.app" art/export-block-bitmaps.jsfl
```

## Timeline Bitmap Fallbacks

Most exported artwork is rendered directly from SVG. Regenerate the small PNG
fallback set for timeline SVGs containing unsupported bitmap fills or filters
with:

```sh
python3 tools/rasterize_timeline_bitmap_fills.py
```

The generated files live in `art/png/timeline/` and are packaged as
`assets/timeline-bitmap/` by `project.xml`.

Check Inkscape availability:

```sh
/Applications/Inkscape.app/Contents/MacOS/inkscape --version
```

## Harness Helpers

### Corner clip sweep

`tools/clip_sweep.sh` runs the real `LocalPlayerController` (compiled to JS and
run with Node) through grids of stats and inputs against an inside corner, and
reports every run where the player's body ends up inside solid blocks, with a
command that reproduces it frame by frame:

```sh
tools/clip_sweep.sh                                # default grid, ~1 minute
tools/clip_sweep.sh --speed 0:100:5 --jump 0:100:5 --dir right,left
tools/clip_sweep.sh --random 50000 --seed 7        # random held-key sequences
tools/clip_sweep.sh --super 0,13:50 --move-start 0:10 --turn -1,1:20  # super jumps, delayed moves, air turns
tools/clip_sweep.sh --help
```

To sweep real levels, download them first (saved to `test/output/levels`, which
is git-ignored), then point the sweep at the folder. It finds every inside
corner in each level and sweeps each one; every run starts from a fresh player
and level, so after a clip the next attempt starts clean:

```sh
tools/fetch_levels.py                              # campaign, best, best_week, newest
tools/fetch_levels.py --ids 50815,1234567          # or specific levels
tools/clip_sweep.sh --levels test/output/levels
tools/clip_sweep.sh --levels test/output/levels/50815.txt --max-clips-per-corner 1
```

It is a diagnostic tool, not part of `./test.sh`.

### Input viewer (/ihud)

Typing **/ihud** in the race chat turns on an input viewer in the bottom right
corner, just above the mute button; typing it again turns it off. It stays on
for later races until you turn it off. It lights each key the player is
pressing every frame: **Left**, **Down** and **Right** in one row with
**Space** (item) beside Right, and **Up** (jump) above Down. During the Clip
Finder's **Replay on me** it shows the replay's keys instead of your keyboard,
so you can see exactly what the clip presses. It is a debug addition with no
Flash counterpart (`haxe/src/pr2/gameplay/InputViewer.hx`).

### In-game Clip Finder (F9+C+D)

In a race, press **F9 + C + D** to open the Clip Finder panel: hold them
together, or tap them one after another within a second, in any order. The
same combo or the X button closes it. Typing **/clip** in the race chat does
the same, which helps on keyboards where F9 is a media key (on many laptops
and Macs, hold **Fn** for F9). It is a debug addition with no Flash counterpart,
in `haxe/src/pr2/gameplay/debug/`, and it shares its simulation code with
`tools/clip_sweep.sh`.

- Each stat is fixed at your current value; tick **Range** to search a min-max
  range instead (both sliders start at your stat).
- **Left/Right** choose the run direction and **Try fast-fall** adds runs that
  hold down while airborne after the jump. Each move option has a tick box and
  a slider for the frames it tries:
  - **Normal jump**: press jump on frames 0-N (held 4, 8 or all frames).
  - **Super jump**: hold down for 13-N frames on the ground, then release
    (13 is the shortest charge that launches, 50 the full charge).
  - **Delayed move**: start holding the direction on frames 0-N, so the player
    stands or jumps in place first.
  - **Air turn**: flip the held direction on frames 1-N (runs without a turn
    are still tried).

  Every ticked option multiplies the number of attempts.
- **Any frame** ignores those sliders: the ticked moves can happen on any frame
  of the run (super jumps can also start charging on any frame). That is far
  too many combinations to try them all, so each attempt picks random timings
  and the search keeps going until **Stop**.
- **Target** (next to the title): click it, then click a block in the level.
  The block gets a red outline and **Aim at target** is ticked. Click the
  button again to clear it.
- **Scan level...** (the menu under the title) has two stages; picking one
  runs it:
  - **Stage 1: map scan (every corner)** checks every inside corner in the
    level, nearest first, with your own stats, gravity and hats. **A clip
    is your feet going into a block** (2 px above the feet, so standing on
    a floor doesn't count): the game only leaves your feet inside a block
    when your body is stuck too, since a floor under the feet snaps you on
    top of it unless the point 30 px up is in a block as well. A head or
    body that only pokes into a block (jumping into a ceiling, falling past
    a block's bottom corner with your feet just under it) is not a clip,
    in any stage. The **bottom corner of a wall** and a **ceiling meeting a
    wall** used to be scanned as well; they only ever put the body in, so
    they are off now (`ClipScanSettings.wallClips` turns them back on).
    For the usual corners, run-ups of
    0-260 px (short ones fit narrow shafts) into a full jump, a short hop or a super jump, each into
    fast-fall. A corner that can't be clipped gets a grey cross on its wall
    tile; a clip gets a box on the block your feet went into (often the
    corner's floor rather than its wall; a mine blast also outlines the mine)
    (green = you pass through and land beyond it,
    yellow = you pop back out on the same side, orange = you fall out of the
    level), with a line from the run-up start to where you land. Found clips
    go into the Prev/Next list, so the ghost and **Replay on me** work on
    them. A mine is never the wall or floor of a corner: touching it blows it
    up instead of letting you clip in. Each corner is also tried with a
    **hop back**: stand against the wall, jump (held 1-12 frames or fully),
    hold away from the wall, then on a set frame (4-75) dive back holding
    toward the wall and down. A clip needs you to land more than 10 px into
    the floor while moving 10 px a frame or more into the wall, and in a
    narrow shaft or off a bouncy floor that is the only way to get both. On
    an up arrow by a wall (as on level 3460484), a one-frame tap jump, away
    until frame 17, then the dive goes through. Once you are inside the
    blocks they don't act on you, so the arrow only matters for the launch.
    If you hold a **Laser Gun**, each
    corner is also tried with a laser recoil clip: stand against the wall,
    jump in place, and on the frame before landing in the corner turn away
    from the wall and fire. The recoil (15 px a frame into the wall) plus the
    landing speed can put you through the floor. Only that exact frame
    works, and it depends on your stats, so every fire frame from 4 to 75 is
    tried (with three jump heights and 0-2 px from the wall). Other held
    items add their own attempts: the **Sword** the same grid facing the
    wall (its lunge adds 8 px a frame forward), the **Super Jump** item
    run-ups that launch with it (25 up) into fast-fall, and **Speed Burst**
    run-ups that burst first (double speed and acceleration) then jump or
    hop into fast-fall. With a Speed Burst it also tries the burst super
    jump: hold down to charge a super jump, use the burst while charging,
    then let go of down holding toward the wall, so the super jump carries
    twice your top speed. It tries each charge, bursting early or late in
    the charge, both running in and standing still until the release (with
    100 speed and the item on level 3460484 it found 42 corners this way). In testing on a plain corner only the laser opened it
    (the sword's 8 is about half the laser's 15), but every corner is tried
    with whatever you hold, and with every item that moves you (Laser Gun,
    Super Jump, Speed Burst, Sword, Mine, Jet Pack, Teleport) the level's
    item blocks can give, even if you hold nothing (a block without options
    gives any of the level's items). A clip found with an item says so, and
    **Replay on me** hands you that item. Trying them all makes Stage 1
    several times slower on a level with items; Stage 1.5 is the quick way to
    try them. The other items:
    - **Mine**: placed at your hand (always a little to your right, as in
      Flash), it appears 33 frames later; touching it then blasts you away
      from its centre at 50 (capped at 28 px a frame). Each corner tries
      placing it 0-18 px off the wall, standing or at four points of a hop
      or a jump, facing the wall or away, then staying, walking at the wall,
      stepping away and back, or jumping up into it. At speed 50 (too slow
      for any run-up) on the test corner, placing it standing 6 px off the
      wall then stepping away and back blasts you through the 3-block wall.
    - **Jet Pack**: run-ups every 10 px that jump, fly 4-30 frames, then
      fast-fall into the corner.
    - **Teleport**: 120 px toward the wall on a set frame of a run, hop or
      jump. It only checks the spot 5 px above your feet, but a floor under
      your feet still snaps you onto it, so in testing it never put the feet
      in a block.
    - **Lightning**, **Ice Wave** and **Snake** don't move you (the Snake digs
      on its own, outside your physics), so they add nothing.

    **Arrow blocks** act on you in every attempt (it runs the real physics),
    and corners with arrows near them get arrow starts of their own. Standing
    on an up arrow bounces you up (10 px a frame); a side arrow pushes 3 px a
    frame on every frame you stand on it, more than your speed relaxes, so
    riding a conveyor while holding its way builds up to 31 px a frame (it
    bleeds off to about 12 within 12 frames in the air); a down arrow wall
    drags you down 5 px a frame more while you slide on it. For each run of
    arrows within 30 tiles before a corner's wall, from 8 rows above its
    floor to 3 below (its far end, middle and near end, up to 6 starts), and
    against an arrow wall, it waits 0-40 frames (still or holding toward the
    wall), then jumps, hops, keeps jumping from the start, or just goes, with
    fast-fall. On the test corner with a conveyor ledge 3 rows up, a hop off
    its far end clips at speed 50, where no run-up can; on plain layouts the
    arrow starts rarely add clips. Stage 1.5 doesn't solve starts on arrows
    (or ice, mines, teleport, push and move blocks), since its programs are
    played on plain ground; those corners get Stage 1's attempts, arrow
    starts included.
    It also scans **mines**: a mine on the floor with room to stand beside
    it (walk, hop or jump at it from 2 px and 40 px), a mine set into the
    floor (step onto it or run across it), and a mine overhead (jump up into
    it). Any blast that drives you into a block is listed and marked on the
    mine, with where you come out. With **Range** ticked on a stat row, every
    corner and mine is tried with each sampled set of stats (up to 4 values
    per ranged stat, your own stats first), and a clip shows the stats that
    did it.
  - **Stage 1.5: predicted clips** solves the physics instead of trying
    run-ups at each corner. A corner clips when you land more than 10 px
    into its floor while moving at least 10 px a frame into its wall (the
    wall check is 10 px above your feet, so it is inside the floor row and
    nothing pushes you out). In the air your two axes don't affect each
    other: left and right only change the sideways speed, jump and down only
    the vertical one, and each is rounded on its own. So any flight is
    exactly a vertical program and a horizontal program put together, frame
    by frame (checked: 0 px apart from the real flight). With your stats
    (each sampled set with Range), gravity and hats it plays, once each:
    - **vertical programs**: jump held 1-12, 15, 20 or all frames; super
      jumps charged 10-50 frames; each with fast-fall from frame 1, 2 or any
      4th frame up to 60, or none; the Super Jump item alone or during a
      jump; and full jumps and super jumps bumping a ceiling 2-12 tiles up.
      The floor is taken away after takeoff, so each lists the frames it
      lands more than 10 px deep on every floor height above and below
      (and the frames it passes 10-15 px under a block's bottom, for bottom
      corners).
    - **horizontal programs**, each way: running, running with a Speed
      Burst, holding away for 1-60 frames and turning back, and running
      with a Sword slash or a Laser shot (turn away and fire for the
      recoil) on a given frame.
    For each corner, each floor height with landings, each horizontal
    program and each frame `s` of it, the wall must be crossed on frame `s`:
    that gives a window of start x a few px wide. Where a spot you can stand
    on falls in the window, every landing on that floor height that lines up
    in time is a solution: moving starts `t + 1 - s` frames into the jump
    (no sooner than a super jump's release or a ceiling bump), or a plain
    jump gets a run-up of `s - 1 - t` frames on floor that reaches the
    takeoff. Starts are whole pixels, like the programs (the game rounds the
    position every frame, so a start a fraction off drifts). The solved
    path is then traced through the level: starts whose path stays clear of
    blocks until the corner are checked first, nearest and with the least
    waiting first, and the rest after. Each is checked with the real physics
    in the real level, and the first that clips is listed, like Stage 1.
    A solved start lands in the corner on exactly the frame it was solved
    for. Ceiling corners (no landing to solve) and every mine get Stage 1's
    own attempts, and so does a corner none of its solved starts clip, so
    it finds everything Stage 1 does as well. The status says how many were
    predicted.
    On level 3460484 (100/45/40, no items, 246 corners) it plays 1,097
    programs in about a second and clips 203 corners (165 solved, the rest
    from Stage 1's attempts) in 83 s, against Stage 1's 140 in 168 s
    (outside the game). With the level's items it also times Sword slashes
    and Laser shots to the landing, and finds 133 corners from solving
    alone in under a minute. On level 102573 it finds 125 clips from
    solving alone; from 340,336 it solves super jumps into the ceiling 8
    tiles up, holding right, that clip the corner at 343,338.
  - **Stage 2: route to target** (with Range ticked on stat rows, it plans
    with each sampled set of stats in turn, up to 3 values per ranged stat
    and your own stats first, until one finds a route; the status shows which
    set) plans a way from where you stand to the
    picked target block with your stats, gravity and hats, and goes through
    walls and floors when that is the way there. It tries walks, jumps, super
    jumps and a jump in place from each spot it can stand on, cheapest first.
    A clip counts as 4 ordinary moves, so clips are only used when needed.
    For a clip at a wall within 10 tiles, it first scans that wall for a
    run-up that comes out on the other side, then walks to that exact pixel,
    stops, and plays the run-up. It also uses mines: the real physics blows a
    mine up when you touch it and adds 50 to your speed, pointing away from
    the mine's centre, then gives 60 hurt frames. A blown-up mine stays gone
    for the rest of the route. At the 3 nearest mines within 8 tiles it tries
    walking, hopping and jumping at a mine from 2 px and 40 px away, jumping
    up into a mine overhead, and stepping onto or running across a mine set
    into the floor. That way a blast can launch you onto a ledge, or even
    into a clip. Steps that set off a mine say "(hits a mine)". Mines already
    blown up in the race (or placed with the mine item) are taken as they are
    when the search starts. The route becomes the one clip in the list: the
    ghost plays it, the info text lists its steps, and **Replay on me** runs
    it on you. It gives up after 5000 spots or 200 steps; then the info text
    says why moves were dropped (back to known spots, never settled, sent
    back or fell out, stuck in blocks, could not line up).

    How it searches big levels:
    - It heads for the target: each spot is ranked by what it took to get
      there plus how far it still is from the target, measured through the
      level's open tiles (blocks that can be cleared, like vanish, brick,
      crumble, mine and push, count as open but costly). So it follows
      corridors instead of pushing into walls.
    - Moves from a spot start from a copy of the player standing there
      (with its level, blocks and items), not a replay of the whole route,
      and the simulated level looks blocks up by tile. The finished route is
      still one input script that plays back exactly from the start.
    - Move blocks run on a frame clock in the simulation, so every replay
      sees them move at the same moments.
    - On level 80814 (Mario Bros remix, 545 tiles from start to finish) it
      finds a 51-step route in under a minute (about 3 minutes in game,
      where it only gets a slice of each frame).

    Other blocks and items it knows about:
    - **Rotate blocks** turn the whole course. The planner follows the
      player in the level's own space, so a route may turn the course and
      carry on (or turn it back); the step says "(turns the course)" and the
      ghost is drawn turned. Clip moves are tried on a turned course too (at
      the corners as the player sees them in that turn); mine moves only
      while upright.
    - **Items:** you start with the item you hold, and item blocks give
      items. In the game an item block picks at random; the planner uses a
      fixed sequence so its routes replay the same way, and a replay on you
      may get a different item. From a spot holding an item it tries using
      it standing, running, mid-jump and held down (the jetpack flies while
      held). Steps say "(gets Jet Pack)" or "(uses up the item)". A teleport
      (block or item) is not mistaken for being sent back. Holding a Laser
      Gun, Sword, Super Jump or Speed Burst, its clip moves also try that
      item's clips; such steps say "(laser recoil)", "(sword lunge)",
      "(super jump item)" or "(speed burst)". A hop-back clip says
      "(hop back)". Against a wall it starts on the frame after you land, so
      it works on a bouncing up arrow too. When a move takes an item from
      an item block, it also tries each other movement item that block could
      give (laser, teleport, super jump, jetpack, speed burst, sword), so a
      route can count on the one it needs; the route remembers its choice.
      You start with the uses your item has left. Item uses are kept in one
      global store in the game (as in Flash), so searches put your real
      item's uses back after every slice of work.
    - **Water:** 10 frames of swimming count as a spot (a pool may have no
      bottom: sinking out of it drops you off the map and back into the
      water), and from a spot in water it tries swimming up, up and to each
      side, sideways, and diving.
    - **Arrow blocks and ice:** riding a conveyor of arrow blocks (or
      sliding on ice) never comes to a stop, so standing on them counts as a
      spot after 10 frames, and so does 45 frames on any floor.
    - **Vanish blocks:** standing on one isn't a resting spot (it fades and
      drops you). Next to one it tries pushing into it or bumping it from
      below, waiting for it to fade, then going through before it returns.
    - The target counts as reached when you touch one of its faces (stand on
      it, push against it, bump it, or end up inside it), not a corner
      graze.
- **Aim at target** runs the same clip tester as usual (grid, or random with
  **Any frame**), but only clips into the picked block count. Untick it to keep
  the block picked but count every clip.
- The simulated copy of the level starts small around you and grows to cover
  wherever the simulated player goes (up to the level's edge), re-running the
  attempt after each growth; falling off the map uses the whole level's edge,
  like the real game.
- **Replay on me** plays the shown clip on your real player: it moves you to
  the clip's start, gives you the clip's stats, and plays the clip's inputs
  (the keyboard is ignored meanwhile), with the ghost running alongside. Your
  own stats come back when it ends; press the button again to stop early. It
  needs the race to be running, and other players see the jump. Mines it
  blows up and bricks it breaks are put back when it ends (only on your
  screen; other players saw them go). If the ghost holds an item you are
  given it for the replay, and where the ghost takes an item from an item
  block you are given that same item (the game's own roll is random); your
  own item comes back when the replay ends.
- **Start** searches from where you are standing in a cropped copy of the
  level, a few attempts per frame so the race keeps running. Every attempt
  starts from a fresh simulated player; your real player, blocks and network
  state are never touched.
- A translucent ghost of your character replays the selected clip, holds for a
  moment, then resets and plays it again. **Prev/Next** switch between clips.

**Stage 3: movement glitches** looks for movement and collision bugs, not
clips (the other stages find those) and not head clips. It first plays, on
open ground with your stats, gravity, hats and item, the highest and fastest
anything can go: every super jump charge with a jump just before, on or
after the release, and your item used on each frame of a jump. Then at spots
you can stand on near you (up to 400, nearest first, not on arrows or other
blocks that move you) it plays 40 moves (run-up jumps of three heights,
jumping up a wall, bunny hops, super jumps, crouch-jumps, fast-fall, plain
walking, and your item at three moments, each way) and lists any run that:

- **jumps higher** above the floor it left than anything can on open ground,
- **moves faster** than anything can on open ground,
- **climbs without jumping** (gains more than 8 px while only walking),
- **is snapped** up or sideways more than 12 px further in one frame than
  its speed carries it (the collision code moving the player: for example
  landing at the foot of a one-block step while running puts you on top of
  it in one frame), or
- **hangs in the air** for 8 frames or more without rising or falling (not
  swimming, with a jetpack or the cowboy hat; for example pinned under a low
  ceiling while holding jump).

Snaps down are left out (that is the head being pushed back out of a ceiling
it was already in), and so are runs that clip, are hurt or frozen, or touch
blocks meant to move you (arrows, mines, teleports, item and stat blocks,
rotate blocks, water, push and move blocks, the finish). Each glitch (one per
kind and tile) goes in the clip list with what it does, the moves, the ghost
and Replay on me. On level 3460484 (100/45/40) it checks 300 spots in about
16 s and finds 25 step snaps and one hover.

**What counts as a clip:** in the map scans (Stages 1 and 1.5) and in a
search without a target, a clip only counts when it goes through: after
getting into the blocks you come to rest outside them on the far side of
the block you went into, at least a tile from where you went in, without
being sent back to a safe spot. A head clip that pops back out, or one that
falls out of the level, isn't listed. Aiming at a target block, any clip
into it counts, and Stage 2 routes use whatever clip gets them there.

**Hats:** every search uses the hats you wear: moon (lower gravity),
propeller (holding jump slows the fall), cowboy (moves like swimming in the
air, and its speed), santa (freezes blocks), crown, party, jellyfish, top
hat (vanish blocks) and cheese (crumble force). A speed burst running when
you start (the Jump Start or Artifact hat, or the item) carries into the
simulation. With the Artifact hat's swapped controls, **Replay on me**
swaps the keys back, so the replay moves as simulated.

**Turned courses:** every stage works while the course is turned by a
rotate block. Corners, starts and spots are found as you see the course
(your own course coordinates), and the physics runs in the real level with
the course turned the same way, so it matches the game exactly. That
matters: the game rounds turned coordinates toward zero, which puts block
edges 1 px further along a flipped axis, so some clips only work in some
turns (for example the test corner clips turned 90 but not 180 or -90).
Each clip remembers the turn it was found in; **Replay on me** turns the
course to that turn at once before putting you at the start, and the
overlay and ghost are redrawn when the course turns.

### Archival Flash side-by-side workflow

The production build is native-only, but the checked-in Flash projector, SWF,
AS3, and XFL remain the comparison specification. Both clients consume the same
timed parity sequence; comparison-only catalog/runtime code must stay outside
`haxe/src`.

```sh
python3 tools/test_archival_parity_workflow.py
tools/test_dont_move_jv.sh flash flash/platform-racing-2.app
tools/test_dont_move_jv.sh port
python3 tools/compare_screenshots.py test/output/dmjv-flash/10-complete.png test/output/dmjv-openfl/10-complete.png --diff test/output/dmjv-diff.png --metrics test/output/dmjv-metrics.json --threshold-percent 100 --threshold-rms 255
```

For a single XFL symbol, use `tools/compare_symbol_render.py`; for a native-only
flow, use the OpenFL sequences below.

Capture an OpenFL screenshot after launching the app:

```sh
python3 tools/openfl_driver.py --delay 2.0 shot test/baselines/openfl/run_harness.png
```

Capture popup parity fixtures without requiring a live lobby session:

```sh
python3 tools/openfl_driver.py --delay 8 --query 'screen=popup&popup=loadouts' shot test/output/openfl-popup-loadouts.png
```

Supported popup fixtures are `message`, `confirm`, `send-message`, `codes`,
`loadouts`, and `credits`.

Read and validate the OpenFL debug state. The offline gameplay sandbox
(`?screen=campaign&debug=1&localLevel=<name>`) publishes the local player's
state to `data-pr2-debug-state`:

```sh
python3 tools/openfl_driver.py --delay 2.0 --query 'screen=campaign&debug=1&localLevel=flat' \
  --expect phase=playable \
  debug-state
```

Measure real-level art drawing performance through the campaign harness. Build
first, then serve the HTML5 export through the local API proxy so browser fetches
for `pr2hub.com` stay same-origin:

```sh
haxelib run openfl build html5
python3 tools/dev_proxy.py --port 8000 --dir export/html5/bin
```

Run the metric harness from another terminal. It records drawing/playable timing,
per-sample FPS, art/block progress, heap usage, and Chrome performance metrics:

```sh
python3 tools/measure_art_render.py \
  --base-url http://127.0.0.1:8000 \
  --label current-candyland \
  --level-id 3460484 --version 13 \
  --out test/output/art-render-candyland.json \
  --timeout 180 --print-every 16
```

Useful art-render stress cases:

```text
3460484 v13  Candyland          Fast-ish, visible parity check, lots of strokes
4866546 v15  Volcanic Inferno   Medium-heavy art and block mix
5877893 v18  Apocalypse         Extreme art case; old builds may not finish
5821108 v92  Smog               Earlier baseline candidate
```

To compare an older revision against the current build, keep each export in a
separate directory and run two proxy ports:

```sh
git worktree add /private/tmp/pr2-baseline add6470
haxelib run openfl build html5
cd /private/tmp/pr2-baseline
haxelib run openfl build html5

python3 tools/dev_proxy.py --port 8001 --dir /private/tmp/pr2-baseline/export/html5/bin
python3 tools/dev_proxy.py --port 8002 --dir /path/to/current/export/html5/bin

python3 tools/measure_art_render.py --base-url http://127.0.0.1:8001 \
  --label baseline-apocalypse --level-id 5877893 --version 18 \
  --out test/output/art-render-baseline-apocalypse.json --timeout 300

python3 tools/measure_art_render.py --base-url http://127.0.0.1:8002 \
  --label current-apocalypse --level-id 5877893 --version 18 \
  --out test/output/art-render-current-apocalypse.json --timeout 180
```

Compare two stage screenshots and write diff artifacts:

```sh
python3 tools/compare_screenshots.py expected.png actual.png --diff test/output/diff.png --metrics test/output/metrics.json --threshold-percent 1 --threshold-rms 8
```

Score the vector renderer against the Adobe `@4x` rasters. Each case renders one
library symbol through the `?screen=symbol` vector path, trims it to its content
box, resizes to the reference raster, and reports `rmsDelta` / `differingPercent`
(`rmsDelta` is the gate; see `tools/symbol_render_cases.json` for the cases and
per-case thresholds):

```sh
python3 tools/compare_symbol_render.py --diff-dir test/output/symbol-diffs --metrics test/output/symbol-metrics.json
python3 tools/compare_symbol_render.py --symbol UI/Global/MuteButton --reference test/baselines/vector-art/mute_button@4x.png
```

Check approximate OpenFL frame rate:

```sh
python3 tools/openfl_driver.py --fps-duration 30 --fps-target 30 --fps-tolerance 5 fps
```

Run a scripted OpenFL driver sequence:

```sh
python3 tools/openfl_driver.py sequence test/sequences/openfl/lobby-flow.json
python3 tools/openfl_driver.py sequence test/sequences/openfl/lobby-parity.json
python3 tools/compare_screenshots.py test/baselines/flash/04_lobby_unobstructed.jpg test/output/openfl-lobby-shell.png --diff test/output/openfl-vs-flash-lobby-diff.png --metrics test/output/openfl-vs-flash-lobby-metrics.json --threshold-percent 100 --threshold-rms 255
```

To exercise campaign and search responses through the real same-origin proxy,
start `tools/dev_proxy.py` and run the parity sequence against it:

```sh
python3 tools/openfl_driver.py --base-url http://127.0.0.1:8000 sequence test/sequences/openfl/lobby-parity.json
```

Sequence files keep one browser session open and can combine `keyDown`,
`keyUp`, `tap`, `hold`, `mouseMove`, `navigate`, `metrics`, `debug-state`, and
`shot` actions. Screenshots, metrics, and diff output should go under ignored
`test/output/`.

Run the broad browser navigation smoke suite, including route reloads, member
and guest lobby tabs, and per-checkpoint Chrome metrics:

```sh
tools/test_browser_navigation.sh
```

The metrics JSON is written to `test/output/browser-navigation-metrics.json`.

Sequences wait for the app to boot past the OpenFL preloader before the clock
starts: step `time` offsets are measured from when `Main` sets the
`data-pr2-app-ready` body attribute, not from browser launch. This keeps input
from being dispatched into the preloader (where it is silently dropped), so
`time` values only need to cover in-app settling, not a guessed preload
duration.

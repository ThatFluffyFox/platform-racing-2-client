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
    level, nearest first, with your own stats, gravity and hats: run-ups of
    100-260 px into a full jump, a short hop or a super jump, each into
    fast-fall. Each corner's wall tile is marked: a grey cross if it can't be
    clipped, or a box if it can (green = you pass through and land beyond it,
    yellow = you pop back out on the same side, orange = you fall out of the
    level), with a line from the run-up start to where you land. Found clips
    go into the Prev/Next list, so the ghost and **Replay on me** work on
    them. A mine is never the wall or floor of a corner: touching it blows it
    up instead of letting you clip in. If you hold a **Laser Gun**, each
    corner is also tried with a laser recoil clip: stand against the wall,
    jump in place, and on the frame before landing in the corner turn away
    from the wall and fire. The recoil (15 px a frame into the wall) plus the
    landing speed can put you through the floor. Only that exact frame
    works, and it depends on your stats, so every fire frame from 4 to 75 is
    tried (with three jump heights and 0-2 px from the wall).
  - **Stage 2: route to target** plans a way from where you stand to the
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
      ghost is drawn turned. Clip and mine moves are only tried while the
      course is upright.
    - **Items:** you start with the item you hold, and item blocks give
      items. In the game an item block picks at random; the planner uses a
      fixed sequence so its routes replay the same way, and a replay on you
      may get a different item. From a spot holding an item it tries using
      it standing, running, mid-jump and held down (the jetpack flies while
      held). Steps say "(gets Jet Pack)" or "(uses up the item)". A teleport
      (block or item) is not mistaken for being sent back. Holding a Laser
      Gun, its clip moves also try the laser recoil clip; such steps say
      "(laser recoil)". You start with the uses your item has left. Item uses
      are kept in one global store in the game (as in Flash), so searches
      put your real item's uses back after every slice of work.
    - **Water:** 10 frames of swimming count as a spot (a pool may have no
      bottom: sinking out of it drops you off the map and back into the
      water), and from a spot in water it tries swimming up, up and to each
      side, sideways, and diving.
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
  needs the race to be running, and other players see the jump.
- **Start** searches from where you are standing in a cropped copy of the
  level, a few attempts per frame so the race keeps running. Every attempt
  starts from a fresh simulated player; your real player, blocks and network
  state are never touched.
- A translucent ghost of your character replays the selected clip, holds for a
  moment, then resets and plays it again. **Prev/Next** switch between clips.

It only works while the course is upright (not mid-rotation).

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

package pr2.gameplay.debug;

import pr2.gameplay.debug.ClipScanner.ClipCorner;
import pr2.gameplay.debug.ClipScanner.ClipScanSettings;
import pr2.gameplay.debug.ClipSimulator.ClipArea;
import pr2.gameplay.debug.ClipSimulator.ClipAttempt;
import pr2.gameplay.debug.ClipSimulator.ClipItems;
import pr2.gameplay.player.LocalPlayerInput;
import pr2.level.BlockType;
import pr2.level.Level.LevelBlock;

/**
	The physics behind Stage 1.5. In the air the player's two axes don't touch
	each other: left and right only change the horizontal speed (accelerating
	toward a target speed), jump and down only the vertical one (jump, the
	held-jump boost, gravity, fast-fall, the super jump release). Position is
	rounded on each axis on its own. So a flight is exactly a horizontal track
	(what the left/right keys do, from a standstill) put together with a
	vertical track (what the jump/down keys do), frame by frame. (Tested: 0 px
	apart from the full flight.)

	A corner clips when, on one frame, the feet land 10 px or more into its
	floor (vertical) and the body crosses into the wall's column moving at 10 px
	a frame or more (horizontal). So the solver:

	1. Plays every vertical program once (each jump hold, each super jump
	   charge, fast-fall from any 4th frame, the Super Jump item, and the same
	   bumping a ceiling 2-12 tiles up) and lists the frames that land deep on
	   each floor height (and that pass 10-15 px under a block's bottom, for
	   hanging corners).
	2. Plays each horizontal program once per direction (run from a standstill,
	   with a Speed Burst, turn back after N frames, and Sword or Laser timed to
	   a frame), giving the distance covered after s frames of moving.
	3. For a corner, a landing on frame `t` at a floor height, and a spot to
	   stand on at that height, the wall crossing must happen on moving frame
	   `s` where the distance window [x(s-1)+10, x(s)] holds the wall: that
	   gives the start x exactly, and moving starts `t + 1 - s` frames into the
	   jump (or after a run-up of `s - 1 - t` frames, then the jump). Only
	   those starts are checked with the real physics.
**/
class ClipSolver {
	/** Frames each track is followed (from the settings). **/
	final frames:Int;
	static inline var MAX_DROP_ROWS:Int = 30;
	static inline var MAX_RISE_ROWS:Int = 20;
	/** Solutions kept per start spot and horizontal frame (one per kind of jump, plus run-ups). **/
	static inline var PER_SPOT:Int = 2;
	/** Score added to a start whose predicted path hits a block before the corner. **/
	static inline var BLOCKED_PATH:Float = 100000;

	static inline var LASER_GUN:Int = 1;
	static inline var SUPER_JUMP:Int = 5;
	static inline var SPEED_BURST:Int = 7;
	static inline var SWORD:Int = 8;

	final settings:ClipScanSettings;
	public final stats:Array<Float>;
	/** Items it may use (from the held item and the level's item blocks). **/
	final items:Array<Int>;
	public final vertical:Array<VTrack> = [];
	/** Landing frames per floor row offset (positive = below the start floor), by frame. **/
	final floorHits:Map<Int, Array<Array<VHit>>> = new Map();
	/** Frames passing 10-15 px under a block bottom, per row offset of that bottom, by frame. **/
	final hangHits:Map<Int, Array<Array<VHit>>> = new Map();
	/** Horizontal tracks by kind, direction and parameter. **/
	final horizontal:Map<String, HTrack> = new Map();
	/** Programs still to play (spread over `step`). **/
	final pendingV:Array<VTrack> = [];
	final pendingH:Array<HTrack> = [];
	var played:Int = 0;

	public function new(settings:ClipScanSettings, stats:Array<Float>, items:Array<Int>) {
		this.settings = settings;
		this.stats = stats;
		this.items = items;
		frames = settings.solveFrames;
		var ff = settings.solveFastFalls;
		for (hold in settings.solveJumpHolds) for (d in ff) pendingV.push(VTrack.jump(hold, d));
		for (charge in settings.solveCharges) for (d in ff) if (d < 0 || d > charge) pendingV.push(VTrack.superJump(charge, d));
		if (hasItem(SUPER_JUMP)) {
			for (d in ff) pendingV.push(VTrack.itemJump(-1, d));
			for (at in [4, 8, 12, 16, 20]) for (d in [-1, at + 8]) pendingV.push(VTrack.itemJump(at, d));
		}
		var ceilingCharges = [for (c in settings.solveCharges) if (c % 5 == 0) c];
		for (h in settings.predictCeilings) {
			// The bump turns the rise into a fall (a quarter of the speed, downward);
			// fast-falling from the frame after it lands hardest, so every frame is tried.
			for (d in -1...25) if (d != 0) pendingV.push(VTrack.jump(999, d, h));
			for (charge in ceilingCharges) for (d in [-1, charge + 1, charge + 2, charge + 3, charge + 4, charge + 8, charge + 16]) pendingV.push(VTrack.superJump(charge, d, h));
		}
		for (dir in [1, -1]) {
			pendingH.push(new HTrack(Run, dir, 0));
			if (hasItem(SPEED_BURST)) pendingH.push(new HTrack(Burst, dir, 0));
			for (a in settings.solveTurnBacks) pendingH.push(new HTrack(TurnBack, dir, a));
		}
	}

	public var ready(get, never):Bool;
	inline function get_ready():Bool return pendingV.length == 0 && pendingH.length == 0;

	/** Programs to play in all, and played. **/
	public var trackCount(get, never):Int;
	inline function get_trackCount():Int return played + pendingV.length + pendingH.length;
	public var tracksPlayed(get, never):Int;
	inline function get_tracksPlayed():Int return played;

	/** Plays up to `max` programs. Returns how many. **/
	public function step(max:Int):Int {
		var n = 0;
		while (n < max && pendingV.length > 0) {
			var v = pendingV.shift();
			playVertical(v);
			vertical.push(v);
			n++;
		}
		while (n < max && pendingH.length > 0) {
			var h = pendingH.shift();
			playHorizontal(h, frames);
			horizontal.set(h.key, h);
			n++;
		}
		played += n;
		return n;
	}

	public function hasItem(item:Int):Bool return items.indexOf(item) >= 0;

	// ---- Vertical ------------------------------------------------------------------

	/**
		Plays a vertical program on a 3-tile floor (and a ceiling over it, if
		any) with no left/right keys; the floor is taken away once the player
		leaves it, so the fall carries on below the start height. Lists its deep
		landings and its passes under block bottoms.
	**/
	function playVertical(v:VTrack):Void {
		var t = ClipSimulator.TILE;
		var col = 300, row = 100;
		var blocks = [for (c in col - 1...col + 2) new LevelBlock(c, row, BlockType.Basic)];
		if (v.ceiling > 0) for (c in col - 1...col + 2) blocks.push(new LevelBlock(c, row - v.ceiling - 1, BlockType.Basic));
		var area = new ClipArea(blocks, col - 20, row - 40, col + 20, row + 20);
		var level = area.buildLevel(settings.gravity);
		var floorY = row * t * 1.0;
		var player = ClipSimulator.preparePlayer(area, level, col * t + 15, floorY, stats[0], stats[1], stats[2], settings.gravity, settings.hats,
			v.item != null ? new ClipItems(v.item) : null);
		player.setMapBoundsForClipSearch(-1e7, -1e7, 1e7, 1e7);
		var ys = [];
		var left = false;
		var highest = 0.0;
		for (f in 0...frames) {
			player.step(v.inputAt(f));
			ys.push(player.y - floorY);
			if (!left && !player.grounded && f > 0) {
				left = true;
				for (b in level.blocks.copy()) if (b.y == row) player.blockController.removeBlock(b);
			}
			// The frame the bump stops the rise.
			if (v.ceiling > 0 && v.bumpFrame < 0 && f > 0 && left && ys[f] >= ys[f - 1]) v.bumpFrame = f;
			highest = Math.min(highest, ys[f]);
		}
		if (v.ceiling > 0 && (v.bumpFrame < 0 || highest > -(v.ceiling * t) + 60)) {
			// Never reached the ceiling: a plain program already does the same.
			v.ys = [];
			return;
		}
		v.ys = ys;
		for (f in 1...ys.length) {
			var y0 = ys[f - 1], y1 = ys[f];
			// Floors (row offset k) the feet pass 10 px or more through on this frame: the
			// wall check (10 px above the feet) is then in the floor row, beside a solid block.
			var kMin = Math.ceil(y0 / t), kMax = Math.floor((y1 - 10 + 1e-6) / t);
			for (k in kMin...kMax + 1) {
				if (k * t <= y0 || k < -MAX_RISE_ROWS || k > MAX_DROP_ROWS) continue;
				add(floorHits, k, new VHit(v, f, false));
			}
			// A block bottom 10-15 px above the feet on this frame.
			var bottom = Math.ceil((y1 - 15) / t) * t;
			if (bottom < y1 - 10 && bottom > y1 - 15) {
				var n = Std.int(bottom / t);
				if (n >= -MAX_RISE_ROWS && n <= MAX_DROP_ROWS) add(hangHits, n, new VHit(v, f, y0 - 10 < bottom));
			}
		}
	}

	function add(map:Map<Int, Array<Array<VHit>>>, key:Int, hit:VHit):Void {
		var byFrame = map.get(key);
		if (byFrame == null) map.set(key, byFrame = [for (_ in 0...frames + 1) null]);
		if (byFrame[hit.frame] == null) byFrame[hit.frame] = [];
		byFrame[hit.frame].push(hit);
	}

	/** Deep landings `k` rows below the start floor, as a list per frame. **/
	public function floorLandings(k:Int):Null<Array<Array<VHit>>> return floorHits.get(k);

	/** Passes under a block bottom `n` rows below the start floor, as a list per frame. **/
	public function hangPasses(n:Int):Null<Array<Array<VHit>>> return hangHits.get(n);

	// ---- Horizontal ----------------------------------------------------------------

	/**
		The horizontal program `kind` toward `dir` (played now if it wasn't):
		`dist[s]` is how far toward `dir` the player is after s frames of it.
	**/
	public function track(kind:HKind, dir:Int, param:Int = 0, length:Int = -1):HTrack {
		var frames = length < 0 ? this.frames : length;
		var h = new HTrack(kind, dir, param);
		var known = horizontal.get(h.key);
		if (known != null && known.dist.length > frames) return known;
		playHorizontal(h, frames);
		horizontal.set(h.key, h);
		return h;
	}

	/** Plays a horizontal program on a long floor with no jump or down keys. **/
	function playHorizontal(h:HTrack, frames:Int):Void {
		var t = ClipSimulator.TILE;
		var row = 100, col = 1000;
		// Long enough for the fastest run (a speed burst) over every frame.
		var tiles = Std.int(frames * 30 / ClipSimulator.TILE) + 4;
		var floor = [for (c in col - tiles...col + tiles + 1) new LevelBlock(c, row, BlockType.Basic)];
		var area = new ClipArea(floor, col - tiles - 10, row - 10, col + tiles + 10, row + 10);
		var level = area.buildLevel(settings.gravity);
		var startX = col * t + 15.0;
		var player = ClipSimulator.preparePlayer(area, level, startX, row * t, stats[0], stats[1], stats[2], settings.gravity, settings.hats,
			h.item != null ? new ClipItems(h.item) : null);
		h.dist.push(0);
		for (f in 0...frames) {
			player.step(h.inputAt(f));
			h.dist.push((player.x - startX) * h.dir);
		}
	}

	// ---- Solving a corner ------------------------------------------------------------

	/**
		Every start that the physics says clips `corner`: for each floor height
		with landings, each horizontal program and each frame `s` of it, the
		start x window that puts the wall crossing on that frame, cut down to
		spots the player can stand on (`standable(col, row)`); then the
		landings that line up in time. `ceilingAt(col, row, h)` says whether a
		spot has a ceiling exactly `h` tiles up (for the ceiling programs).
		With `solidAt(col, row)`, the predicted path is traced through the level
		and starts that would hit a block before the corner are left out.
	**/
	public function solve(corner:ClipCorner, standable:Int->Int->Bool, ceilingAt:Int->Int->Int->Bool, ?solidAt:Int->Int->Bool):Array<ClipSolution> {
		var out:Array<ClipSolution> = [];
		this.solidAt = solidAt;
		if (corner.kind == CeilingWall) return out;
		var hanging = corner.kind == HangingWall;
		var t = ClipSimulator.TILE;
		var dir = corner.dir;
		var face = corner.wallFace;
		// The row whose top the landing is measured to: the floor, or a hanging block's bottom edge.
		var floorRow = corner.y + 1;
		var tracks = [for (h in horizontal) if (h.dir == dir && h.kind != Sword && h.kind != Laser) h];
		tracks.sort((a, b) -> Reflect.compare(a.key, b.key));
		var reach = 0.0;
		for (h in tracks) for (d in h.dist) reach = Math.max(reach, d);
		var map = hanging ? hangHits : floorHits;
		for (k in map.keys()) {
			var byFrame = map.get(k);
			var startRow = floorRow - k;
			var spots = standingSpans(face, dir, reach + 60, startRow, standable);
			if (spots.length == 0) continue;
			for (h in tracks) solveTrack(corner, h, byFrame, k, startRow, spots, standable, ceilingAt, out);
			// Sword and Laser: the slash or shot is timed to the landing, so each needs its own track.
			if (hasItem(SWORD) || hasItem(LASER_GUN)) {
				var run = track(Run, dir);
				for (s in 2...frames) for (early in [1, 2]) {
					var p = s - 1 - early;
					if (p < 1) continue;
					// Only where the plain run's window is near a spot (the item adds at most ~30 px).
					if (!nearSpan(spots, face, dir, run.dist[s - 1] - 40, run.dist[s] + 40)) continue;
					for (kind in [Sword, Laser]) {
						if (!hasItem(kind == Sword ? SWORD : LASER_GUN)) continue;
						var h = track(kind, dir, p, Std.int(Math.min(frames, p + 4)));
						solveFrame(corner, h, s, byFrame, k, startRow, spots, standable, ceilingAt, out);
					}
				}
			}
		}
		return out;
	}

	/** Solid tiles of the level being solved (null = don't trace paths). **/
	var solidAt:Null<Int->Int->Bool> = null;

	/**
		True when the predicted path (the two tracks put together) stays clear
		of blocks up to the frame before `clipFrame`: the feet, the wall check,
		the middle and the head (lower while charging a super jump), each side.
	**/
	function pathClear(v:VTrack, h:HTrack, x:Float, row:Int, runUp:Int, moveAt:Int, clipFrame:Int):Bool {
		var solid = solidAt;
		if (solid == null) return true;
		var floorY = row * ClipSimulator.TILE;
		var last = h.dist.length - 1;
		for (f in 0...clipFrame) {
			var vi = f - runUp;
			var y = vi >= 0 && vi < v.ys.length ? floorY + v.ys[vi] : floorY;
			var n = f - moveAt + 1;
			var px = x + h.dir * (n <= 0 ? 0 : h.dist[n < last ? n : last]);
			var head = vi >= 0 && vi < v.charge ? 29 : 54;
			var r1 = ClipSimulator.tileOf(y - 1), r2 = ClipSimulator.tileOf(y - 10), r3 = ClipSimulator.tileOf(y - 28), r4 = ClipSimulator.tileOf(y - head);
			var side = -9;
			while (side <= 9) {
				var col = ClipSimulator.tileOf(px + side);
				if (solid(col, r1) || solid(col, r2) || solid(col, r3) || solid(col, r4)) return false;
				side += 18;
			}
		}
		return true;
	}

	/**
		True when the ceiling program's ceiling is there: the same height over
		every column the body passes under from the takeoff to the bump (the
		player may already be running then).
	**/
	static function ceilingOver(v:VTrack, h:HTrack, x:Float, row:Int, runUp:Int, moveAt:Int, ceilingAt:Int->Int->Int->Bool):Bool {
		var last = h.dist.length - 1;
		inline function at(f:Int):Float {
			var n = f - moveAt + 1;
			return x + h.dir * (n <= 0 ? 0 : h.dist[n < last ? n : last]);
		}
		var a = at(runUp), b = at(runUp + v.bumpFrame);
		var c0 = ClipSimulator.tileOf(Math.min(a, b) - 9), c1 = ClipSimulator.tileOf(Math.max(a, b) + 9);
		for (c in c0...c1 + 1) if (!ceilingAt(c, row, v.ceiling)) return false;
		return true;
	}

	function solveTrack(corner:ClipCorner, h:HTrack, byFrame:Array<Array<VHit>>, k:Int, startRow:Int, spots:Array<Span>, standable:Int->Int->Bool,
			ceilingAt:Int->Int->Int->Bool, out:Array<ClipSolution>):Void {
		for (s in 1...h.dist.length) solveFrame(corner, h, s, byFrame, k, startRow, spots, standable, ceilingAt, out);
	}

	/** Solutions where the wall is crossed on frame `s` of horizontal program `h`. **/
	function solveFrame(corner:ClipCorner, h:HTrack, s:Int, byFrame:Array<Array<VHit>>, k:Int, startRow:Int, spots:Array<Span>,
			standable:Int->Int->Bool, ceilingAt:Int->Int->Int->Bool, out:Array<ClipSolution>):Void {
		if (s >= h.dist.length) return;
		var hanging = corner.kind == HangingWall;
		var before = h.dist[s - 1], after = h.dist[s];
		// The wall must be ahead of the leading edge before the frame and behind the feet after it.
		var strictLo = Math.max(before + 10, 10);
		if (!hanging && after < strictLo) return;
		// Hanging: the body midpoint crosses the face (and the leading edge, if the wall check was still at the block's height).
		var looseLo = Math.max(after - 30, 0.5);
		var windows = hanging ? [[looseLo, after, 0], [Math.max(strictLo, looseLo), after, 1]] : [[strictLo, after, 1]];
		for (w in windows) {
			if (w[1] < w[0]) continue;
			var needAbove = hanging && w[2] == 1;
			for (span in spots) {
				// Feet start = face - dir * D for D in the window.
				var a = corner.wallFace - corner.dir * w[1], b = corner.wallFace - corner.dir * w[0];
				var x0 = Math.max(Math.min(a, b), span.x0), x1 = Math.min(Math.max(a, b), span.x1);
				if (x1 < x0) continue;
				// Whole pixels, like the tracks' own start: the game rounds the position
				// every frame, so a start a fraction of a pixel off drifts from the track.
				var x:Float = Math.round((x0 + x1) / 2);
				if (x < x0) x = Math.ceil(x0);
				if (x > x1) x = Math.floor(x1);
				// No whole pixel fits: the window's middle, off by a fraction, tried after the exact ones.
				var off = 0.0;
				if (x < x0 || x > x1) {
					x = Math.round((x0 + x1) / 2 * 4) / 4;
					off = BLOCKED_PATH / 2;
				}
				pickLandings(corner, h, s, x, off, byFrame, k, startRow, hanging ? needAbove : null, standable, ceilingAt, out);
			}
		}
	}

	/**
		Landings that line up with crossing on frame `s` of `h` from `x`: moving
		starts `t + 1 - s` frames into the jump (no sooner than the program
		allows), or, for a plain jump, a run-up of `s - 1 - t` frames comes first.
	**/
	function pickLandings(corner:ClipCorner, h:HTrack, s:Int, x:Float, off:Float, byFrame:Array<Array<VHit>>, k:Int, startRow:Int, prevAbove:Null<Bool>,
			standable:Int->Int->Bool, ceilingAt:Int->Int->Int->Bool, out:Array<ClipSolution>):Void {
		var col = ClipSimulator.tileOf(x);
		var taken:Map<String, Int> = new Map();
		var distance = off + Math.abs(corner.wallFace - x) + Math.abs(k) * ClipSimulator.TILE;
		inline function family(v:VTrack):String return (v.ceiling > 0 ? "c" : "") + (v.charge > 0 ? "s" : v.item != null ? "i" : "j");
		// Score added for a usable landing (-1 = not usable): a path that hits a
		// block on the way goes after every clear one (a small bump can still clip).
		function usable(hit:VHit, runUp:Int, moveAt:Int):Float {
			if (prevAbove != null && hit.prevAbove != prevAbove) return -1;
			var v = hit.v;
			if (v.item != null && h.item != null) return -1;
			if (v.ceiling > 0 && !ceilingOver(v, h, x, startRow, runUp, moveAt, ceilingAt)) return -1;
			var fam = family(v);
			inline function full(f:String):Bool return taken.exists(f) && taken.get(f) >= PER_SPOT;
			if (full(fam) && full(fam + "!")) return -1;
			var clear = pathClear(v, h, x, startRow, runUp, moveAt, runUp + hit.frame);
			var f = fam + (clear ? "" : "!");
			if (full(f)) return -1;
			var n = taken.exists(f) ? taken.get(f) : 0;
			taken.set(f, n + 1);
			return clear ? 0 : BLOCKED_PATH;
		}
		// Moving starts after the jump does (TurnBack starts with it).
		for (t in Std.int(Math.max(1, s - 1))...byFrame.length) {
			var hits = byFrame[t];
			if (hits == null) continue;
			var moveAt = t + 1 - s;
			for (hit in hits) {
				if (moveAt < hit.v.moveFrom) continue;
				if (h.kind == TurnBack && moveAt != 0) continue;
				var extra = usable(hit, 0, moveAt);
				if (extra < 0) continue;
				out.push(new ClipSolution(hit.v, h, x, startRow, 0, moveAt, hit.frame, extra + distance + (moveAt - hit.v.moveFrom) * 0.5));
			}
		}
		// A run-up first: only plain jumps (a super jump's charge stops the player), on floor that runs to the takeoff.
		if (h.kind != Run && h.kind != Burst) return;
		var t = s - 2;
		while (t >= 1) {
			var hits = byFrame[t];
			var runUp = s - 1 - t;
			t--;
			if (hits == null) continue;
			if (!floorRuns(x, h.dir, h.dist[runUp], startRow, standable)) break;
			for (hit in hits) {
				if (hit.v.charge > 0 || hit.v.moveFrom > 0) continue;
				var extra = usable(hit, runUp, 0);
				if (extra < 0) continue;
				out.push(new ClipSolution(hit.v, h, x, startRow, runUp, 0, runUp + hit.frame, extra + distance + runUp * 0.25));
			}
		}
	}

	/** Floor to stand on all the way from x to `run` px further along `dir`. **/
	static function floorRuns(x:Float, dir:Int, run:Float, row:Int, standable:Int->Int->Bool):Bool {
		var a = ClipSimulator.tileOf(x), b = ClipSimulator.tileOf(x + dir * run);
		var step = b >= a ? 1 : -1;
		var c = a;
		while (true) {
			if (!standable(c, row)) return false;
			if (c == b) return true;
			c += step;
		}
	}

	/** Runs of standable tiles on `row` within `reach` px before the face (facing `dir`). **/
	static function standingSpans(face:Float, dir:Int, reach:Float, row:Int, standable:Int->Int->Bool):Array<Span> {
		var t = ClipSimulator.TILE;
		var near = ClipSimulator.tileOf(face - dir * 0.5);
		var far = ClipSimulator.tileOf(face - dir * reach);
		var lo = Std.int(Math.min(near, far)), hi = Std.int(Math.max(near, far));
		var spans:Array<Span> = [];
		var open:Null<Span> = null;
		for (c in lo...hi + 1) {
			if (standable(c, row)) {
				if (open == null) spans.push(open = new Span(c * t + 0.5, c * t + t - 0.5));
				else open.x1 = c * t + t - 0.5;
			} else {
				open = null;
			}
		}
		return spans;
	}

	static function nearSpan(spots:Array<Span>, face:Float, dir:Int, dLo:Float, dHi:Float):Bool {
		var a = face - dir * dHi, b = face - dir * dLo;
		var x0 = Math.min(a, b), x1 = Math.max(a, b);
		for (s in spots) if (s.x1 >= x0 && s.x0 <= x1) return true;
		return false;
	}

	// ---- Putting them together -------------------------------------------------------

	/** The attempt for a solution (started at `x`, normally the solved start). **/
	public function attempt(sol:ClipSolution, ?x:Float):ClipAttempt {
		if (x == null) x = sol.x;
		var v = sol.v, h = sol.h;
		var length = sol.runUp + v.ys.length + 40;
		var script = [for (f in 0...length) {
			var vi = f >= sol.runUp ? v.inputAt(f - sol.runUp) : new LocalPlayerInput();
			var hi = f >= sol.moveAt ? h.inputAt(f - sol.moveAt) : new LocalPlayerInput();
			new LocalPlayerInput(hi.left, hi.right, vi.jump, vi.down, vi.item || hi.item);
		}];
		var a = new ClipAttempt(x, sol.row * ClipSimulator.TILE, stats[0], stats[1], stats[2], settings.gravity, h.dir, 0, 0, false, length);
		a.script = script;
		a.hats = settings.hats;
		var item = v.item != null ? v.item : h.item;
		if (item != null) a.items = new ClipItems(item);
		a.courseRotation = settings.courseRotation;
		var run = sol.runUp > 0 ? 'run ${sol.runUp} frames, then ' : '';
		a.label = '$run${v.label}, ${h.describe(sol.moveAt)} (predicted)';
		return a;
	}
}

/** A solved start: vertical and horizontal programs, the spot, a run-up and when moving starts. **/
class ClipSolution {
	public final v:VTrack;
	public final h:HTrack;
	public final x:Float;
	public final row:Int;
	public final runUp:Int;
	public final moveAt:Int;
	/** The frame (0-based step) the player is predicted to land in the corner. **/
	public final clipFrame:Int;
	/** Lower is tried first (nearer starts, less waiting). **/
	public final score:Float;

	public function new(v:VTrack, h:HTrack, x:Float, row:Int, runUp:Int, moveAt:Int, clipFrame:Int, score:Float) {
		this.v = v;
		this.h = h;
		this.x = x;
		this.row = row;
		this.runUp = runUp;
		this.moveAt = moveAt;
		this.clipFrame = clipFrame;
		this.score = score;
	}
}

private class Span {
	public var x0:Float;
	public var x1:Float;

	public function new(x0:Float, x1:Float) {
		this.x0 = x0;
		this.x1 = x1;
	}
}

/** A vertical program (jump/down/item keys only) and what it does. **/
class VTrack {
	public final label:String;
	/** Frames jump is held (999 = all), super jump charge frames (0 = none), fast-fall from (-1 = never), item at (-1 = none). **/
	public final hold:Int;
	public final charge:Int;
	public final fastFall:Int;
	public final itemAt:Int;
	public final item:Null<Int>;
	/** Tiles of air under a ceiling it is played with (0 = none). **/
	public final ceiling:Int;
	/** Earliest frame horizontal moving may start (a super jump's charge holds the player still). **/
	public var moveFrom:Int;
	/** Under a ceiling: the frame the bump stops the rise (-1 = none). **/
	public var bumpFrame:Int = -1;
	/** Feet height after each frame, relative to the start floor (down is positive). **/
	public var ys:Array<Float> = [];

	function new(label:String, hold:Int, charge:Int, fastFall:Int, itemAt:Int, item:Null<Int>, ceiling:Int, moveFrom:Int) {
		this.label = label;
		this.hold = hold;
		this.charge = charge;
		this.fastFall = fastFall;
		this.itemAt = itemAt;
		this.item = item;
		this.ceiling = ceiling;
		this.moveFrom = moveFrom;
	}

	static function ffText(d:Int):String return d < 0 ? "" : ', fast-fall from frame $d';

	static function ceilText(h:Int):String return h > 0 ? ' into the ceiling $h tiles up' : "";

	public static function jump(hold:Int, fastFall:Int, ceiling:Int = 0):VTrack {
		return new VTrack('jump held ${hold >= 999 ? "all" : Std.string(hold)}${ceilText(ceiling)}${ffText(fastFall)}', hold, 0, fastFall, -1, null,
			ceiling, 0);
	}

	public static function superJump(charge:Int, fastFall:Int, ceiling:Int = 0):VTrack {
		return new VTrack('super jump (charge $charge)${ceilText(ceiling)}${ffText(fastFall)}', 0, charge, fastFall, -1, null, ceiling,
			charge);
	}

	/** The Super Jump item: alone from the ground (at = -1, used on frame 1), or during a full jump on frame `at`. **/
	public static function itemJump(at:Int, fastFall:Int):VTrack {
		var label = at < 0 ? 'super jump item${ffText(fastFall)}' : 'full jump, super jump item on frame $at${ffText(fastFall)}';
		return new VTrack(label, at < 0 ? 0 : 999, 0, fastFall, at < 0 ? 1 : at, 5, 0, 0);
	}

	public function inputAt(f:Int):LocalPlayerInput {
		var jump = charge == 0 && f < hold;
		var down = charge > 0 ? f < charge : false;
		if (fastFall >= 0 && f >= fastFall && (charge == 0 || f >= charge)) down = true;
		return new LocalPlayerInput(false, false, jump, down, f == itemAt);
	}
}

/** A landing (or a pass under a block bottom) of a vertical program: its frame, and whether the wall check was still above the bottom the frame before. **/
class VHit {
	public final v:VTrack;
	public final frame:Int;
	public final prevAbove:Bool;

	public function new(v:VTrack, frame:Int, prevAbove:Bool) {
		this.v = v;
		this.frame = frame;
		this.prevAbove = prevAbove;
	}
}

enum HKind {
	/** Hold toward the wall from the start. **/
	Run;
	/** The same with a Speed Burst on its second frame. **/
	Burst;
	/** Hold away for `param` frames, then toward (a hop back at a wall). **/
	TurnBack;
	/** Run, slashing the Sword on frame `param` (it lunges forward). **/
	Sword;
	/** Run, turning away on frame `param - 1` and firing the Laser on `param` (the recoil kicks toward the wall). **/
	Laser;
}

/** A horizontal program (left/right/item keys) and how far toward `dir` it carries the player. **/
class HTrack {
	public final kind:HKind;
	public final dir:Int;
	public final param:Int;
	/** Distance toward `dir` after s frames (dist[0] = 0). **/
	public final dist:Array<Float> = [];

	public function new(kind:HKind, dir:Int, param:Int) {
		this.kind = kind;
		this.dir = dir;
		this.param = param;
	}

	public var key(get, never):String;
	inline function get_key():String return '$kind:$dir:$param';

	public var item(get, never):Null<Int>;
	function get_item():Null<Int> {
		return switch (kind) {
			case Burst: 7;
			case Sword: 8;
			case Laser: 1;
			default: null;
		}
	}

	public function inputAt(f:Int):LocalPlayerInput {
		var toward = true, use = false;
		switch (kind) {
			case Run:
			case Burst:
				use = f == 1;
			case TurnBack:
				toward = f >= param;
			case Sword:
				use = f == param;
			case Laser:
				toward = f < param - 1;
				use = f == param;
		}
		var right = toward ? dir == 1 : dir == -1;
		return new LocalPlayerInput(!right, right, false, false, use);
	}

	public function describe(moveAt:Int):String {
		var side = dir == 1 ? "right" : "left";
		return switch (kind) {
			case Run: 'hold $side from frame $moveAt';
			case Burst: 'hold $side with a speed burst from frame $moveAt';
			case TurnBack: 'hold away for $param frames, then $side';
			case Sword: 'hold $side from frame $moveAt, slash on frame ${moveAt + param}';
			case Laser: 'hold $side from frame $moveAt, turn and fire on frame ${moveAt + param}';
		}
	}
}

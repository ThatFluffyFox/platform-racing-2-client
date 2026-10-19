package pr2.gameplay.debug;

import pr2.gameplay.debug.ClipScanner.ClipCorner;
import pr2.gameplay.debug.ClipScanner.CornerKind;
import pr2.gameplay.debug.ClipScanner.ClipPortal;
import pr2.gameplay.debug.ClipScanner.ClipScanSettings;
import pr2.gameplay.debug.ClipSimulator.ClipArea;
import pr2.gameplay.debug.ClipSimulator.ClipAttempt;
import pr2.gameplay.debug.ClipSolver.ClipSolution;
import pr2.level.Level.LevelBlock;

/**
	Stage 1.5 of the Clip Finder: predicted clips. Instead of trying run-ups
	at every corner, it solves the physics backwards from how a clip happens
	(see ClipSolver):

	1. The player's vertical motion (every jump hold, super jump charge,
	   fast-fall, the Super Jump item, ceiling bumps) and horizontal motion
	   (running, Speed Burst, turning back, Sword and Laser timed to a frame)
	   are each played once with the real physics and the player's stats,
	   gravity and hats. In the air the two don't affect each other, so any
	   flight is one of each put together.
	2. For each corner it works out exactly where to stand and on which frame
	   to start moving (or how long to run first) so the landing frame and
	   the wall crossing fall on the same frame, at every height the player
	   can stand at near the corner.
	3. Those starts are checked with the real physics in the real level,
	   nearest first. The first that clips becomes the corner's ClipPortal,
	   like Stage 1.

	It works in slices (`step`) so the race keeps running.
**/
class ClipPredictor implements CornerScan {
	/** Most solved starts checked per corner. **/
	public static inline var MAX_CANDIDATES:Int = 160;
	/** A predicted clip must happen within this many tiles of its corner. **/
	static inline var NEAR_TILES:Int = 2;

	static inline var LASER_GUN:Int = 1;
	static inline var SUPER_JUMP:Int = 5;
	static inline var SPEED_BURST:Int = 7;
	static inline var SWORD:Int = 8;

	public final settings:ClipScanSettings;
	public final corners:Array<ClipCorner>;
	public final portals:Array<ClipPortal> = [];
	public final solidCorners:Array<ClipCorner> = [];
	public var cornerIndex(default, null):Int = 0;
	/** Real-physics runs made (programs played and starts checked). **/
	public var tested(default, null):Int = 0;
	/** One solver per stat set. **/
	public final solvers:Array<ClipSolver> = [];

	/** Programs (vertical and horizontal, every stat set) to play, and played. **/
	public var trackCount(get, never):Int;
	function get_trackCount():Int {
		var n = 0;
		for (s in solvers) n += s.trackCount;
		return n;
	}
	public var tracksPlayed(get, never):Int;
	function get_tracksPlayed():Int {
		var n = 0;
		for (s in solvers) n += s.tracksPlayed;
		return n;
	}

	final blocks:Array<LevelBlock>;
	/** Solid tiles as the player sees them, as a flat grid (looked up for every frame of every solved path). **/
	var grid:haxe.io.Bytes;
	var gridX:Int = 0;
	var gridY:Int = 0;
	var gridW:Int = 0;
	var gridH:Int = 0;
	/** Starts for the corner being checked (solved when it starts). **/
	var candidates:Null<Array<Candidate>> = null;
	var candidateIndex:Int = 0;

	public function new(blocks:Array<LevelBlock>, settings:ClipScanSettings) {
		this.blocks = blocks;
		this.settings = settings;
		// Corners and standing spots as the player sees them on the turned course.
		var seen = ClipSimulator.layoutFor(blocks, settings.courseRotation);
		var solids = [for (b in seen) if (!b.isMarker() && b.type.isSolid()) b];
		if (solids.length > 0) {
			var x0 = solids[0].x, y0 = solids[0].y, x1 = x0, y1 = y0;
			for (b in solids) {
				if (b.x < x0) x0 = b.x;
				if (b.x > x1) x1 = b.x;
				if (b.y < y0) y0 = b.y;
				if (b.y > y1) y1 = b.y;
			}
			gridX = x0;
			gridY = y0;
			gridW = x1 - x0 + 1;
			gridH = y1 - y0 + 1;
		}
		grid = haxe.io.Bytes.alloc(gridW * gridH);
		for (b in solids) grid.set((b.y - gridY) * gridW + (b.x - gridX), 1);
		corners = ClipScanner.findCorners(seen, 1).concat(ClipScanner.findCorners(seen, -1));
		if (settings.wallClips) corners = corners.concat(ClipScanner.findWallCorners(seen));
		// Mine spots have no landing to predict; they go straight to Stage 1's mine moves.
		if (settings.mines && settings.predictFallback) corners = corners.concat(ClipScanner.findMineSpots(seen));
		var ox = settings.originX, oy = settings.originY;
		corners.sort((a, b) -> Reflect.compare(distanceSq(a, ox, oy), distanceSq(b, ox, oy)));
		var statSets = settings.statSets != null && settings.statSets.length > 0 ? settings.statSets : [[settings.speed, settings.accel, settings.jump]];
		var items:Array<Int> = [];
		var wanted = [settings.heldItem].concat(settings.extraItems);
		for (item in wanted) if (item != null && ClipScanner.CLIP_ITEMS.indexOf(item) >= 0 && items.indexOf(item) < 0) items.push(item);
		for (stats in statSets) solvers.push(new ClipSolver(settings, stats, items));
	}

	public var done(get, never):Bool;
	function get_done():Bool return cornerIndex >= corners.length;

	public function progressText(stopped:Bool):String {
		if (predicting) return 'Solving the physics ${tracksPlayed}/${trackCount}...';
		var total = corners.length;
		var stage = fallback != null ? " (Stage 1 moves)" : "";
		return '${stopped ? "Stopped at" : "Checking"} ${Std.int(Math.min(cornerIndex + 1, total))}/$total corners/mines$stage, ${portals.length} clip';
	}

	public function doneText():String {
		return 'Prediction done: ${portals.length} of ${corners.length} corners/mines clip (${portals.length - fallbackFound} predicted, ${trackCount} programs)';
	}

	/** True while the motion programs are still being played (before any corner is checked). **/
	public var predicting(get, never):Bool;
	function get_predicting():Bool {
		for (s in solvers) if (!s.ready) return true;
		return false;
	}

	/** Runs physics until `maxRuns` runs or `deadline()` says time is up. Returns runs made. **/
	public function step(maxRuns:Int, ?deadline:Void->Bool):Int {
		var runs = 0;
		inline function out():Bool return runs >= maxRuns || (deadline != null && runs > 0 && deadline());
		for (solver in solvers) {
			while (!solver.ready && !out()) {
				var made = solver.step(1);
				runs += made;
				tested += made;
			}
		}
		if (predicting) return runs;
		while (!done && !out()) {
			var corner = corners[cornerIndex];
			if (candidates == null) {
				candidates = corner.mine != null ? [] : candidatesFor(corner);
				candidateIndex = 0;
			}
			if (candidateIndex >= candidates.length) {
				// Nothing solved clips it: Stage 1's own attempts at this corner
				// (hop-backs, run-ups, item moves, mines) before giving up on it.
				if (!settings.predictFallback) {
					solidCorners.push(corner);
					nextCorner();
					continue;
				}
				var scan = fallback;
				if (scan == null) fallback = scan = new ClipScanner(blocks, settings, corner);
				var made = scan.step(maxRuns - runs, deadline);
				runs += made;
				tested += made;
				if (scan.portals.length > 0) {
					portals.push(scan.portals[0]);
					fallbackFound++;
					nextCorner();
				} else if (scan.done) {
					solidCorners.push(corner);
					nextCorner();
				}
				continue;
			}
			var picked = candidates[candidateIndex++];
			var attempt = picked.solver.attempt(picked.sol, picked.x);
			runs++;
			var area = areaFor(corner, attempt);
			var result = ClipSimulator.run(area, attempt);
			if (result.startBlocked) continue;
			tested++;
			if (!result.clipped || !nearCorner(corner, result.x, result.y)) continue;
			var portal = new ClipPortal(corner, attempt, ClipScanner.follow(area, attempt, settings.followFrames));
			if (settings.passThroughOnly && !portal.passesThrough) continue;
			portals.push(portal);
			nextCorner();
		}
		return runs;
	}

	function nextCorner():Void {
		cornerIndex++;
		candidates = null;
		fallback = null;
	}

	/** Stage 1's attempts at the current corner, once nothing solved clips it. **/
	var fallback:Null<ClipScanner> = null;
	/** Clips found by those (the rest were predicted). **/
	public var fallbackFound(default, null):Int = 0;

	// ---- Corners -----------------------------------------------------------------

	/** The solved starts for `corner` with every stat set, nearest and simplest first. **/
	function candidatesFor(corner:ClipCorner):Array<Candidate> {
		var solutions:Array<{solver:ClipSolver, sol:ClipSolution}> = [];
		for (solver in solvers) {
			for (sol in solver.solve(corner, standable, ceilingAt, solidAt)) solutions.push({solver: solver, sol: sol});
		}
		solutions.sort((p, q) -> Reflect.compare(p.sol.score, q.sol.score));
		var list:Array<Candidate> = [];
		var seen:Map<String, Bool> = new Map();
		for (s in solutions) {
			var sol = s.sol;
			// A turned course puts block edges 1 px further along a flipped axis: try either side too.
			var xs = settings.courseRotation == 0 ? [sol.x] : [sol.x, sol.x - 1, sol.x + 1];
			for (x in xs) {
				var id = '${sol.v.label}|${sol.h.key}|$x|${sol.row}|${sol.runUp}|${sol.moveAt}|${s.solver.stats}';
				if (seen.exists(id)) continue;
				seen.set(id, true);
				list.push(new Candidate(s.solver, sol, x));
			}
			if (list.length >= MAX_CANDIDATES) break;
		}
		if (list.length > MAX_CANDIDATES) list.resize(MAX_CANDIDATES);
		return list;
	}

	/** Exactly `h` tiles of air above the floor tile (col, floorRow), then a solid block. **/
	function ceilingAt(col:Int, floorRow:Int, h:Int):Bool {
		for (dy in 1...h + 1) if (solidAt(col, floorRow - dy)) return false;
		return solidAt(col, floorRow - h - 1);
	}

	function solidAt(col:Int, row:Int):Bool {
		var x = col - gridX, y = row - gridY;
		return x >= 0 && y >= 0 && x < gridW && y < gridH && grid.get(y * gridW + x) == 1;
	}

	/** A solid floor tile with two air tiles above it. **/
	function standable(col:Int, floorRow:Int):Bool {
		return solidAt(col, floorRow) && !solidAt(col, floorRow - 1) && !solidAt(col, floorRow - 2);
	}

	function nearCorner(corner:ClipCorner, x:Float, y:Float):Bool {
		var tx = ClipSimulator.tileOf(x), ty = ClipSimulator.tileOf(y - 1);
		// A hanging corner's clip is in the block itself (the row of the corner).
		var row = corner.kind == HangingWall ? corner.y : corner.y + 1;
		return Math.abs(tx - corner.wallTileX) <= NEAR_TILES && Math.abs(ty - row) <= NEAR_TILES;
	}

	function areaFor(corner:ClipCorner, attempt:ClipAttempt):ClipArea {
		var sx = ClipSimulator.tileOf(attempt.startX), sy = ClipSimulator.tileOf(attempt.startY);
		return ClipArea.forCourse(blocks, Std.int(Math.min(sx, corner.x)) - 8, Std.int(Math.min(sy, corner.y)) - 16,
			Std.int(Math.max(sx, corner.x)) + 8, Std.int(Math.max(sy, corner.y)) + 6, settings.courseRotation);
	}

	static function distanceSq(corner:ClipCorner, x:Float, y:Float):Float {
		var dx = corner.wallFace - x, dy = corner.floorY - y;
		return dx * dx + dy * dy;
	}
}

/** A solved start to check (its attempt is built when it is checked). **/
private class Candidate {
	public final solver:ClipSolver;
	public final sol:ClipSolution;
	public final x:Float;

	public function new(solver:ClipSolver, sol:ClipSolution, x:Float) {
		this.solver = solver;
		this.sol = sol;
		this.x = x;
	}
}

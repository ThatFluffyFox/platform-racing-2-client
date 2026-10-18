package pr2.gameplay.debug;

import pr2.gameplay.debug.ClipScanner.ClipCorner;
import pr2.gameplay.debug.ClipScanner.CornerKind;
import pr2.gameplay.debug.ClipScanner.ClipPortal;
import pr2.gameplay.debug.ClipScanner.ClipScanSettings;
import pr2.gameplay.debug.ClipSimulator.ClipArea;
import pr2.gameplay.debug.ClipSimulator.ClipAttempt;
import pr2.gameplay.debug.ClipSimulator.ClipItems;
import pr2.level.BlockType;
import pr2.level.Level.LevelBlock;

/**
	Stage 1.5 of the Clip Finder: predicted clips. Instead of trying run-ups
	at every corner, it works backwards from how a clip happens.

	A corner clips when the player lands more than 10 px into its floor while
	moving at least 10 px a frame into its wall: the wall check (10 px above
	the feet) is then inside the floor row, so nothing pushes the player out,
	and the feet end up in the wall column with the wall above. So:

	1. Each launch (jumps, super jumps, and every item move: Speed Burst,
	   Super Jump item, Sword slash and Laser recoil timed to the landing) is
	   simulated once with the real physics on open ground, with the floor
	   ending where the player takes off, so the flight carries on below the
	   start height. That gives its positions and speeds on every frame.
	2. Every frame that lands deep and fast enough is a "hit": for each floor
	   height it crosses, it says exactly how far before the wall the launch
	   must start (a window a few px wide).
	3. For each corner in the level, each hit names a start row and an x
	   window; any spot there the player can stand on is a candidate, from
	   any distance (a launch can cross half the level).
	4. Candidates are checked with the real physics in the real level. The
	   first that clips becomes the corner's ClipPortal, like Stage 1.

	It works in slices (`step`) so the race keeps running.
**/
class ClipPredictor implements CornerScan {
	/** Frames each launch is followed in open air. **/
	public static inline var FLIGHT_FRAMES:Int = 160;
	/** Most candidate starts checked per corner. **/
	public static inline var MAX_CANDIDATES:Int = 160;
	/** A predicted clip must happen within this many tiles of its corner. **/
	static inline var NEAR_TILES:Int = 2;
	/** Rows below the open-ground start the flight is followed to (deeper corners). **/
	static inline var MAX_DROP_ROWS:Int = 30;
	/** Rows above (corners higher than the start). **/
	static inline var MAX_RISE_ROWS:Int = 20;

	static inline var LASER_GUN:Int = 1;
	static inline var SUPER_JUMP:Int = 5;
	static inline var SPEED_BURST:Int = 7;
	static inline var SWORD:Int = 8;

	public final settings:ClipScanSettings;
	public final corners:Array<ClipCorner>;
	public final portals:Array<ClipPortal> = [];
	public final solidCorners:Array<ClipCorner> = [];
	public var cornerIndex(default, null):Int = 0;
	/** Real-physics checks made (flights and candidates). **/
	public var tested(default, null):Int = 0;
	/** Launches (with every stat set, item and direction) still to fly, and flown. **/
	public var launchesFlown(default, null):Int = 0;
	public var launchCount(get, never):Int;
	inline function get_launchCount():Int return pending.length + launchesFlown;

	final blocks:Array<LevelBlock>;
	final solid:Map<Int, Bool> = new Map();
	final pending:Array<PredictLaunch> = [];
	final flown:Array<PredictLaunch> = [];
	/** Candidates for the corner being checked (built when it starts). **/
	var candidates:Null<Array<ClipAttempt>> = null;
	var candidateIndex:Int = 0;

	public function new(blocks:Array<LevelBlock>, settings:ClipScanSettings) {
		this.blocks = blocks;
		this.settings = settings;
		// Corners and standing spots as the player sees them on the turned course.
		var seen = ClipSimulator.layoutFor(blocks, settings.courseRotation);
		for (b in seen) if (!b.isMarker() && b.type.isSolid()) solid.set(key(b.x, b.y), true);
		corners = ClipScanner.findCorners(seen, 1).concat(ClipScanner.findCorners(seen, -1));
		if (settings.wallClips) corners = corners.concat(ClipScanner.findWallCorners(seen));
		// Mine spots have no landing to predict; they go straight to Stage 1's mine moves.
		if (settings.mines && settings.predictFallback) corners = corners.concat(ClipScanner.findMineSpots(seen));
		var ox = settings.originX, oy = settings.originY;
		corners.sort((a, b) -> Reflect.compare(distanceSq(a, ox, oy), distanceSq(b, ox, oy)));
		var statSets = settings.statSets != null && settings.statSets.length > 0 ? settings.statSets : [[settings.speed, settings.accel, settings.jump]];
		var items:Array<Null<Int>> = [null];
		var wanted = [settings.heldItem].concat(settings.extraItems);
		for (item in wanted) if (item != null && ClipScanner.CLIP_ITEMS.indexOf(item) >= 0 && items.indexOf(item) < 0) items.push(item);
		for (stats in statSets) for (dir in [1, -1]) for (item in items) for (launch in launchesFor(stats, dir, item)) pending.push(launch);
	}

	public var done(get, never):Bool;
	function get_done():Bool return cornerIndex >= corners.length;

	public function progressText(stopped:Bool):String {
		if (predicting) return 'Predicting launches ${launchesFlown}/${launchCount}...';
		var total = corners.length;
		var stage = fallback != null ? " (Stage 1 moves)" : "";
		return '${stopped ? "Stopped at" : "Checking"} ${Std.int(Math.min(cornerIndex + 1, total))}/$total corners/mines$stage, ${portals.length} clip';
	}

	public function doneText():String {
		return 'Prediction done: ${portals.length} of ${corners.length} corners/mines clip (${portals.length - fallbackFound} predicted, ${launchesFlown} launches)';
	}

	/** True while launches are still being flown (before any corner is checked). **/
	public var predicting(get, never):Bool;
	inline function get_predicting():Bool return pending.length > 0;

	/** Runs physics until `maxRuns` runs or `deadline()` says time is up. Returns runs made. **/
	public function step(maxRuns:Int, ?deadline:Void->Bool):Int {
		var runs = 0;
		inline function out():Bool return runs >= maxRuns || (deadline != null && runs > 0 && deadline());
		while (pending.length > 0 && !out()) {
			var launch = pending.shift();
			fly(launch);
			runs++;
			tested++;
			launchesFlown++;
			flown.push(launch);
			// Sword and laser moves are timed to a landing: once the plain flight is known, fly each timing.
			for (timed in launch.timedVariants()) pending.push(timed);
		}
		while (!done && !out()) {
			var corner = corners[cornerIndex];
			if (candidates == null) {
				candidates = corner.mine != null ? [] : candidatesFor(corner);
				candidateIndex = 0;
			}
			if (candidateIndex >= candidates.length) {
				// Nothing predicted clips it: Stage 1's own attempts at this corner
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
			var attempt = candidates[candidateIndex++];
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

	/** Stage 1's attempts at the current corner, once nothing predicted clips it. **/
	var fallback:Null<ClipScanner> = null;
	/** Clips found by those (the rest were predicted). **/
	public var fallbackFound(default, null):Int = 0;

	// ---- Launches ----------------------------------------------------------------

	/**
		The launches tried (facing `dir`) with one stat set and item: run-up
		jumps of every height, super jumps (running in or standing until the
		release), and the item's own moves.
	**/
	function launchesFor(stats:Array<Float>, dir:Int, item:Null<Int>):Array<PredictLaunch> {
		var s = settings;
		var list:Array<PredictLaunch> = [];
		inline function base(jumpFrame:Int, hold:Int, fastFall:Bool):ClipAttempt {
			return new ClipAttempt(0, 0, stats[0], stats[1], stats[2], s.gravity, dir, jumpFrame, hold, fastFall, FLIGHT_FRAMES);
		}
		inline function superJump(charge:Int, standing:Bool, fastFall:Bool):ClipAttempt {
			var a = base(0, 0, fastFall);
			a.superCharge = charge;
			if (standing) a.moveStart = charge;
			return a;
		}
		var runs = s.predictRunFrames, holds = s.predictHolds, charges = s.predictCharges;
		// The burst needs a frame of its own first; sword and laser moves fly fewer launches (each is timed per landing).
		var burstRuns:Array<Int> = [];
		for (j in runs) if (burstRuns.indexOf(Std.int(Math.max(1, j))) < 0) burstRuns.push(Std.int(Math.max(1, j)));
		var burstHolds = [for (h in holds) if (h == 999 || h == 8 || h == 2) h];
		if (burstHolds.length == 0) burstHolds = holds;
		var timedRuns = [for (j in runs) if (j <= 20 && j % 10 == 0) j];
		if (timedRuns.length == 0) timedRuns = runs;
		var timedHolds = [for (h in holds) if (h == 999 || h == 8) h];
		if (timedHolds.length == 0) timedHolds = holds;
		var timedCharges = [for (c in charges) if (c >= 35) c];
		switch (item) {
			case null:
				for (jumpFrame in runs) for (hold in holds) for (ff in [true, false]) {
					list.push(new PredictLaunch(base(jumpFrame, hold, ff), null, 'run ${jumpFrame} frames, jump held ${holdText(hold)}${ff ? ", fast-fall" : ""}'));
				}
				for (charge in charges) for (standing in [false, true]) for (ff in [true, false]) {
					list.push(new PredictLaunch(superJump(charge, standing, ff), null,
						'super jump (charge $charge${standing ? ", standing until the release" : ""})${ff ? ", fast-fall" : ""}'));
				}
			case SPEED_BURST:
				for (jumpFrame in burstRuns) for (hold in burstHolds) for (ff in [true, false]) {
					var a = base(jumpFrame, hold, ff);
					a.itemAt = 0;
					list.push(new PredictLaunch(a, item, 'speed burst, run ${jumpFrame} frames, jump held ${holdText(hold)}${ff ? ", fast-fall" : ""}'));
				}
				for (charge in charges) for (late in [false, true]) for (standing in [false, true]) for (ff in [true, false]) {
					var a = superJump(charge, standing, ff);
					a.itemAt = late ? charge - 2 : 1;
					list.push(new PredictLaunch(a, item, 'speed burst while charging a super jump (charge $charge, burst on frame ${a.itemAt}'
						+ (standing ? ', standing until the release' : '') + ')${ff ? ", fast-fall" : ""}'));
				}
			case SUPER_JUMP:
				for (jumpFrame in runs) for (ff in [true, false]) {
					var a = base(jumpFrame, 0, ff);
					a.jumpWithItem = true;
					list.push(new PredictLaunch(a, item, 'run ${jumpFrame} frames, super jump item${ff ? ", fast-fall" : ""}'));
				}
			case SWORD | LASER_GUN:
				// Flown plain first; each landing frame then gets its own timed slash or shot.
				for (jumpFrame in timedRuns) for (hold in timedHolds) {
					var a = base(jumpFrame, hold, true);
					list.push(new PredictLaunch(a, item, 'run ${jumpFrame} frames, jump held ${holdText(hold)}, fast-fall', true));
				}
				for (charge in timedCharges) for (standing in [false, true]) {
					list.push(new PredictLaunch(superJump(charge, standing, true), item,
						'super jump (charge $charge${standing ? ", standing until the release" : ""}), fast-fall', true));
				}
			default:
		}
		return list;
	}

	static function holdText(hold:Int):String return hold >= 999 ? "all" : Std.string(hold);

	/**
		Flies a launch on open ground: once on a long floor to find where it
		takes off, then with the floor ending there so the flight goes on below
		the start height. Records its hits (frames that land deep and fast).
	**/
	function fly(launch:PredictLaunch):Void {
		var proto = launch.attempt;
		var t = ClipSimulator.TILE;
		var startCol = 200, floorRow = 100;
		var startX = startCol * t + 15.0, floorY = floorRow * t * 1.0;
		var dir = proto.dir;
		var takeoff = flight(launch, startX, floorY, startCol - 190, startCol + 190, floorRow, true).takeoffCol;
		var minCol = dir == 1 ? startCol - 190 : takeoff;
		var maxCol = dir == 1 ? takeoff : startCol + 190;
		var path = flight(launch, startX, floorY, minCol, maxCol, floorRow, false);
		launch.path = path.xs;
		launch.pathY = path.ys;
		launch.hits = [];
		launch.hangHits = [];
		var xs = path.xs, ys = path.ys;
		for (f in 1...xs.length) {
			var x0 = (xs[f - 1] - startX) * dir, x1 = (xs[f] - startX) * dir;
			var y0 = ys[f - 1] - floorY, y1 = ys[f] - floorY;
			// The wall must be past the leading edge before the frame and behind the feet after it.
			var lo = x0 + 10, hi = x1;
			if (hi < lo) continue;
			// Floor tops (relative rows) the feet pass more than 10 px through this frame.
			var kMin = Math.ceil(y0 / t), kMax = Math.floor((y1 - 10.01) / t);
			for (k in kMin...kMax + 1) {
				if (k * t <= y0 || k < -MAX_RISE_ROWS || k > MAX_DROP_ROWS) continue;
				launch.hits.push(new PredictHit(f, k, lo, hi));
			}
			// Hanging corners: the feet 10-15 px below a block's bottom edge as the
			// body midpoint crosses into its column. If the wall check (10 px above
			// the feet) was still at the block's height the frame before, the
			// leading edge must not have reached it yet.
			var bottom = Math.ceil((y1 - 15) / t) * t;
			if (bottom < y1 - 10 && bottom > y1 - 15) {
				var n = Std.int(bottom / t);
				var hangLo = x1 - 30;
				if (y0 - 10 < bottom) hangLo = Math.max(hangLo, x0 + 10);
				if (x1 > hangLo && n >= -MAX_RISE_ROWS && n <= MAX_DROP_ROWS) launch.hangHits.push(new PredictHit(f, n, hangLo, x1));
			}
		}
	}

	/** One open-ground flight; floor tiles `minCol`..`maxCol` on `floorRow`. **/
	function flight(launch:PredictLaunch, startX:Float, floorY:Float, minCol:Int, maxCol:Int, floorRow:Int, longFloor:Bool):FlightPath {
		var floor = [for (c in minCol...maxCol + 1) new LevelBlock(c, floorRow, BlockType.Basic)];
		var area = new ClipArea(floor, minCol - 200, floorRow - 150, maxCol + 200, floorRow + 250);
		var level = area.buildLevel(settings.gravity);
		var attempt = launch.placed(startX, floorY);
		var player = ClipSimulator.preparePlayer(area, level, startX, floorY, attempt.speed, attempt.accel, attempt.jump, attempt.gravity,
			settings.hats, attempt.items);
		var xs = [player.x], ys = [player.y];
		var takeoff = ClipSimulator.tileOf(startX);
		var lastGroundedX = player.x;
		var leftGround = false;
		for (f in 0...FLIGHT_FRAMES) {
			player.step(attempt.inputAt(f, player.grounded));
			xs.push(player.x);
			ys.push(player.y);
			if (player.grounded) {
				if (leftGround && !longFloor) break;
				if (!leftGround) lastGroundedX = player.x;
			} else if (f > 0) {
				leftGround = true;
			}
			if (longFloor && leftGround && player.grounded) break;
		}
		takeoff = ClipSimulator.tileOf(lastGroundedX);
		return new FlightPath(xs, ys, takeoff);
	}

	// ---- Corners -----------------------------------------------------------------

	/** Start spots for `corner`: every hit of every flown launch facing its wall, at spots the player can stand on. **/
	function candidatesFor(corner:ClipCorner):Array<ClipAttempt> {
		// Ceilings meeting walls have no landing to predict: Stage 1's run-ups try them.
		if (corner.kind == CeilingWall) return [];
		var hanging = corner.kind == HangingWall;
		var t = ClipSimulator.TILE;
		// The row whose top the hit is measured to: the floor, or a hanging block's bottom edge.
		var floorRow = corner.y + 1;
		var face = corner.wallFace;
		var list:Array<ClipAttempt> = [];
		var seen:Map<String, Bool> = new Map();
		for (launch in flown) {
			if (launch.attempt.dir != corner.dir || launch.hits == null) continue;
			if (launch.needsTiming) continue;
			for (hit in (hanging ? launch.hangHits : launch.hits)) {
				var row = floorRow - hit.k;
				// Start x window (the feet): face - hi .. face - lo (mirrored facing left).
				var a = corner.dir == 1 ? face - hit.hi : face + hit.lo;
				var b = corner.dir == 1 ? face - hit.lo : face + hit.hi;
				for (col in ClipSimulator.tileOf(a)...ClipSimulator.tileOf(b) + 1) {
					if (!standable(col, row)) continue;
					var x0 = Math.max(a, col * t + 0.5), x1 = Math.min(b, col * t + t - 0.5);
					if (x1 < x0) continue;
					var mid = Math.round((x0 + x1) / 2 * 4) / 4;
					// A turned course puts block edges 1 px further along a flipped axis: try either side too.
					var xs = settings.courseRotation == 0 ? [mid] : [mid, mid - 1, mid + 1];
					for (x in xs) {
						var id = launch.id + ":" + x + ":" + row;
						if (seen.exists(id)) continue;
						seen.set(id, true);
						var attempt = launch.placed(x, row * t);
						attempt.courseRotation = settings.courseRotation;
						attempt.label = '${launch.label}, from ${Math.round(Math.abs(face - x)) - 10}px (predicted)';
						list.push(attempt);
					}
				}
			}
		}
		// Nearest starts first: the shorter the flight, the less there is in the way.
		list.sort((p, q) -> Reflect.compare(Math.abs(p.startX - face) + Math.abs(p.startY - corner.floorY),
			Math.abs(q.startX - face) + Math.abs(q.startY - corner.floorY)));
		if (list.length > MAX_CANDIDATES) list.resize(MAX_CANDIDATES);
		return list;
	}

	/** A solid floor tile with two air tiles above it. **/
	function standable(col:Int, floorRow:Int):Bool {
		return solid.exists(key(col, floorRow)) && !solid.exists(key(col, floorRow - 1)) && !solid.exists(key(col, floorRow - 2));
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

	static inline function key(x:Int, y:Int):Int return (x + 20000) * 40000 + (y + 20000);

	static function distanceSq(corner:ClipCorner, x:Float, y:Float):Float {
		var dx = corner.wallFace - x, dy = corner.floorY - y;
		return dx * dx + dy * dy;
	}
}

/** One launch: a ClipAttempt made at (0, 0) and placed at each candidate start. **/
class PredictLaunch {
	static var nextId:Int = 0;

	public final id:Int;
	public final attempt:ClipAttempt;
	public final item:Null<Int>;
	public final label:String;
	/** Sword or laser: this plain flight only times the slash or shot; its timed copies are the real launches. **/
	public final needsTiming:Bool;
	public var path:Null<Array<Float>> = null;
	public var pathY:Null<Array<Float>> = null;
	public var hits:Null<Array<PredictHit>> = null;
	/** Frames that would enter a hanging corner: `k` is then the block bottom's row offset from the start floor. **/
	public var hangHits:Array<PredictHit> = [];

	public function new(attempt:ClipAttempt, item:Null<Int>, label:String, needsTiming:Bool = false) {
		id = nextId++;
		this.attempt = attempt;
		this.item = item;
		this.label = label;
		this.needsTiming = needsTiming;
		if (item != null) attempt.items = new ClipItems(item);
	}

	/** The attempt started with the feet at (x, y). **/
	public function placed(x:Float, y:Float):ClipAttempt {
		var p = attempt;
		var a = new ClipAttempt(x, y, p.speed, p.accel, p.jump, p.gravity, p.dir, p.jumpFrame, p.hold, p.down, p.frames);
		a.script = p.script;
		a.hats = p.hats;
		a.items = p.items;
		a.label = p.label;
		a.itemAt = p.itemAt;
		a.jumpWithItem = p.jumpWithItem;
		a.moveStart = p.moveStart;
		a.turnFrame = p.turnFrame;
		a.superCharge = p.superCharge;
		a.superStart = p.superStart;
		return a;
	}

	/**
		For a sword or laser launch that has flown: a copy per landing frame
		with the slash (on the frame before it lands) or the shot (turn away two
		frames before, fire one before: the recoil kicks toward the wall).
	**/
	public function timedVariants():Array<PredictLaunch> {
		if (!needsTiming || hits == null) return [];
		var frames:Array<Int> = [];
		for (hit in hits) if (frames.indexOf(hit.frame) < 0) frames.push(hit.frame);
		var list:Array<PredictLaunch> = [];
		for (f in frames) {
			// `hit.frame` is a pose index (pose after frame index - 1): the landing step is f - 1.
			for (early in [1, 2]) {
				var use = f - 1 - early;
				if (use < 1) continue;
				var a = placed(0, 0);
				a.itemAt = use;
				var what:String;
				if (item == 1) {
					a.turnFrame = use - 1;
					what = 'turn away and fire on frame $use';
				} else {
					what = 'slash on frame $use';
				}
				list.push(new PredictLaunch(a, item, '$label, $what'));
			}
		}
		return list;
	}
}

/** A frame of a flight that lands deep and fast: corners `k` rows below the start floor, wall `lo`..`hi` px ahead. **/
class PredictHit {
	public final frame:Int;
	public final k:Int;
	public final lo:Float;
	public final hi:Float;

	public function new(frame:Int, k:Int, lo:Float, hi:Float) {
		this.frame = frame;
		this.k = k;
		this.lo = lo;
		this.hi = hi;
	}
}

private class FlightPath {
	public final xs:Array<Float>;
	public final ys:Array<Float>;
	public final takeoffCol:Int;

	public function new(xs:Array<Float>, ys:Array<Float>, takeoffCol:Int) {
		this.xs = xs;
		this.ys = ys;
		this.takeoffCol = takeoffCol;
	}
}

package pr2.gameplay.debug;

import pr2.gameplay.debug.ClipSimulator.ClipArea;
import pr2.gameplay.debug.ClipSimulator.ClipAttempt;
import pr2.gameplay.debug.ClipSimulator.ClipRun;
import pr2.level.Level.LevelBlock;

/** Inclusive stat range searched in `step` increments. A fixed stat has min == max. **/
class StatRange {
	public final min:Float;
	public final max:Float;
	public final step:Float;

	public function new(min:Float, max:Float, step:Float = 1) {
		this.min = Math.min(min, max);
		this.max = Math.max(min, max);
		this.step = step <= 0 ? 1 : step;
	}

	public static function fixed(value:Float):StatRange return new StatRange(value, value, 1);

	public function values():Array<Float> {
		var out:Array<Float> = [];
		var v = min;
		while (v <= max + 1e-9) {
			out.push(Math.round(v * 100) / 100);
			v += step;
		}
		return out;
	}
}

class ClipFinderSettings {
	public var startX:Float;
	public var startY:Float;
	public var gravity:Float;
	public var speed:StatRange;
	public var accel:StatRange;
	public var jump:StatRange;
	public var dirs:Array<Int> = [1, -1];
	/** Try normal jumps: pressed on each frame 0..maxJumpFrame, held for each of `holds`. **/
	public var normalJumps:Bool = true;
	public var maxJumpFrame:Int = 20;
	public var holds:Array<Int> = [4, 8, 999];
	/** Super jump charge lengths (frames of down) to try as well; empty = none. **/
	public var superCharges:Array<Int> = [];
	public var downModes:Array<Bool> = [false, true];
	/** Frames the direction starts being held (0 = from the start). **/
	public var moveStarts:Array<Int> = [0];
	/** Frames the direction flips mid-run (-1 = no turn). **/
	public var turnFrames:Array<Int> = [-1];
	public var frames:Int = 120;
	/** Hats the simulated player wears (copied from the real player in game). **/
	public var hats:Null<ClipSimulator.ClipHats> = null;
	/** Search stops collecting after this many clips (the search itself keeps counting). **/
	public var maxStoredClips:Int = 100;
	/**
		Random timing instead of the exhaustive grid: every attempt picks a random
		value from each list above (any frame of the run for jumps, super jump
		start, move start and turn) and the search runs until stopped, or for
		`randomAttempts` attempts when that is above 0.
	**/
	public var anyFrame:Bool = false;
	/**
		Aim at the target instead of searching blindly: attempts are scored by
		how close the body gets to the target tile, the closest ones are kept
		and nudged (a stat point, a frame of timing...) while some stay random.
		Needs a target; runs until stopped like `anyFrame`.
	**/
	public var aimAtTarget:Bool = false;
	/** Only count clips into this tile ("Target block"); null = any solid block. **/
	public var targetTileX:Null<Int> = null;
	public var targetTileY:Null<Int> = null;
	public var randomAttempts:Int = 0;
	public var seed:Int = 1;

	public function new(startX:Float, startY:Float, gravity:Float, speed:StatRange, accel:StatRange, jump:StatRange) {
		this.startX = startX;
		this.startY = startY;
		this.gravity = gravity;
		this.speed = speed;
		this.accel = accel;
		this.jump = jump;
	}
}

class FoundClip {
	public final attempt:ClipAttempt;
	public final run:ClipRun;

	public function new(attempt:ClipAttempt, run:ClipRun) {
		this.attempt = attempt;
		this.run = run;
	}
}

/**
	Debug-only incremental search: tries every stat/input combination from one
	start position, a few at a time, so the game keeps running while it works.
	Each attempt starts from a fresh simulated player (see ClipSimulator), and
	every clip found is re-run once with recording on for the ghost replay.
**/
class ClipFinder {
	/** Tiles kept around the start position: left/right, above, below. **/
	public static inline var AREA_RADIUS_X:Int = 14;
	public static inline var AREA_UP:Int = 12;
	public static inline var AREA_DOWN:Int = 8;

	public final settings:ClipFinderSettings;
	public final area:ClipArea;
	public final clips:Array<FoundClip> = [];
	public var tested(default, null):Int = 0;
	public var clipCount(default, null):Int = 0;
	public var blockedStart(default, null):Bool = false;
	/** Attempts the search will make; 0 when a random search runs until stopped. **/
	public final total:Int;
	final rng:ClipRng;

	final speeds:Array<Float>;
	final accels:Array<Float>;
	final jumps:Array<Float>;
	/** Every launch to try: normal jumps (frame, hold) then super jump charges. **/
	final launches:Array<Launch>;
	var next:Int = 0;

	public function new(blocks:Array<LevelBlock>, settings:ClipFinderSettings) {
		this.settings = settings;
		area = ClipArea.around(blocks, settings.startX, settings.startY, AREA_RADIUS_X, AREA_UP, AREA_DOWN);
		speeds = settings.speed.values();
		accels = settings.accel.values();
		jumps = settings.jump.values();
		launches = [];
		if (settings.normalJumps) {
			for (frame in 0...settings.maxJumpFrame + 1) for (hold in settings.holds) launches.push(new Launch(frame, hold, 0));
		}
		for (charge in settings.superCharges) launches.push(new Launch(0, 0, charge));
		rng = new ClipRng(settings.seed);
		total = settings.anyFrame || aiming() ? settings.randomAttempts : speeds.length * accels.length * jumps.length * settings.dirs.length
			* settings.moveStarts.length * settings.turnFrames.length * launches.length * settings.downModes.length;
	}

	public var done(get, never):Bool;
	function get_done():Bool {
		if (blockedStart || launches.length == 0) return true;
		return settings.anyFrame || aiming() ? total > 0 && next >= total : next >= total;
	}

	inline function aiming():Bool return settings.aimAtTarget && settings.targetTileX != null;

	// ---- Aim at target -------------------------------------------------------

	/** How many of the closest attempts are kept and refined. **/
	public static inline var ELITE_SIZE:Int = 8;
	/** Chance (out of 10) an aimed attempt is fresh random rather than a refined elite. **/
	static inline var EXPLORE_TENTHS:Int = 3;

	/** Closest attempts so far, best first. **/
	final elites:Array<ScoredAttempt> = [];
	/** Closest any attempt has come to the target, in pixels (0 = clipped into it). **/
	public var bestDistance(default, null):Float = Math.POSITIVE_INFINITY;
	/** The most promising attempt so far (lowest aiming score). **/
	public var bestAttempt(default, null):Null<ClipAttempt> = null;

	/** Attempts without a better score before the kept attempts are dropped and the search starts over. **/
	public static inline var STALL_LIMIT:Int = 300;
	var sinceImprovement:Int = 0;
	/** Best score since the last restart (bestScore keeps the overall best). **/
	var roundBest:Float = Math.POSITIVE_INFINITY;

	function aimedAttempt():ClipAttempt {
		if (sinceImprovement >= STALL_LIMIT && elites.length > 0) {
			// Stuck refining one approach: forget it and explore afresh.
			elites.resize(0);
			roundBest = Math.POSITIVE_INFINITY;
			sinceImprovement = 0;
		}
		if (elites.length < ELITE_SIZE / 2 || rng.int(10) < EXPLORE_TENTHS) return randomAttempt();
		// Lean toward the best: pick among the first few elites more often.
		var parent = elites[rng.int(rng.int(elites.length) + 1)].attempt;
		return refine(parent);
	}

	/** Keeps the most promising attempts (by ClipRun.aimScore) and the closest distance seen. **/
	function remember(attempt:ClipAttempt, score:Float, distance:Float):Void {
		bestDistance = Math.min(bestDistance, distance);
		if (score < bestScore) {
			bestScore = score;
			bestAttempt = attempt;
		}
		if (score < roundBest) {
			roundBest = score;
			sinceImprovement = 0;
		} else {
			sinceImprovement++;
		}
		if (score == Math.POSITIVE_INFINITY) return;
		if (elites.length >= ELITE_SIZE && score >= elites[elites.length - 1].score) return;
		var key = attempt.describe();
		for (e in elites) if (e.attempt.describe() == key) return;
		elites.push(new ScoredAttempt(attempt, score));
		elites.sort((a, b) -> Reflect.compare(a.score, b.score));
		if (elites.length > ELITE_SIZE) elites.pop();
	}

	/** Best aiming score so far (see ClipRun.aimScore); the near-miss ghost shows its attempt. **/
	public var bestScore(default, null):Float = Math.POSITIVE_INFINITY;

	/**
		A small change to one or two of the attempt's choices: a neighbouring stat
		value, a frame or two earlier or later for the jump / super jump / move /
		turn, a different hold or charge, or flipping fast-fall or direction.
	**/
	public function refine(parent:ClipAttempt):ClipAttempt {
		var speed = parent.speed, accel = parent.accel, jump = parent.jump;
		var dir = parent.dir, down = parent.down;
		var jumpFrame = parent.jumpFrame, hold = parent.hold;
		var superCharge = parent.superCharge, superStart = parent.superStart;
		var moveStart = parent.moveStart, turnFrame = parent.turnFrame;
		var last = settings.frames - 1;
		var turns = settings.turnFrames.filter(t -> t >= 0);
		for (_ in 0...1 + rng.int(2)) {
			switch (rng.int(9)) {
				case 0: speed = neighbour(speeds, speed);
				case 1: accel = neighbour(accels, accel);
				case 2: jump = neighbour(jumps, jump);
				case 3:
					if (superCharge > 0) superStart = clampInt(superStart + nudge(), 0, Std.int(Math.max(0, last - superCharge)));
					else jumpFrame = clampInt(jumpFrame + nudge(), 0, settings.maxJumpFrame);
				case 4:
					if (superCharge > 0) {
						var charges = settings.superCharges;
						var i = clampInt(charges.indexOf(superCharge) + nudge(), 0, charges.length - 1);
						superCharge = charges[i];
					} else {
						hold = hold >= 999 ? 1 + rng.int(settings.frames) : clampInt(hold + nudge(), 1, settings.frames);
					}
				case 5:
					if (settings.moveStarts.length > 1) moveStart = clampInt(moveStart + nudge(), 0, settings.moveStarts[settings.moveStarts.length - 1]);
				case 6:
					if (turns.length > 0) turnFrame = turnFrame < 0 ? rng.pick(turns) : clampInt(turnFrame + nudge(), turns[0], turns[turns.length - 1]);
				case 7:
					if (settings.downModes.length > 1) down = !down;
				default:
					if (settings.dirs.length > 1 && rng.int(3) == 0) dir = -dir;
			}
		}
		var child = new ClipAttempt(settings.startX, settings.startY, speed, accel, jump, settings.gravity, dir, jumpFrame, hold, down,
			settings.frames);
		child.superCharge = superCharge;
		child.superStart = superStart;
		child.moveStart = moveStart;
		child.turnFrame = turnFrame;
		child.hats = settings.hats;
		child.targetTileX = settings.targetTileX;
		child.targetTileY = settings.targetTileY;
		return child;
	}

	/** -2..2, never 0. **/
	function nudge():Int {
		var s = 1 + rng.int(2);
		return rng.int(2) == 0 ? -s : s;
	}

	function neighbour(values:Array<Float>, current:Float):Float {
		if (values.length <= 1) return current;
		var i = 0;
		for (j in 0...values.length) if (Math.abs(values[j] - current) < Math.abs(values[i] - current)) i = j;
		return values[clampInt(i + nudge(), 0, values.length - 1)];
	}

	static inline function clampInt(v:Int, min:Int, max:Int):Int {
		return v < min ? min : (v > max ? max : v);
	}

	/** Runs attempts until `maxRuns` have run or `deadline()` says time is up. Returns runs made. **/
	public function step(maxRuns:Int, ?deadline:Void->Bool):Int {
		var runs = 0;
		while (!done && runs < maxRuns && (deadline == null || runs == 0 || !deadline())) {
			var attempt = aiming() ? aimedAttempt() : (settings.anyFrame ? randomAttempt() : attemptAt(next));
			next++;
			runs++;
			var result = ClipSimulator.run(area, attempt);
			if (result.startBlocked) {
				// The start position never changes, so every attempt would be blocked.
				blockedStart = true;
				break;
			}
			tested++;
			if (aiming()) remember(attempt, result.aimScore, result.closestToTarget);
			if (result.clipped) {
				clipCount++;
				if (clips.length < settings.maxStoredClips) {
					clips.push(new FoundClip(attempt, ClipSimulator.run(area, attempt, true)));
				}
			}
		}
		return runs;
	}

	/**
		One random attempt for "Any frame" mode. Stats, direction and fast-fall
		come from the same lists as the grid; a normal jump is pressed on any
		frame 0..maxJumpFrame and held 1..frames frames (or to the end), a super
		jump charges for a listed length starting on any frame that still leaves
		room to launch, and the move start / turn come from their lists (half the
		attempts skip the turn when turns are enabled).
	**/
	public function randomAttempt():ClipAttempt {
		var frames = settings.frames;
		var launch = rng.pick(kindsInLaunches());
		var jumpFrame = 0, hold = 0;
		if (launch.superCharge == 0) {
			jumpFrame = rng.int(settings.maxJumpFrame + 1);
			hold = rng.int(4) == 0 ? 999 : 1 + rng.int(frames);
		}
		var attempt = new ClipAttempt(settings.startX, settings.startY, rng.pick(speeds), rng.pick(accels), rng.pick(jumps), settings.gravity,
			rng.pick(settings.dirs), jumpFrame, hold, rng.pick(settings.downModes), frames);
		if (launch.superCharge > 0) {
			attempt.superCharge = rng.pick(settings.superCharges);
			attempt.superStart = rng.int(Std.int(Math.max(1, frames - attempt.superCharge)));
		}
		attempt.moveStart = rng.pick(settings.moveStarts);
		var turns = settings.turnFrames.filter(t -> t >= 0);
		attempt.turnFrame = turns.length == 0 || rng.int(2) == 0 ? -1 : rng.pick(turns);
		attempt.hats = settings.hats;
		attempt.targetTileX = settings.targetTileX;
		attempt.targetTileY = settings.targetTileY;
		return attempt;
	}

	/** One representative per launch kind, so normal and super jumps are equally likely. **/
	function kindsInLaunches():Array<Launch> {
		var kinds:Array<Launch> = [];
		if (settings.normalJumps) kinds.push(new Launch(0, 8, 0));
		if (settings.superCharges.length > 0) kinds.push(new Launch(0, 0, settings.superCharges[0]));
		return kinds;
	}

	/** Decodes a flat combination index (mixed radix, stats outermost). **/
	public function attemptAt(index:Int):ClipAttempt {
		var i = index;
		var down = settings.downModes[i % settings.downModes.length];
		i = Std.int(i / settings.downModes.length);
		var launch = launches[i % launches.length];
		i = Std.int(i / launches.length);
		var turnFrame = settings.turnFrames[i % settings.turnFrames.length];
		i = Std.int(i / settings.turnFrames.length);
		var moveStart = settings.moveStarts[i % settings.moveStarts.length];
		i = Std.int(i / settings.moveStarts.length);
		var dir = settings.dirs[i % settings.dirs.length];
		i = Std.int(i / settings.dirs.length);
		var jump = jumps[i % jumps.length];
		i = Std.int(i / jumps.length);
		var accel = accels[i % accels.length];
		i = Std.int(i / accels.length);
		var speed = speeds[i % speeds.length];
		var attempt = new ClipAttempt(settings.startX, settings.startY, speed, accel, jump, settings.gravity, dir, launch.jumpFrame, launch.hold,
			down, settings.frames);
		attempt.superCharge = launch.superCharge;
		attempt.moveStart = moveStart;
		attempt.turnFrame = turnFrame;
		attempt.hats = settings.hats;
		attempt.targetTileX = settings.targetTileX;
		attempt.targetTileY = settings.targetTileY;
		return attempt;
	}
}

/** Small seeded PRNG (xorshift32) so a random search can be reproduced in tests. **/
private class ClipRng {
	var state:Int;

	public function new(seed:Int) {
		state = seed == 0 ? 1 : seed;
	}

	public function int(max:Int):Int {
		if (max <= 1) return 0;
		state ^= state << 13;
		state ^= state >>> 17;
		state ^= state << 5;
		return (state & 0x7fffffff) % max;
	}

	public function pick<T>(values:Array<T>):T {
		return values[int(values.length)];
	}
}

private class ScoredAttempt {
	public final attempt:ClipAttempt;
	public final score:Float;

	public function new(attempt:ClipAttempt, score:Float) {
		this.attempt = attempt;
		this.score = score;
	}
}

private class Launch {
	public final jumpFrame:Int;
	public final hold:Int;
	public final superCharge:Int;

	public function new(jumpFrame:Int, hold:Int, superCharge:Int) {
		this.jumpFrame = jumpFrame;
		this.hold = hold;
		this.superCharge = superCharge;
	}
}

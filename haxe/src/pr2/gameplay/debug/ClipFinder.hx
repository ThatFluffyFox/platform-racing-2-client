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
	public final total:Int;

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
		total = speeds.length * accels.length * jumps.length * settings.dirs.length * settings.moveStarts.length * settings.turnFrames.length
			* launches.length * settings.downModes.length;
	}

	public var done(get, never):Bool;
	inline function get_done():Bool return next >= total || blockedStart;

	/** Runs attempts until `maxRuns` have run or `deadline()` says time is up. Returns runs made. **/
	public function step(maxRuns:Int, ?deadline:Void->Bool):Int {
		var runs = 0;
		while (!done && runs < maxRuns && (deadline == null || runs == 0 || !deadline())) {
			var attempt = attemptAt(next);
			next++;
			runs++;
			var result = ClipSimulator.run(area, attempt);
			if (result.startBlocked) {
				// The start position never changes, so every attempt would be blocked.
				blockedStart = true;
				break;
			}
			tested++;
			if (result.clipped) {
				clipCount++;
				if (clips.length < settings.maxStoredClips) {
					clips.push(new FoundClip(attempt, ClipSimulator.run(area, attempt, true)));
				}
			}
		}
		return runs;
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
		return attempt;
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

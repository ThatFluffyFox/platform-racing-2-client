package pr2.gameplay.debug;

import pr2.gameplay.debug.ClipSimulator.ClipArea;
import pr2.gameplay.debug.ClipSimulator.ClipAttempt;
import pr2.gameplay.debug.ClipSimulator.ClipHats;
import pr2.gameplay.debug.ClipSimulator.ClipRun;
import pr2.gameplay.debug.ClipSimulator.GhostFrame;
import pr2.level.Level.LevelBlock;

/** An inside corner: the air tile in the crook, and which side the wall is on (1 = right). **/
class ClipCorner {
	public final x:Int;
	public final y:Int;
	public final dir:Int;

	public function new(x:Int, y:Int, dir:Int) {
		this.x = x;
		this.y = y;
		this.dir = dir;
	}

	/** Pixel x of the wall face the player runs into. **/
	public var wallFace(get, never):Float;
	inline function get_wallFace():Float return (dir == 1 ? x + 1 : x) * ClipSimulator.TILE;

	/** Pixel y of the floor's top (the player's feet when standing in the corner). **/
	public var floorY(get, never):Float;
	inline function get_floorY():Float return (y + 1) * ClipSimulator.TILE;

	/** The wall tile next to the corner, the one a clip goes into. **/
	public var wallTileX(get, never):Int;
	inline function get_wallTileX():Int return x + dir;
}

/** A corner the scan clipped through, with the attempt that did it and where it led. **/
class ClipPortal {
	public final corner:ClipCorner;
	public final attempt:ClipAttempt;
	/** Recorded run, from the start until the player came to rest (or a long tail ran out). **/
	public final run:ClipRun;
	/** Where the player came to rest after the clip, outside the blocks; null if it never did. **/
	public final exitX:Null<Float>;
	public final exitY:Null<Float>;

	/** A jump this big between two frames is the game sending the player back to a safe spot. **/
	public static inline var RESPAWN_JUMP:Float = 60;

	public function new(corner:ClipCorner, attempt:ClipAttempt, run:ClipRun) {
		this.corner = corner;
		this.attempt = attempt;
		this.run = run;
		var ghost = run.ghost;
		var last = ghost == null || ghost.length == 0 ? null : ghost[ghost.length - 1];
		if (last != null && last.grounded && !last.inSolid && !respawnedAfter(ghost, run.clipFrame)) {
			exitX = last.x;
			exitY = last.y;
		} else {
			exitX = null;
			exitY = null;
		}
	}

	/**
		First recorded pose after the clip where the player stands outside the
		blocks (before any respawn), or -1. Indexes are into the ghost frames.
	**/
	public static function landingIndex(ghost:Array<GhostFrame>, clipFrame:Int):Int {
		for (i in clipFrame + 2...ghost.length) {
			if (isRespawn(ghost, i)) return -1;
			if (ghost[i].grounded && !ghost[i].inSolid) return i;
		}
		return -1;
	}

	/** True when the player was sent back to a safe spot at some point after the clip. **/
	public static function respawnedAfter(ghost:Array<GhostFrame>, clipFrame:Int):Bool {
		for (i in clipFrame + 2...ghost.length) if (isRespawn(ghost, i)) return true;
		return false;
	}

	static function isRespawn(ghost:Array<GhostFrame>, i:Int):Bool {
		var a = ghost[i - 1], b = ghost[i];
		return Math.abs(b.x - a.x) > RESPAWN_JUMP || Math.abs(b.y - a.y) > RESPAWN_JUMP;
	}
}

class ClipScanSettings {
	public var speed:Float;
	public var accel:Float;
	public var jump:Float;
	public var gravity:Float;
	public var hats:Null<ClipHats> = null;
	/** Corners are scanned nearest-first from here (normally the player). **/
	public var originX:Float = 0;
	public var originY:Float = 0;
	/** Run-up distances tried at each corner: px from the player's leading edge to the wall. **/
	public var distances:Array<Int> = [for (d in 100...261) d];
	/** Super jump charges tried as well as the normal jumps (0 = none). **/
	public var superCharges:Array<Int> = [20, 35, 50];
	/** Normal jumps tried at each distance: frames jump is held (999 = a full jump, 8 = a short hop). **/
	public var jumpHolds:Array<Int> = [999, 8];
	public var frames:Int = 120;
	/** Frames a found clip is followed to see where the player ends up. **/
	public var followFrames:Int = 150;

	public function new(speed:Float, accel:Float, jump:Float, gravity:Float) {
		this.speed = speed;
		this.accel = accel;
		this.jump = jump;
		this.gravity = gravity;
	}
}

/**
	Debug-only level scan for the Clip Finder: finds every inside corner (a
	floor meeting a wall) and, with the player's own stats, gravity and hats,
	runs the real physics at each one to see whether it can be clipped. A
	corner is tried with run-ups from a range of distances, each with a full
	jump into fast-fall, a short hop into fast-fall, and a few super jumps; the
	first attempt that clips becomes a ClipPortal, followed until the player
	comes to rest so the scan knows where the clip leads.

	Like ClipFinder it works a few attempts at a time (`step`) so the race keeps
	running. Corners are scanned nearest-first.
**/
class ClipScanner {
	/** Tiles kept around a corner for its simulated area (it grows as needed). **/
	static inline var CROP_BACK:Int = 12;
	static inline var CROP_PAST:Int = 4;
	static inline var CROP_UP:Int = 10;
	static inline var CROP_DOWN:Int = 4;

	public final settings:ClipScanSettings;
	public final corners:Array<ClipCorner>;
	public final portals:Array<ClipPortal> = [];
	/** Corners fully scanned without a clip. **/
	public final solidCorners:Array<ClipCorner> = [];
	public var tested(default, null):Int = 0;
	public var cornerIndex(default, null):Int = 0;

	final blocks:Array<LevelBlock>;
	final launches:Array<ScanLaunch>;
	var area:Null<ClipArea> = null;
	var attemptIndex:Int = 0;

	public function new(blocks:Array<LevelBlock>, settings:ClipScanSettings) {
		this.blocks = blocks;
		this.settings = settings;
		launches = [for (hold in settings.jumpHolds) new ScanLaunch(hold, 0)];
		for (charge in settings.superCharges) if (charge > 0) launches.push(new ScanLaunch(0, charge));
		corners = findCorners(blocks, 1).concat(findCorners(blocks, -1));
		var ox = settings.originX, oy = settings.originY;
		corners.sort((a, b) -> Reflect.compare(distanceSq(a, ox, oy), distanceSq(b, ox, oy)));
	}

	public var done(get, never):Bool;
	inline function get_done():Bool return cornerIndex >= corners.length;

	/** Attempts per corner when no clip is found (the most a corner can cost). **/
	public var attemptsPerCorner(get, never):Int;
	inline function get_attemptsPerCorner():Int return settings.distances.length * launches.length;

	/** Runs attempts until `maxRuns` have run or `deadline()` says time is up. Returns runs made. **/
	public function step(maxRuns:Int, ?deadline:Void->Bool):Int {
		var runs = 0;
		while (!done && runs < maxRuns && (deadline == null || runs == 0 || !deadline())) {
			var corner = corners[cornerIndex];
			if (area == null) area = cornerArea(corner);
			if (attemptIndex >= attemptsPerCorner) {
				solidCorners.push(corner);
				nextCorner();
				continue;
			}
			var attempt = attemptAt(corner, attemptIndex);
			attemptIndex++;
			runs++;
			var result = ClipSimulator.run(area, attempt);
			if (result.startBlocked) continue;
			tested++;
			if (result.clipped) {
				portals.push(new ClipPortal(corner, attempt, followClip(area, attempt)));
				nextCorner();
			}
		}
		return runs;
	}

	/**
		Records a clipping attempt until the player comes to rest. The keys stay
		held through the clip (letting go inside a wall changes where you come
		out); once the player first lands outside the blocks they are released,
		so it stops there instead of running on, and a replay does the same.
	**/
	function followClip(area:ClipArea, attempt:ClipAttempt):ClipRun {
		var held = ClipSimulator.run(area, attempt, true, null, settings.followFrames);
		var ghost = held.ghost;
		if (ghost == null) return held;
		var landing = ClipPortal.landingIndex(ghost, held.clipFrame);
		if (landing < 0) return held;
		// ghost[i] is the pose after frame i - 1, so let go from frame `landing`.
		attempt.releaseFrame = landing;
		return ClipSimulator.run(area, attempt, true, null, settings.followFrames);
	}

	function nextCorner():Void {
		cornerIndex++;
		attemptIndex = 0;
		area = null;
	}

	/** Distance-major order, so the nearest run-ups are tried with every launch first. **/
	public function attemptAt(corner:ClipCorner, index:Int):ClipAttempt {
		var launch = launches[index % launches.length];
		var distance = settings.distances[Std.int(index / launches.length)];
		var startX = corner.wallFace - corner.dir * (10 + distance);
		var attempt = new ClipAttempt(startX, corner.floorY, settings.speed, settings.accel, settings.jump, settings.gravity, corner.dir, 0,
			launch.hold, true, settings.frames);
		attempt.superCharge = launch.superCharge;
		attempt.hats = settings.hats;
		return attempt;
	}

	function cornerArea(corner:ClipCorner):ClipArea {
		var minX = corner.dir == 1 ? corner.x - CROP_BACK : corner.x - CROP_PAST;
		var maxX = corner.dir == 1 ? corner.x + CROP_PAST : corner.x + CROP_BACK;
		return new ClipArea(blocks, minX, corner.y - CROP_UP, maxX, corner.y + CROP_DOWN);
	}

	static function distanceSq(corner:ClipCorner, x:Float, y:Float):Float {
		var dx = corner.wallFace - x, dy = corner.floorY - y;
		return dx * dx + dy * dy;
	}

	/**
		Inside corners facing `dir` (1 = wall on the right): an air tile with air
		above it (room to stand), a solid floor below, and a solid wall beside it.
		The physics decides whether a corner can actually be clipped.
	**/
	public static function findCorners(blocks:Array<LevelBlock>, dir:Int):Array<ClipCorner> {
		var solid:Map<String, Bool> = new Map();
		for (block in blocks) {
			if (!block.isMarker() && block.type.isSolid()) solid.set(block.x + "," + block.y, true);
		}
		inline function isSolid(x:Int, y:Int):Bool return solid.exists(x + "," + y);
		var corners:Array<ClipCorner> = [];
		var seen:Map<String, Bool> = new Map();
		for (block in blocks) {
			if (block.isMarker() || !block.type.isSolid()) continue;
			// Every solid block is a potential floor tile under a corner.
			var cx = block.x;
			var cy = block.y - 1;
			var key = cx + "," + cy;
			if (seen.exists(key)) continue;
			seen.set(key, true);
			if (!isSolid(cx, cy) && !isSolid(cx, cy - 1) && isSolid(cx + dir, cy)) corners.push(new ClipCorner(cx, cy, dir));
		}
		corners.sort((a, b) -> a.y != b.y ? a.y - b.y : a.x - b.x);
		return corners;
	}
}

private class ScanLaunch {
	public final hold:Int;
	public final superCharge:Int;

	public function new(hold:Int, superCharge:Int) {
		this.hold = hold;
		this.superCharge = superCharge;
	}
}

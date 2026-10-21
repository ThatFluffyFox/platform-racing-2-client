package pr2.gameplay.debug;

import pr2.gameplay.debug.ClipSimulator.ClipArea;
import pr2.gameplay.debug.ClipSimulator.ClipAttempt;
import pr2.gameplay.debug.ClipSimulator.ClipHats;
import pr2.gameplay.debug.ClipSimulator.ClipItems;
import pr2.gameplay.player.LocalPlayerInput;
import pr2.gameplay.debug.ClipSimulator.ClipRun;
import pr2.gameplay.debug.ClipSimulator.GhostFrame;
import pr2.level.BlockType;
import pr2.level.Level.LevelBlock;

/** An inside corner: the air tile in the crook, and which side the wall is on (1 = right). **/
class ClipCorner {
	public final x:Int;
	public final y:Int;
	public final dir:Int;
	/**
		For a mine spot (the level scan also tries mines): the mine's tile and
		how it is reached; null for an inside corner. (x, y) is then the tile
		the player stands in and `dir` faces the mine.
	**/
	public var mine:Null<MineSpot> = null;
	/** Which shape this is: a floor meeting a wall (the usual), a wall's bottom corner, or a ceiling meeting a wall. **/
	public final kind:CornerKind;
	/** For a hanging or ceiling corner: the row of the floor the player starts on (below the corner). **/
	public final startRow:Int;

	public function new(x:Int, y:Int, dir:Int, ?mine:MineSpot, ?kind:CornerKind, ?startRow:Int) {
		this.x = x;
		this.y = y;
		this.dir = dir;
		this.mine = mine;
		this.kind = kind == null ? FloorWall : kind;
		this.startRow = startRow == null ? y + 1 : startRow;
	}

	/** What kind of clip this is, for the panel. **/
	public function kindText():String {
		return switch (kind) {
			case FloorWall: "floor meets wall";
			case HangingWall: "bottom corner of a wall";
			case CeilingWall: "ceiling meets wall";
		}
	}

	/** The tile the overlay marks: the wall tile of a corner, or the mine. **/
	public var markX(get, never):Int;
	inline function get_markX():Int return mine != null ? mine.x : wallTileX;

	public var markY(get, never):Int;
	inline function get_markY():Int return mine != null ? mine.y : y;

	/** Pixel x of the wall face the player runs into. **/
	public var wallFace(get, never):Float;
	inline function get_wallFace():Float return (dir == 1 ? x + 1 : x) * ClipSimulator.TILE;

	/**
		Pixel y of the floor's top the player starts on: the corner's own floor,
		or for a hanging or ceiling corner the floor below it.
	**/
	public var floorY(get, never):Float;
	inline function get_floorY():Float return startRow * ClipSimulator.TILE;

	/** Pixel y of the bottom of the wall tile (a hanging corner's bottom edge). **/
	public var wallBottom(get, never):Float;
	inline function get_wallBottom():Float return (y + 1) * ClipSimulator.TILE;

	/** The wall tile next to the corner, the one a clip goes into. **/
	public var wallTileX(get, never):Int;
	inline function get_wallTileX():Int return x + dir;
}

/** The shapes the scan clips. **/
enum CornerKind {
	/** A floor meeting a wall: land deep in the floor moving into the wall. **/
	FloorWall;
	/**
		The bottom corner of a wall or block with air below it: fall past it
		moving into it with the feet 10-15 px below its bottom edge. The wall
		check (10 px above the feet) is already below the block, and nothing
		checks the head while falling, so the body goes in.
	**/
	HangingWall;
	/** A ceiling (overhang) meeting a wall: jump up into the corner moving into the wall. **/
	CeilingWall;
}

/** How a mine spot is used: a mine beside the player on the floor, set into the floor, or overhead. **/
enum MineUse {
	Beside;
	InFloor;
	Overhead;
}

class MineSpot {
	public final x:Int;
	public final y:Int;
	public final use:MineUse;

	public function new(x:Int, y:Int, use:MineUse) {
		this.x = x;
		this.y = y;
		this.use = use;
	}
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

	/** The tile (course tiles, like the corner's) the feet went into: the block the clip goes through, which the overlay marks. **/
	public final blockX:Int;
	public final blockY:Int;

	public function new(corner:ClipCorner, attempt:ClipAttempt, run:ClipRun) {
		this.corner = corner;
		this.attempt = attempt;
		this.run = run;
		blockX = run.clipped ? ClipSimulator.tileOf(run.x) : corner.markX;
		blockY = run.clipped ? ClipSimulator.tileOf(run.y - ClipSimulator.FEET_DEPTH) : corner.markY;
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

	/** True when the player came to rest past the wall or below the floor (through the blocks, not back out). **/
	public var passesThrough(get, never):Bool;
	function get_passesThrough():Bool {
		var ex = exitX, ey = exitY;
		if (ex == null || ey == null) return false;
		// The exit is in level space; the corner and start are in the attempt's course coordinates.
		var exit = ClipSimulator.toCourse(ex, ey, attempt.courseRotation);
		var x = exit.x, y = exit.y;
		if (corner.mine != null) {
			// A mine blast that went into blocks: it leads somewhere when it comes to rest away from where it started.
			var t = ClipSimulator.TILE;
			return Math.abs(x - attempt.startX) > t * 1.5 || Math.abs(y - attempt.startY) > t * 1.5;
		}
		if (corner.kind != FloorWall) return corner.dir * (x - corner.wallFace) > 0;
		return corner.dir * (x - corner.wallFace) > 0 || y > corner.floorY + 1;
	}

	/**
		True when the clip leads through the block: the player comes to rest
		past it (`passesThrough`), or gets out into the open past it without
		coming to rest (it falls out of the level and is sent back to a safe
		spot, or keeps swimming). A head clip that pops back out, or getting
		stuck inside, does not. The map scans list these.
	**/
	public var goesThrough(get, never):Bool;
	function get_goesThrough():Bool return passesThrough || clearsPast();

	function clearsPast():Bool {
		var ghost = run.ghost;
		if (corner.mine != null || exitX != null || ghost == null || run.clipFrame < 0) return false;
		var t = ClipSimulator.TILE;
		for (i in run.clipFrame + 2...ghost.length) {
			if (isRespawn(ghost, i)) break;
			var f = ghost[i];
			if (f.inSolid) continue;
			var p = ClipSimulator.toCourse(f.x, f.y, attempt.courseRotation);
			// Out in the open a tile past the wall face, or (floor corners) a tile under the floor.
			if (corner.dir * (p.x - corner.wallFace) > t) return true;
			if (corner.kind == FloorWall && p.y > corner.floorY + t) return true;
		}
		return false;
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

	/**
		True when a clip goes through the block: after getting into it the
		player comes to rest outside the blocks on the far side of the block it
		went into (and at least a tile from where it went in), without being
		sent back to a safe spot. A head clip that pops back out, or a clip that
		falls out of the level, does not. `clipFrame` is the run's clip frame.
	**/
	public static function wentThrough(ghost:Null<Array<GhostFrame>>, clipFrame:Int):Bool {
		if (ghost == null || clipFrame < 0 || clipFrame + 1 >= ghost.length) return false;
		// ghost[i] is the pose after frame i - 1: feet in the block at clipFrame + 1, before it at clipFrame.
		var before = ghost[clipFrame], inside = ghost[clipFrame + 1];
		var t = ClipSimulator.TILE;
		var feet = ClipSimulator.FEET_DEPTH;
		var bx = (ClipSimulator.tileOf(inside.x) + 0.5) * t, by = (ClipSimulator.tileOf(inside.y - feet) + 0.5) * t;
		for (i in clipFrame + 2...ghost.length) {
			if (isRespawn(ghost, i)) return false;
			var f = ghost[i];
			if (f.inSolid || !f.grounded) continue;
			// Came to rest: past the block the feet went into, going the way they went in?
			var inX = bx - before.x, inY = by - (before.y - feet);
			var outX = f.x - bx, outY = (f.y - feet) - by;
			var moved = Math.sqrt((f.x - before.x) * (f.x - before.x) + (f.y - before.y) * (f.y - before.y));
			return inX * outX + inY * outY > 0 && moved > t;
		}
		return false;
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
	/** Run-up distances tried at each corner: px from the player's leading edge to the wall (short ones fit narrow shafts). **/
	public var distances:Array<Int> = [for (d in 0...261) d];
	/** Super jump charges tried as well as the normal jumps (0 = none). **/
	public var superCharges:Array<Int> = [20, 35, 50];
	/** Normal jumps tried at each distance: frames jump is held (999 = a full jump, 8 = a short hop). **/
	public var jumpHolds:Array<Int> = [999, 8];
	public var frames:Int = 120;
	/** Frames a found clip is followed to see where the player ends up. **/
	public var followFrames:Int = 150;
	/** Only accept a clip that comes out through the blocks (the route planner's recipes); others keep the corner scanning. **/
	public var passThroughOnly:Bool = false;
	/** With `passThroughOnly`: a clip that gets out past the blocks without coming to rest counts too (`ClipPortal.goesThrough`; the map scans. A route needs somewhere to land). **/
	public var clearPastCounts:Bool = false;
	/**
		Also try laser recoil clips (the player holds a Laser Gun): stand
		against the wall, jump in place, and on the frame before landing in the
		corner turn away and fire; the recoil (15 px a frame toward the wall)
		plus the landing speed can put the player through. The landing frame
		depends on the stats, so every fire frame is tried.
	**/
	public var laser:Bool = false;
	/**
		The item the player holds (its code), which adds its own attempts:
		Laser Gun (1) the laser recoil clips above; Sword (8) the same grid but
		facing the wall, since its lunge adds 8 px a frame forward; Super Jump
		(5) run-ups that launch with the item (25 up, far above a jump) into
		fast-fall; Speed Burst (7) run-ups that burst first (double speed and
		acceleration) then jump or hop into fast-fall; Mine (2) placing a mine
		by the wall and getting blasted by it (up to 28 px a frame, into the
		wall or the floor); Jet Pack (6) run-ups that fly up first, then dive
		into the corner; Teleport (4) blinking 120 px toward the wall mid-jump.
		Lightning (3), Ice Wave (9) and Snake (10) don't move the player, so
		they have none.
	**/
	public var heldItem:Null<Int> = null;
	/**
		Other items to try at every corner as well (codes; e.g. every item the
		level's item blocks can give). Only the ones with clip attempts count
		(`ClipScanner.CLIP_ITEMS`).
	**/
	public var extraItems:Array<Int> = [];
	/** Mine item: px between the player's side and the wall when the mine is placed (they set which side of the player it lands). **/
	public var mineGaps:Array<Float> = [0, 6, 12, 18];
	/** Mine item: [frames jump is held, frame the mine is placed] (0 = placed standing). **/
	public var mineLaunches:Array<Array<Int>> = [[0, 1], [4, 2], [4, 4], [4, 6], [999, 4], [999, 8], [999, 12], [999, 16]];
	/** Jet Pack: frames it is held from the jump (then fast-fall into the corner), on run-ups every `jetStep` px. **/
	public var jetFrames:Array<Int> = [4, 8, 16, 30];
	public var jetStep:Int = 10;
	/** Teleport: px from the wall at the start, frames jump is held, and the frame it is used on. **/
	public var teleportGaps:Array<Float> = [0, 30, 90];
	public var teleportHolds:Array<Int> = [0, 8, 999];
	public var teleportFrames:Array<Int> = [for (f in 0...14) 1 + f * 3];
	/**
		Arrow blocks near a corner push the player: standing on an up arrow
		bounces it up (10 px a frame), side arrows push 3 px a frame on every
		frame stood on them (more than the speed relaxes, so riding a conveyor
		while holding its way builds up to 31 px a frame; it bleeds off to
		about 12 within 12 frames in the air), a down arrow wall drags a
		falling player down 5 px a frame more. Starting on arrows near the
		corner (see `arrowStarts`), the player waits this many frames (letting
		them act) before going for the corner.
	**/
	public var arrowWaits:Array<Int> = [for (w in 0...21) w * 2];
	/** Tiles before the wall searched for arrows (and started on). **/
	public var arrowReach:Int = 30;
	/** Px between the player's side and the wall at the start of a laser attempt. **/
	public var laserGaps:Array<Float> = [0, 1, 2];
	/** Frames jump is held for a laser attempt. **/
	public var laserHolds:Array<Int> = [3, 8, 30];
	/** Frames the player turns away on (and fires the frame after). **/
	public var laserFireFrames:Array<Int> = [for (f in 4...76) f];
	/**
		Hop-back clips: stand against the wall, jump (held `hopHolds` frames),
		hold away from the wall until `hopBackFrames`, then dive back at it
		holding toward it and down. In a narrow shaft, or off a bouncy floor
		like an up arrow, that is the only way to land in the corner fast
		with full speed into the wall.
	**/
	public var hopHolds:Array<Int> = [1, 2, 3, 4, 6, 8, 12, 999];
	public var hopBackFrames:Array<Int> = [for (f in 4...76) f];
	/**
		The course turn to scan in: corners and starts are in that turn's course
		coordinates (the player's own), and runs start the course turned.
	**/
	public var courseRotation:Int = 0;
	/**
		Also scan the bottom corners of walls hanging in the air, and ceilings
		meeting walls (not only floors meeting walls). Off by default: in those
		shapes only the head or body pokes into the block, never the feet, so
		they don't clip (a clip is the feet going in).
	**/
	public var wallClips:Bool = false;
	/**
		Stage 1.5: a corner no predicted start clips is then tried with Stage 1's
		own attempts (hop-backs and the rest), so it finds everything Stage 1
		does as well as the far clips.
	**/
	public var predictFallback:Bool = true;
	/**
		Stage 1.5's physics solver: the vertical programs played (frames jump
		is held, 999 = all; the frame fast-fall starts, -1 = never; super jump
		charge frames), and the frames held away before turning back at a wall.
		Run-ups and when moving starts are solved, not listed.
	**/
	public var solveJumpHolds:Array<Int> = [for (h in 1...13) h].concat([15, 20, 999]);
	public var solveFastFalls:Array<Int> = [-1, 1, 2].concat([for (d in 1...16) d * 4]);
	public var solveCharges:Array<Int> = [for (c in 10...51) c];
	public var solveTurnBacks:Array<Int> = [for (a in 1...61) a];
	/** Frames each of those programs is played for (the longest flight solved). **/
	public var solveFrames:Int = 140;
	/** Ceiling heights (tiles of air) bumped into, each played as its own program. **/
	public var predictCeilings:Array<Int> = [for (h in 2...13) h];
	/** Also scan mines: blasts from beside, from the floor and from below that drive the player into blocks. **/
	public var mines:Bool = true;
	/**
		Stats to scan with, each [speed, accel, jump] (null = just `speed`,
		`accel`, `jump`). Every corner is tried with each set, in order.
	**/
	public var statSets:Null<Array<Array<Float>>> = null;

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
class ClipScanner implements CornerScan {
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

	/** Scans the whole level, or only `onlyCorner` when given (the route planner's per-wall recipe). **/
	public function new(blocks:Array<LevelBlock>, settings:ClipScanSettings, ?onlyCorner:ClipCorner) {
		this.blocks = blocks;
		this.settings = settings;
		launches = [for (hold in settings.jumpHolds) new ScanLaunch(hold, 0)];
		for (charge in settings.superCharges) if (charge > 0) launches.push(new ScanLaunch(0, charge));
		// Corners as the player sees them on the turned course.
		var seen = ClipSimulator.layoutFor(blocks, settings.courseRotation);
		for (b in seen) {
			if (!b.isMarker() && b.type.isSolid()) solidTiles.set(tileKey(b.x, b.y), true);
			if (!b.isMarker() && isArrow(b.type)) arrowTiles.set(tileKey(b.x, b.y), true);
		}
		corners = onlyCorner != null ? [onlyCorner] : findCorners(seen, 1).concat(findCorners(seen, -1));
		if (onlyCorner == null && settings.wallClips) corners = corners.concat(findWallCorners(seen));
		if (onlyCorner == null && settings.mines) corners = corners.concat(findMineSpots(seen));
		statSets = settings.statSets != null && settings.statSets.length > 0 ? settings.statSets : [[settings.speed, settings.accel, settings.jump]];
		variants = [settings.heldItem];
		for (extra in settings.extraItems) {
			if (CLIP_ITEMS.indexOf(extra) >= 0 && variants.indexOf(extra) < 0) variants.push(extra);
		}
		var ox = settings.originX, oy = settings.originY;
		corners.sort((a, b) -> Reflect.compare(distanceSq(a, ox, oy), distanceSq(b, ox, oy)));
	}

	public var done(get, never):Bool;
	function get_done():Bool return cornerIndex >= corners.length;

	public function progressText(stopped:Bool):String {
		var total = corners.length;
		return '${stopped ? "Stopped at" : "Scanning"} ${Std.int(Math.min(cornerIndex + 1, total))}/$total corners/mines, ${portals.length} clip';
	}

	public function doneText():String return 'Scan done: ${portals.length} of ${corners.length} corners/mines clip';

	/** The stat sets every corner is tried with. **/
	final statSets:Array<Array<Float>>;

	/** Attempts per inside corner when no clip is found, over all stat sets. **/
	public var attemptsPerCorner(get, never):Int;
	inline function get_attemptsPerCorner():Int return cornerAttempts * statSets.length;

	/**
		Items each corner is tried with: the held item (with the plain run-ups
		and hops), then each extra item (only its own attempts).
	**/
	final variants:Array<Null<Int>>;
	/** The item the attempt being counted or built is for. **/
	var item:Null<Int> = null;
	/** True for the first variant, which also has the plain run-ups and hops. **/
	var baseVariant:Bool = true;

	/**
		Items with clip attempts of their own: every item that moves the
		player. Lightning, Ice Wave and Snake don't (the Snake digs on its own,
		outside the player's physics), so they have none.
	**/
	public static final CLIP_ITEMS:Array<Int> = [LASER_GUN, MINE_ITEM, TELEPORT, SUPER_JUMP, JET_PACK, SPEED_BURST, SWORD];

	/** Solid and arrow tiles as the player sees them (course tiles). **/
	final solidTiles:Map<String, Bool> = new Map();
	final arrowTiles:Map<String, Bool> = new Map();
	/** Arrow start spots per corner (course x of the feet), worked out once. **/
	final arrowStartCache:haxe.ds.ObjectMap<ClipCorner, Array<ArrowStart>> = new haxe.ds.ObjectMap();

	static inline function tileKey(x:Int, y:Int):String return x + "," + y;

	static function isArrow(type:BlockType):Bool {
		return switch (type) {
			case ArrowUp | ArrowDown | ArrowLeft | ArrowRight: true;
			default: false;
		}
	}

	function useVariant(v:Int):Void {
		item = variants[v];
		baseVariant = v == 0;
	}

	/** Attempts for one item variant (with one stat set). **/
	function variantAttempts(v:Int):Int {
		useVariant(v);
		return (baseVariant ? runUpAttempts + hopAttempts : 0) + laserAttempts + itemRunUpAttempts + itemMoveAttempts;
	}

	/** The Mine, Jet Pack and Teleport attempts of the variant's item (at a floor-meets-wall corner). **/
	var itemMoveAttempts(get, never):Int;
	function get_itemMoveAttempts():Int {
		var s = settings;
		if (item == MINE_ITEM) return s.mineGaps.length * 2 * s.mineLaunches.length * MINE_APPROACHES;
		if (item == JET_PACK) return jetDistances().length * s.jetFrames.length;
		if (item == TELEPORT) return s.teleportGaps.length * s.teleportHolds.length * s.teleportFrames.length;
		return 0;
	}

	/** What the player does once the mine is placed: stay, walk at the wall, step away and come back, or keep jumping. **/
	static inline var MINE_APPROACHES:Int = 4;

	function jetDistances():Array<Int> {
		var every = [for (d in settings.distances) if (d % settings.jetStep == 0) d];
		// A short list of run-ups (none on the step) is used as it is.
		return every.length > 0 ? every : settings.distances;
	}

	/** Jump styles per arrow start and wait: a full jump after the wait, jumping all along, no jump, a short hop after the wait. **/
	static inline var ARROW_LAUNCHES:Int = 4;

	function arrowAttempts(corner:ClipCorner):Int {
		return arrowStarts(corner).length * settings.arrowWaits.length * ARROW_LAUNCHES * 2;
	}

	/**
		Feet positions of the arrow starts at a floor-meets-wall corner: each
		arrow with room to stand on it within `arrowReach` tiles before the
		wall, from `ARROW_RISE` rows above the corner's floor (a conveyor or
		an up arrow on a ledge that carries the player down into the corner)
		to `ARROW_DROP` rows below it (an up arrow bouncing it up); and
		against the wall when the wall next to the player is an arrow. The
		`MAX_ARROW_STARTS` nearest are kept. None when no arrow is near.
	**/
	function arrowStarts(corner:ClipCorner):Array<ArrowStart> {
		var known = arrowStartCache.get(corner);
		if (known != null) return known;
		var t = ClipSimulator.TILE;
		var starts:Array<ArrowStart> = [];
		var floorRow = corner.y + 1;
		for (row in floorRow - ARROW_RISE...floorRow + ARROW_DROP + 1) {
			// Each run of arrows to stand on (a conveyor, or a single pad): its far end (the
			// longest ride toward the wall), its middle and its near end.
			var run:Array<Int> = [];
			function endRun():Void {
				if (run.length == 0) return;
				var picks = [run[run.length - 1], run[Std.int(run.length / 2)], run[0]];
				for (i in picks) {
					var col = corner.x - corner.dir * i;
					var start = new ArrowStart((col + 0.5) * t, row * t, i + Math.abs(row - floorRow));
					if (!Lambda.exists(starts, s -> s.x == start.x && s.y == start.y)) starts.push(start);
				}
				run = [];
			}
			for (i in 0...settings.arrowReach) {
				var col = corner.x - corner.dir * i;
				var standOn = arrowTiles.exists(tileKey(col, row)) && !solidTiles.exists(tileKey(col, row - 1))
					&& !solidTiles.exists(tileKey(col, row - 2));
				if (standOn) run.push(i) else endRun();
			}
			endRun();
		}
		starts.sort((a, b) -> Reflect.compare(a.distance, b.distance));
		if (starts.length > MAX_ARROW_STARTS) starts.resize(MAX_ARROW_STARTS);
		var wallArrow = false;
		for (row in corner.y - 2...corner.y + 1) if (arrowTiles.exists(tileKey(corner.wallTileX, row))) wallArrow = true;
		if (wallArrow) starts.push(new ArrowStart(corner.wallFace - corner.dir * 10, corner.floorY, 0));
		arrowStartCache.set(corner, starts);
		return starts;
	}

	static inline var ARROW_RISE:Int = 8;
	static inline var ARROW_DROP:Int = 3;
	static inline var MAX_ARROW_STARTS:Int = 6;

	/**
		Attempts at a hanging or ceiling corner: run-ups only (no standing
		against its wall), each with and without fast-fall (fast-fall drops
		past a hanging corner's 5 px window).
	**/
	function wallCornerAttempts(v:Int):Int {
		useVariant(v);
		return (baseVariant ? runUpAttempts * 2 : 0) + itemRunUpAttempts;
	}

	/** Attempts at one inside corner with one stat set, over every item variant. **/
	var cornerAttempts(get, never):Int;
	function get_cornerAttempts():Int {
		var total = 0;
		for (v in 0...variants.length) total += variantAttempts(v);
		return total;
	}

	var hopAttempts(get, never):Int;
	inline function get_hopAttempts():Int return settings.hopHolds.length * settings.hopBackFrames.length;

	/** Attempts at one target with one stat set. **/
	function attemptsPerSet(corner:ClipCorner):Int {
		var mine = corner.mine;
		if (mine != null) return mineMoves(mine.use).length;
		if (corner.kind != FloorWall) {
			var total = 0;
			for (v in 0...variants.length) total += wallCornerAttempts(v);
			return total;
		}
		return cornerAttempts + arrowAttempts(corner);
	}

	public function attemptsFor(corner:ClipCorner):Int return attemptsPerSet(corner) * statSets.length;

	var runUpAttempts(get, never):Int;
	inline function get_runUpAttempts():Int return settings.distances.length * launches.length;

	/** Recoil-style attempts: the laser (turn away and fire) or the sword (face the wall and slash). **/
	var recoilItem(get, never):Null<Int>;
	inline function get_recoilItem():Null<Int> {
		return (settings.laser && baseVariant) || item == LASER_GUN ? LASER_GUN : (item == SWORD ? SWORD : null);
	}

	var laserAttempts(get, never):Int;
	inline function get_laserAttempts():Int {
		return recoilItem != null ? settings.laserGaps.length * settings.laserHolds.length * settings.laserFireFrames.length : 0;
	}

	/** Item launches per run-up distance: the Super Jump item, or a Speed Burst before each jump hold. **/
	var itemLaunches(get, never):Int;
	inline function get_itemLaunches():Int {
		return item == SUPER_JUMP ? 1 : (item == SPEED_BURST ? settings.jumpHolds.length + burstSuperLaunches : 0);
	}

	/**
		Speed Burst super jumps per run-up distance: each charge, bursting
		early or late in the charge, and holding the direction all along or
		only from the release.
	**/
	var burstSuperLaunches(get, never):Int;
	inline function get_burstSuperLaunches():Int {
		var charges = 0;
		for (c in settings.superCharges) if (c > 0) charges++;
		return charges * 4;
	}

	var itemRunUpAttempts(get, never):Int;
	inline function get_itemRunUpAttempts():Int return settings.distances.length * itemLaunches;

	/** Runs attempts until `maxRuns` have run or `deadline()` says time is up. Returns runs made. **/
	public function step(maxRuns:Int, ?deadline:Void->Bool):Int {
		var runs = 0;
		while (!done && runs < maxRuns && (deadline == null || runs == 0 || !deadline())) {
			var corner = corners[cornerIndex];
			if (area == null) area = cornerArea(corner);
			if (attemptIndex >= attemptsFor(corner)) {
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
				var portal = new ClipPortal(corner, attempt, followClip(area, attempt));
				if (settings.passThroughOnly && !(settings.clearPastCounts ? portal.goesThrough : portal.passesThrough)) continue;
				portals.push(portal);
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
	function followClip(area:ClipArea, attempt:ClipAttempt):ClipRun return follow(area, attempt, settings.followFrames);

	/** `followClip` for any clipping attempt (also used by the Stage 1.5 predictor). **/
	public static function follow(area:ClipArea, attempt:ClipAttempt, followFrames:Int):ClipRun {
		var held = ClipSimulator.run(area, attempt, true, null, followFrames);
		var ghost = held.ghost;
		if (ghost == null) return held;
		var landing = ClipPortal.landingIndex(ghost, held.clipFrame);
		if (landing < 0) return held;
		// ghost[i] is the pose after frame i - 1, so let go from frame `landing`.
		attempt.releaseFrame = landing;
		return ClipSimulator.run(area, attempt, true, null, followFrames);
	}

	function nextCorner():Void {
		cornerIndex++;
		attemptIndex = 0;
		area = null;
	}

	/**
		Stat sets in order (all of one set's attempts first). Within a set:
		distance-major run-ups, so the nearest are tried with every launch
		first; then the laser attempts; a mine spot has its own moves.
	**/
	public function attemptAt(corner:ClipCorner, index:Int):ClipAttempt {
		var attempt = buildAttemptAt(corner, index);
		attempt.courseRotation = settings.courseRotation;
		return attempt;
	}

	function buildAttemptAt(corner:ClipCorner, index:Int):ClipAttempt {
		var perSet = attemptsPerSet(corner);
		var stats = statSets[Std.int(index / perSet)];
		index = index % perSet;
		var mine = corner.mine;
		if (mine != null) return mineAttemptAt(corner, mine, index, stats);
		var v = 0;
		if (corner.kind != FloorWall) {
			while (v < variants.length - 1 && index >= wallCornerAttempts(v)) {
				index -= wallCornerAttempts(v);
				v++;
			}
			useVariant(v);
			var runs = baseVariant ? runUpAttempts * 2 : 0;
			if (index >= runs) return itemRunUpAttemptAt(corner, index - runs, stats);
			return runUpAttemptAt(corner, index >> 1, stats, index % 2 == 0);
		}
		// The arrow starts come after every item variant's attempts.
		var itemAttempts = cornerAttempts;
		if (index >= itemAttempts) {
			useVariant(0);
			return arrowAttemptAt(corner, index - itemAttempts, stats);
		}
		while (v < variants.length - 1 && index >= variantAttempts(v)) {
			index -= variantAttempts(v);
			v++;
		}
		useVariant(v);
		// Within a variant: plain run-ups (first variant only), laser or sword, item run-ups, the
		// item's own moves (mine, jet pack, teleport), then hop-backs (first variant only).
		var runUps = baseVariant ? runUpAttempts : 0;
		if (index < runUps) return runUpAttemptAt(corner, index, stats);
		index -= runUps;
		if (index < laserAttempts) return laserAttemptAt(corner, index, stats);
		index -= laserAttempts;
		if (index < itemRunUpAttempts) return itemRunUpAttemptAt(corner, index, stats);
		index -= itemRunUpAttempts;
		if (index < itemMoveAttempts) return itemMoveAttemptAt(corner, index, stats);
		index -= itemMoveAttempts;
		return hopAttemptAt(corner, index, stats);
	}

	/** A plain run-up at `corner`: distance-major, every launch at each distance. **/
	function runUpAttemptAt(corner:ClipCorner, index:Int, stats:Array<Float>, fastFall:Bool = true):ClipAttempt {
		var launch = launches[index % launches.length];
		var distance = settings.distances[Std.int(index / launches.length)];
		var startX = corner.wallFace - corner.dir * (10 + distance);
		var attempt = new ClipAttempt(startX, corner.floorY, stats[0], stats[1], stats[2], settings.gravity, corner.dir, 0,
			launch.hold, fastFall, settings.frames);
		attempt.superCharge = launch.superCharge;
		attempt.hats = settings.hats;
		return attempt;
	}

	/**
		A laser recoil attempt: start `gap` px from the wall, jump in place
		(held `hold` frames), turn away from the wall on `fireAt` and fire on the
		next frame, then let go.
	**/
	function laserAttemptAt(corner:ClipCorner, index:Int, stats:Array<Float>):ClipAttempt {
		var s = settings;
		var fires = s.laserFireFrames.length, holds = s.laserHolds.length;
		var fireAt = s.laserFireFrames[index % fires];
		var hold = s.laserHolds[Std.int(index / fires) % holds];
		var gap = s.laserGaps[Std.int(index / (fires * holds))];
		var startX = corner.wallFace - corner.dir * (10 + gap);
		var length = fireAt + 2 + 60;
		var sword = recoilItem == SWORD;
		// The laser kicks back, so turn away from the wall; the sword lunges forward, so face it.
		var turnDir = sword ? corner.dir : -corner.dir;
		var script = [for (f in 0...length) {
			var jumping = f < hold;
			var turn = f == fireAt;
			new LocalPlayerInput(turn && turnDir == -1, turn && turnDir == 1, jumping, false, f == fireAt + 1);
		}];
		var attempt = new ClipAttempt(startX, corner.floorY, stats[0], stats[1], stats[2], s.gravity, corner.dir, 0, 0, false, length);
		attempt.script = script;
		attempt.items = new ClipItems(sword ? SWORD : LASER_GUN);
		attempt.hats = s.hats;
		attempt.label = (sword ? 'sword lunge (jump held $hold, slash on frame ${fireAt + 1}' : 'laser recoil (jump held $hold, fire on frame ${fireAt + 1}')
			+ ', ${gap}px from the wall)';
		return attempt;
	}

	/** A hop-back attempt: against the wall, jump, hold away until `back`, then toward the wall and down. **/
	function hopAttemptAt(corner:ClipCorner, index:Int, stats:Array<Float>):ClipAttempt {
		var s = settings;
		var backs = s.hopBackFrames.length;
		var back = s.hopBackFrames[index % backs];
		var hold = s.hopHolds[Std.int(index / backs)];
		var startX = corner.wallFace - corner.dir * 10;
		var length = back + s.frames;
		var away = -corner.dir;
		var script = [for (f in 0...length) {
			var dir = f < back ? away : corner.dir;
			new LocalPlayerInput(dir == -1, dir == 1, f < hold, f >= back);
		}];
		var attempt = new ClipAttempt(startX, corner.floorY, stats[0], stats[1], stats[2], s.gravity, corner.dir, 0, 0, false, length);
		attempt.script = script;
		attempt.hats = s.hats;
		attempt.label = 'hop back (jump held ${hold >= 999 ? "all" : Std.string(hold)}, away until frame $back, then dive at the wall)';
		return attempt;
	}

	/** A run-up launched with the Super Jump item, or a Speed Burst run-up then a jump; both into fast-fall. **/
	function itemRunUpAttemptAt(corner:ClipCorner, index:Int, stats:Array<Float>):ClipAttempt {
		var s = settings;
		var launches = itemLaunches;
		var launch = index % launches;
		var distance = s.distances[Std.int(index / launches)];
		var startX = corner.wallFace - corner.dir * (10 + distance);
		var attempt:ClipAttempt;
		if (item == SUPER_JUMP) {
			attempt = new ClipAttempt(startX, corner.floorY, stats[0], stats[1], stats[2], s.gravity, corner.dir, 0, 0, true, s.frames);
			attempt.jumpWithItem = true;
			attempt.label = 'super jump item from ${distance}px, then fast-fall';
		} else if (launch >= s.jumpHolds.length) {
			attempt = burstSuperJump(startX, corner, launch - s.jumpHolds.length, stats);
			attempt.label = 'speed burst while charging a super jump (charge ${attempt.superCharge}, burst on frame ${attempt.itemAt}), '
				+ (attempt.moveStart > 0 ? 'stand ${distance}px from the wall, release holding toward it' : 'run from ${distance}px') + ', fast-fall';
		} else {
			var hold = s.jumpHolds[launch];
			attempt = new ClipAttempt(startX, corner.floorY, stats[0], stats[1], stats[2], s.gravity, corner.dir, 1, hold, true, s.frames);
			attempt.itemAt = 0;
			attempt.label = 'speed burst, run from ${distance}px, jump held ${hold >= 999 ? "all" : Std.string(hold)}, fast-fall';
		}
		attempt.items = new ClipItems(item);
		attempt.hats = s.hats;
		return attempt;
	}

	/**
		Hold down to charge a super jump, use the Speed Burst while charging
		(double speed and acceleration), then let go of down holding toward
		the wall: the launch carries twice the normal top speed.
	**/
	function burstSuperJump(startX:Float, corner:ClipCorner, index:Int, stats:Array<Float>):ClipAttempt {
		var charges = [for (c in settings.superCharges) if (c > 0) c];
		var charge = charges[Std.int(index / 4)];
		var late = index % 2 == 1;
		var holdFromRelease = index % 4 >= 2;
		var attempt = new ClipAttempt(startX, corner.floorY, stats[0], stats[1], stats[2], settings.gravity, corner.dir, 0, 0, true,
			settings.frames + charge);
		attempt.superCharge = charge;
		// An item press needs a released frame first, so the earliest is frame 1.
		attempt.itemAt = late ? Std.int(Math.max(1, charge - 2)) : 1;
		if (holdFromRelease) attempt.moveStart = charge;
		return attempt;
	}

	/** The Mine, Jet Pack or Teleport attempt `index` of the variant's item. **/
	function itemMoveAttemptAt(corner:ClipCorner, index:Int, stats:Array<Float>):ClipAttempt {
		var attempt = item == MINE_ITEM ? mineItemAttemptAt(corner, index, stats)
			: (item == JET_PACK ? jetAttemptAt(corner, index, stats) : teleportAttemptAt(corner, index, stats));
		attempt.items = new ClipItems(item);
		attempt.hats = settings.hats;
		return attempt;
	}

	/**
		Mine item: from `gap` px off the wall, jump (or not), and on the
		placing frame face toward or away from the wall and place the mine. It
		lands in the tile at the player's hand (always a little to the right,
		as in Flash) and appears 33 frames later; touching it then blasts the
		player away from its centre (50, capped at 28 px a frame). Then stay,
		walk at the wall, step away and come back, or keep jumping (up into a
		mine placed overhead blasts the player down into the floor).
	**/
	function mineItemAttemptAt(corner:ClipCorner, index:Int, stats:Array<Float>):ClipAttempt {
		var s = settings;
		var launches = s.mineLaunches.length;
		var approach = index % MINE_APPROACHES;
		var launch = s.mineLaunches[Std.int(index / MINE_APPROACHES) % launches];
		var facing = Std.int(index / (MINE_APPROACHES * launches)) % 2;
		var gap = s.mineGaps[Std.int(index / (MINE_APPROACHES * launches * 2))];
		var hold = launch[0], place = launch[1];
		var dir = corner.dir;
		var face = facing == 0 ? dir : -dir;
		var appear = place + MINE_APPEAR_FRAMES;
		var length = appear + 70;
		var script = [for (f in 0...length) {
			var jump = f < Std.int(Math.min(hold, 20)) || (approach == 3 && f >= appear - 10);
			var move = 0;
			if (f == place) move = face;
			else if (f > place) move = switch (approach) {
				case 1: dir;
				case 2: f <= place + 10 ? -dir : dir;
				default: 0;
			}
			new LocalPlayerInput(move == -1, move == 1, jump, false, f == place);
		}];
		var attempt = new ClipAttempt(corner.wallFace - dir * (10 + gap), corner.floorY, stats[0], stats[1], stats[2], s.gravity, dir, 0, 0, false, length);
		attempt.script = script;
		var then = switch (approach) {
			case 1: "walk at the wall";
			case 2: "step away and come back";
			case 3: "keep jumping";
			default: "stay";
		}
		var jumpText = hold == 0 ? "standing" : 'jump held ${hold >= 999 ? "all" : Std.string(hold)}';
		attempt.label = 'mine item ($jumpText, ${gap}px from the wall, place it facing ${face == dir ? "the wall" : "away"} on frame $place, then $then)';
		return attempt;
	}

	/** Jet Pack: run from each `jetStep` px, jump, fly for `jetFrames`, then fast-fall into the corner. **/
	function jetAttemptAt(corner:ClipCorner, index:Int, stats:Array<Float>):ClipAttempt {
		var s = settings;
		var fly = s.jetFrames[index % s.jetFrames.length];
		var distance = jetDistances()[Std.int(index / s.jetFrames.length)];
		var attempt = new ClipAttempt(corner.wallFace - corner.dir * (10 + distance), corner.floorY, stats[0], stats[1], stats[2], s.gravity, corner.dir,
			0, 999, true, s.frames + fly);
		attempt.itemFrom = 1;
		attempt.itemUntil = fly;
		attempt.downFrom = fly + 1;
		attempt.label = 'jet pack: run from ${distance}px, jump, fly $fly frames, then fast-fall';
		return attempt;
	}

	/** Teleport: from `gap` px off the wall, run at it (jumping or not) and teleport 120 px toward it on a set frame, then fast-fall. **/
	function teleportAttemptAt(corner:ClipCorner, index:Int, stats:Array<Float>):ClipAttempt {
		var s = settings;
		var frames = s.teleportFrames.length, holds = s.teleportHolds.length;
		var at = s.teleportFrames[index % frames];
		var hold = s.teleportHolds[Std.int(index / frames) % holds];
		var gap = s.teleportGaps[Std.int(index / (frames * holds))];
		var attempt = new ClipAttempt(corner.wallFace - corner.dir * (10 + gap), corner.floorY, stats[0], stats[1], stats[2], s.gravity, corner.dir, 0,
			hold, true, s.frames);
		attempt.itemAt = at;
		var jumpText = hold == 0 ? "no jump" : 'jump held ${hold >= 999 ? "all" : Std.string(hold)}';
		attempt.label = 'teleport toward the wall on frame $at (${gap}px from it, $jumpText), fast-fall';
		return attempt;
	}

	/**
		An arrow start: stand on an arrow near the corner (or against an arrow
		wall), wait while it acts (holding toward the wall or not), then go for
		the corner: a full jump from the end of the wait, a full jump held all
		along (bouncing higher on an up arrow), or no jump; fast-fall once the
		wait is over.
	**/
	function arrowAttemptAt(corner:ClipCorner, index:Int, stats:Array<Float>):ClipAttempt {
		var s = settings;
		var waits = s.arrowWaits.length;
		var launch = index % ARROW_LAUNCHES;
		var holdWhileWaiting = Std.int(index / ARROW_LAUNCHES) % 2 == 1;
		var wait = s.arrowWaits[Std.int(index / (ARROW_LAUNCHES * 2)) % waits];
		var start = arrowStarts(corner)[Std.int(index / (ARROW_LAUNCHES * 2 * waits))];
		var jumpFrame = launch == 1 ? 0 : wait;
		var hold = switch (launch) {
			case 2: 0;
			case 3: 4;
			default: 999;
		}
		var attempt = new ClipAttempt(start.x, start.y, stats[0], stats[1], stats[2], s.gravity, corner.dir, jumpFrame, hold, true, s.frames + wait);
		attempt.downFrom = wait;
		attempt.moveStart = holdWhileWaiting ? 0 : wait;
		attempt.hats = s.hats;
		var then = switch (launch) {
			case 0: "jump";
			case 1: "keep jumping from the start";
			case 3: "hop";
			default: "no jump";
		}
		attempt.label = 'arrows: start at ${Math.round(start.x)},${Math.round(start.y)}, wait $wait frames '
			+ '${holdWhileWaiting ? "holding toward the wall" : "still"}, then $then, fast-fall';
		return attempt;
	}

	static inline var SWORD:Int = 8;
	static inline var SUPER_JUMP:Int = 5;
	static inline var SPEED_BURST:Int = 7;
	static inline var MINE_ITEM:Int = 2;
	static inline var TELEPORT:Int = 4;
	static inline var JET_PACK:Int = 6;
	/** Frames a placed mine takes to appear (LocalPlayerController.MINE_APPEAR_FRAMES). **/
	static inline var MINE_APPEAR_FRAMES:Int = 33;

	static inline var LASER_GUN:Int = 1;

	/** The moves tried at a mine spot, facing it (right): what it is, gap from the mine (or offset under it) and inputs. **/
	static function mineMoves(use:MineUse):Array<MineMove> {
		var moves:Array<MineMove> = [];
		switch (use) {
			case Beside:
				for (gap in [2.0, 40.0]) {
					moves.push(new MineMove('walk at it from ${gap}px', gap, holdKeys(1, 30, 0)));
					moves.push(new MineMove('hop at it from ${gap}px', gap, holdKeys(1, 30, 3)));
					moves.push(new MineMove('jump at it from ${gap}px', gap, holdKeys(1, 30, 30)));
				}
			case InFloor:
				for (gap in [4.0, 60.0]) {
					moves.push(new MineMove('step onto it from ${gap}px', gap, holdKeys(1, 20 + Std.int(gap), 0)));
					moves.push(new MineMove('run across it from ${gap}px', gap, holdKeys(1, 90, 0)));
				}
			case Overhead:
				moves.push(new MineMove("jump up into it", 0, holdKeys(0, 0, 30)));
				moves.push(new MineMove("jump up into it (off-centre)", 12, holdKeys(0, 0, 30)));
		}
		return moves;
	}

	/** Hold `dir` (0 = none) for `frames` frames and jump for the first `jumpHold`. **/
	static function holdKeys(dir:Int, frames:Int, jumpHold:Int):Array<LocalPlayerInput> {
		var length = Std.int(Math.max(frames, jumpHold));
		return [for (f in 0...length) new LocalPlayerInput(dir == -1 && f < frames, dir == 1 && f < frames, f < jumpHold, false)];
	}

	/** A mine attempt: stand at the move's gap from the mine and play it (inputs face the mine). **/
	function mineAttemptAt(corner:ClipCorner, mine:MineSpot, index:Int, stats:Array<Float>):ClipAttempt {
		var t = ClipSimulator.TILE;
		var move = mineMoves(mine.use)[index];
		var dir = corner.dir;
		var startX = switch (mine.use) {
			case Overhead: (mine.x + 0.5) * t - move.gap;
			default: (dir == 1 ? mine.x * t : (mine.x + 1) * t) - dir * (10 + move.gap);
		}
		var inputs = [for (i in move.inputs) new LocalPlayerInput(dir == -1 ? i.right : i.left, dir == -1 ? i.left : i.right, i.jump, i.down)];
		var length = inputs.length + settings.frames;
		var attempt = new ClipAttempt(startX, (corner.y + 1) * t, stats[0], stats[1], stats[2], settings.gravity, dir, 0, 0, false, length);
		attempt.script = inputs;
		attempt.hats = settings.hats;
		attempt.label = 'mine at ${mine.x},${mine.y}: ${move.label}';
		return attempt;
	}

	/**
		Every item the level's item blocks can give (codes, in code order): a
		block's own options ("5-7"), or `allowed` (the level's item list; null =
		every item) for a block without options. "none" gives nothing.
	**/
	public static function levelItems(blocks:Array<LevelBlock>, ?allowed:Array<Int>):Array<Int> {
		var all = allowed != null ? allowed : pr2.gameplay.Items.getAllCodes();
		var found:Array<Int> = [];
		for (b in blocks) {
			if (b.type != BlockType.Item && b.type != BlockType.InfiniteItem) continue;
			var options = b.options == null ? "" : b.options;
			var codes = options == "" ? all : (options == "none" ? [] : [for (id in options.split("-")) if (Std.parseInt(id) != null) Std.parseInt(id)]);
			for (code in codes) if (found.indexOf(code) < 0) found.push(code);
		}
		found.sort((a, b) -> a - b);
		return found;
	}

	/**
		Mines a player can use: one on the floor with standing room beside it,
		one set into the floor with room to stand on its neighbour, and one
		overhead with room to stand under it (and jump up into it).
	**/
	public static function findMineSpots(blocks:Array<LevelBlock>):Array<ClipCorner> {
		var solid:Map<String, Bool> = new Map();
		for (block in blocks) {
			if (!block.isMarker() && block.type.isSolid()) solid.set(block.x + "," + block.y, true);
		}
		inline function isSolid(x:Int, y:Int):Bool return solid.exists(x + "," + y);
		var spots:Array<ClipCorner> = [];
		for (b in blocks) {
			if (b.isMarker() || b.type != BlockType.Mine) continue;
			var mx = b.x, my = b.y;
			for (dir in [1, -1]) {
				var sx = mx - dir;
				// Beside: stand next to it on the same floor.
				if (!isSolid(sx, my) && !isSolid(sx, my - 1) && isSolid(sx, my + 1)) spots.push(new ClipCorner(sx, my, dir, new MineSpot(mx, my, Beside)));
				// In the floor: stand on the tile next to it, with the mine's own top open.
				if (!isSolid(mx, my - 1) && !isSolid(mx, my - 2) && isSolid(sx, my) && !isSolid(sx, my - 1) && !isSolid(sx, my - 2))
					spots.push(new ClipCorner(sx, my - 1, dir, new MineSpot(mx, my, InFloor)));
			}
			// Overhead: open below it, then a floor to stand on within a few tiles.
			if (!isSolid(mx, my + 1)) {
				for (sy in my + 2...my + 5) {
					if (isSolid(mx, sy)) break;
					if (isSolid(mx, sy + 1) && !isSolid(mx, sy - 1)) {
						spots.push(new ClipCorner(mx, sy, 1, new MineSpot(mx, my, Overhead)));
						break;
					}
				}
			}
		}
		return spots;
	}

	function cornerArea(corner:ClipCorner):ClipArea {
		var minX = corner.dir == 1 ? corner.x - CROP_BACK : corner.x - CROP_PAST;
		var maxX = corner.dir == 1 ? corner.x + CROP_PAST : corner.x + CROP_BACK;
		return ClipArea.forCourse(blocks, minX, corner.y - CROP_UP, maxX, corner.y + CROP_DOWN, settings.courseRotation);
	}

	static function distanceSq(corner:ClipCorner, x:Float, y:Float):Float {
		var dx = corner.wallFace - x, dy = corner.floorY - y;
		return dx * dx + dy * dy;
	}

	/**
		Inside corners facing `dir` (1 = wall on the right): an air tile with air
		above it (room to stand), a solid floor below, and a solid wall beside it.
		The physics decides whether a corner can actually be clipped. A mine is
		never the floor or wall of a corner: touching it blows it up and knocks
		the player away instead of letting them clip in (it still counts as
		solid for the room-to-stand checks).
	**/
	/** Rows below a hanging or ceiling corner searched for a floor to start on. **/
	static inline var START_DROP:Int = 12;

	/**
		Hanging and ceiling corners facing both ways. A hanging corner: a solid
		tile (not a mine) with air below it and air in front (both rows), and a
		floor below the air in front to start from. A ceiling corner: an air
		tile with a solid ceiling above and a solid wall beside it, at least two
		tiles above a floor (room to stand under it).
	**/
	public static function findWallCorners(blocks:Array<LevelBlock>):Array<ClipCorner> {
		var solid:Map<String, Bool> = new Map();
		var mine:Map<String, Bool> = new Map();
		for (block in blocks) {
			if (block.isMarker() || !block.type.isSolid()) continue;
			solid.set(block.x + "," + block.y, true);
			if (block.type == BlockType.Mine) mine.set(block.x + "," + block.y, true);
		}
		inline function isSolid(x:Int, y:Int):Bool return solid.exists(x + "," + y);
		inline function isClippable(x:Int, y:Int):Bool return isSolid(x, y) && !mine.exists(x + "," + y);
		// The first floor below (x, y) with two rows of room above it, or -1.
		function floorBelow(x:Int, y:Int):Int {
			for (row in y + 1...y + START_DROP + 1) {
				if (isSolid(x, row)) return !isSolid(x, row - 1) && !isSolid(x, row - 2) && row - 2 >= y ? row : -1;
			}
			return -1;
		}
		var corners:Array<ClipCorner> = [];
		var seen:Map<String, Bool> = new Map();
		for (block in blocks) {
			if (block.isMarker() || !block.type.isSolid() || block.type == BlockType.Mine) continue;
			var wx = block.x, wy = block.y;
			for (dir in [1, -1]) {
				var fx = wx - dir;
				// Hanging: air below the block and in front of it (both rows).
				if (!isSolid(wx, wy + 1) && !isSolid(fx, wy) && !isSolid(fx, wy + 1)) {
					var row = floorBelow(fx, wy);
					var key = 'h$fx,$wy,$dir';
					if (row > 0 && !seen.exists(key)) {
						seen.set(key, true);
						corners.push(new ClipCorner(fx, wy, dir, null, HangingWall, row));
					}
				}
				// Ceiling: air in front with a solid tile above it, the block being the wall.
				if (!isSolid(fx, wy) && isSolid(fx, wy - 1) && isClippable(wx, wy)) {
					var row = floorBelow(fx, wy);
					var key = 'c$fx,$wy,$dir';
					if (row > 0 && row - wy >= 2 && !seen.exists(key)) {
						seen.set(key, true);
						corners.push(new ClipCorner(fx, wy, dir, null, CeilingWall, row));
					}
				}
			}
		}
		corners.sort((a, b) -> a.y != b.y ? a.y - b.y : a.x - b.x);
		return corners;
	}

	public static function findCorners(blocks:Array<LevelBlock>, dir:Int):Array<ClipCorner> {
		var solid:Map<String, Bool> = new Map();
		var mine:Map<String, Bool> = new Map();
		for (block in blocks) {
			if (block.isMarker() || !block.type.isSolid()) continue;
			solid.set(block.x + "," + block.y, true);
			if (block.type == BlockType.Mine) mine.set(block.x + "," + block.y, true);
		}
		inline function isSolid(x:Int, y:Int):Bool return solid.exists(x + "," + y);
		inline function isClippable(x:Int, y:Int):Bool return isSolid(x, y) && !mine.exists(x + "," + y);
		var corners:Array<ClipCorner> = [];
		var seen:Map<String, Bool> = new Map();
		for (block in blocks) {
			if (block.isMarker() || !block.type.isSolid() || block.type == BlockType.Mine) continue;
			// Every solid block is a potential floor tile under a corner.
			var cx = block.x;
			var cy = block.y - 1;
			var key = cx + "," + cy;
			if (seen.exists(key)) continue;
			seen.set(key, true);
			if (!isSolid(cx, cy) && !isSolid(cx, cy - 1) && isClippable(cx + dir, cy)) corners.push(new ClipCorner(cx, cy, dir));
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

/** Where an arrow attempt starts (the feet, in course pixels), and how far that is from its corner (tiles, for ordering). **/
private class ArrowStart {
	public final x:Float;
	public final y:Float;
	public final distance:Float;

	public function new(x:Float, y:Float, distance:Float) {
		this.x = x;
		this.y = y;
		this.distance = distance;
	}
}

private class MineMove {
	public final label:String;
	public final gap:Float;
	public final inputs:Array<LocalPlayerInput>;

	public function new(label:String, gap:Float, inputs:Array<LocalPlayerInput>) {
		this.label = label;
		this.gap = gap;
		this.inputs = inputs;
	}
}

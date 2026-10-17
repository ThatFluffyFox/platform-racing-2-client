package pr2.gameplay.debug;

import pr2.character.CharacterState;
import pr2.gameplay.player.LocalPlayerController;
import pr2.gameplay.player.LocalPlayerInput;
import pr2.level.BlockType;
import pr2.level.Level;
import pr2.level.Level.LevelBlock;
import pr2.level.Level.StatDefaults;
import pr2.level.Level.TilePosition;

/**
	Debug-only clip search core, shared by the in-game Clip Finder (F9+C+D) and
	`tools/clip_sweep.sh`. Not part of the Flash client.

	A run simulates the real `LocalPlayerController` from a start position with
	fixed stats and a scripted input sequence, inside a cropped copy of the
	level, and reports the first frame where the player's body midpoint (the
	point Flash samples for `bodyTouch`) is inside a solid block. Every run
	builds its own player, and its own blocks whenever they can break or move,
	so one attempt never affects the next.
**/
class ClipSimulator {
	public static inline var TILE:Int = 30;

	/** Frames a recorded run keeps after the clip, so a replay shows the player sinking through. **/
	public static inline var GHOST_TAIL_FRAMES:Int = 20;

	/**
		Runs one attempt. `recordGhost` keeps every frame's pose for a replay.
		`onFrame(frame, input, player, bodyInSolid)` is for tracing; when given,
		the run plays all of `attempt.frames` instead of stopping early.

		If the player leaves the cropped area, the area grows to take in where it
		went and the attempt is run again from the start, so the simulated level
		always covers the whole path (up to the level's edge plus open air).

		A recorded run keeps going `tailFrames` after the clip, or until the
		player has stood still outside any block for 10 frames, whichever is
		first; the level scanner uses a long tail to see where a clip leads.
	**/
	public static function run(area:ClipArea, attempt:ClipAttempt, recordGhost:Bool = false,
			?onFrame:Int->LocalPlayerInput->LocalPlayerController->Bool->Void, tailFrames:Int = GHOST_TAIL_FRAMES):ClipRun {
		if (onFrame != null) {
			// Grow the area first with a silent run, so the traced run happens once.
			run(area, attempt, recordGhost, null, tailFrames);
		}
		while (true) {
			var result = runOnce(area, attempt, recordGhost, onFrame, tailFrames);
			if (result != null) return result;
		}
	}

	/** One pass in the current area; null when the area grew and the attempt must restart. **/
	static function runOnce(area:ClipArea, attempt:ClipAttempt, recordGhost:Bool,
			onFrame:Null<Int->LocalPlayerInput->LocalPlayerController->Bool->Void>, tailFrames:Int):Null<ClipRun> {
		var level = area.buildLevel(attempt.gravity);
		if (area.overlapsSolid(level, attempt.startX, attempt.startY)) {
			return ClipRun.blocked();
		}
		var player = new LocalPlayerController(level);
		player.setStartingStats(attempt.speed, attempt.accel, attempt.jump);
		player.setGravity(attempt.gravity);
		if (attempt.hats != null) attempt.hats.applyTo(player);
		// Clears the constructor's grounded state, then one idle frame lets the
		// real collision pass decide it: floor starts stand, mid-air starts fall.
		player.resetPreRacePosition(attempt.startX, attempt.startY);
		// The fall-off-the-map return uses the whole level's extent, not the crop's.
		player.setMapBoundsForClipSearch(area.mapMinX, area.mapMinY, area.mapMaxX, area.mapMaxY);
		player.step(new LocalPlayerInput());

		var ghost:Null<Array<GhostFrame>> = recordGhost ? [GhostFrame.capture(player, bodyInSolid(level, player))] : null;
		var settledFrames = 0;
		var longTail = tailFrames > GHOST_TAIL_FRAMES;
		var clipFrame = -1;
		var clipX = 0.0, clipY = 0.0, clipVx = 0.0, clipVy = 0.0;
		var stopAt = attempt.frames;
		var frame = 0;
		while (frame < stopAt) {
			var input = attempt.inputAt(frame, player.grounded);
			player.step(input);
			var inSolid = bodyInSolid(level, player);
			if (ghost != null) ghost.push(GhostFrame.capture(player, inSolid));
			if (onFrame != null) onFrame(frame, input, player, inSolid);
			if (clipFrame < 0 && inSolid && attempt.hitsTarget(player.x, player.y)) {
				clipFrame = frame;
				clipX = player.x;
				clipY = player.y;
				clipVx = player.vx;
				clipVy = player.vy;
				if (ghost == null && onFrame == null) break;
				if (ghost != null) {
					// A long tail (the scanner) may run past the scripted frames to see where the player ends up.
					stopAt = longTail ? frame + 1 + tailFrames : Std.int(Math.min(attempt.frames, frame + 1 + tailFrames));
				}
			}
			if (onFrame == null) {
				// Left the crop: grow it and start over, or stop if the player is
				// past the level's edge (nothing out there to clip into).
				if (!area.containsPixel(player.x, player.y)) {
					if (area.growToInclude(player.x, player.y)) return null;
					if (clipFrame < 0) break;
				}
				// Over once the scripted jump is done and the player has stood still for a while.
				settledFrames = player.grounded && Math.abs(player.vx) < 0.5 && Math.abs(player.vy) < 1 ? settledFrames + 1 : 0;
				if (clipFrame < 0 && attempt.scriptFinished(frame) && settledFrames >= 10) break;
				// After a clip, a long tail ends once the player has come to rest outside the blocks.
				if (clipFrame >= 0 && longTail && settledFrames >= 10 && !inSolid) break;
			}
			frame++;
		}
		return new ClipRun(clipFrame, clipX, clipY, clipVx, clipVy, ghost);
	}

	/** True when the body midpoint (Flash's `bodyTouch` point) is inside a live solid block. **/
	public static function bodyInSolid(level:Level, player:LocalPlayerController):Bool {
		var block = level.blockAt(tileOf(player.x), tileOf(player.y - 15));
		return block != null && block.type.isSolid() && !player.blockController.isBlockRemoved(block);
	}

	public static inline function tileOf(px:Float):Int {
		return Std.int(Math.floor(px / TILE));
	}
}

/** One scripted attempt: start, stats, gravity and the inputs held on each frame. **/
class ClipAttempt {
	public final startX:Float;
	public final startY:Float;
	public final speed:Float;
	public final accel:Float;
	public final jump:Float;
	public final gravity:Float;
	/** 1 = holds right, -1 = holds left. **/
	public final dir:Int;
	public final jumpFrame:Int;
	public final hold:Int;
	public final down:Bool;
	public final frames:Int;
	/** Explicit per-frame inputs (random fuzzing); overrides the jump script. **/
	public var script:Null<Array<LocalPlayerInput>> = null;
	/** Physics-affecting hats worn by the simulated player (none when null). **/
	public var hats:Null<ClipHats> = null;
	/** Frame the direction starts being held; before it the player stands or jumps in place. **/
	public var moveStart:Int = 0;
	/** Frame the held direction flips (an air turn), or -1 for never. **/
	public var turnFrame:Int = -1;
	/**
		Super jump instead of a normal jump: hold down for this many frames, then
		release. LocalPlayerController charges 2 per grounded frame and launches
		with vy = -charge * 0.24 once the charge passes 25, so 13+ frames are
		needed (50 is the 100 cap). 0 = normal jump (`jumpFrame`/`hold`).
	**/
	public var superCharge:Int = 0;
	/** Frame the super jump starts charging (down held from here for `superCharge` frames). **/
	public var superStart:Int = 0;
	/**
		From this frame on nothing is held (-1 = never). The level scan sets it
		to the frame after the clip, so the player comes to rest where the clip
		leads instead of running on.
	**/
	public var releaseFrame:Int = -1;
	/** Only clips into this tile count (the in-game "Target block"); null = any solid block. **/
	public var targetTileX:Null<Int> = null;
	public var targetTileY:Null<Int> = null;

	/** True when the body point at (x, y - 15) is in the target tile, or there is no target. **/
	public function hitsTarget(x:Float, y:Float):Bool {
		if (targetTileX == null || targetTileY == null) return true;
		return ClipSimulator.tileOf(x) == targetTileX && ClipSimulator.tileOf(y - 15) == targetTileY;
	}

	/** Shortest charge that launches (charge 26 > 25) and the frames to the 100 cap. **/
	public static inline var MIN_SUPER_CHARGE:Int = 13;
	public static inline var MAX_SUPER_CHARGE:Int = 50;

	public function new(startX:Float, startY:Float, speed:Float, accel:Float, jump:Float, gravity:Float, dir:Int, jumpFrame:Int, hold:Int,
			down:Bool, frames:Int) {
		this.startX = startX;
		this.startY = startY;
		this.speed = speed;
		this.accel = accel;
		this.jump = jump;
		this.gravity = gravity;
		this.dir = dir;
		this.jumpFrame = jumpFrame;
		this.hold = hold;
		this.down = down;
		this.frames = frames;
	}

	/**
		Holds toward `dir` from `moveStart` (flipping at `turnFrame`). Then either
		holds jump from `jumpFrame` for `hold` frames, or, for a super jump, holds
		down for `superCharge` frames and releases. With `down`, also holds down
		whenever airborne after the launch (fast-fall; never charges on the ground).
	**/
	public function inputAt(frame:Int, grounded:Bool):LocalPlayerInput {
		if (script != null) return script[frame];
		if (releaseFrame >= 0 && frame >= releaseFrame) return new LocalPlayerInput();
		var heldDir = 0;
		if (frame >= moveStart) heldDir = turnFrame >= 0 && frame >= turnFrame ? -dir : dir;
		var jumping = false;
		var holdDown = false;
		if (superCharge > 0) {
			holdDown = frame >= superStart && frame < superStart + superCharge;
		} else {
			jumping = frame >= jumpFrame && frame < jumpFrame + hold;
		}
		if (down && frame >= launchFrame() && !grounded) holdDown = true;
		return new LocalPlayerInput(heldDir == -1, heldDir == 1, jumping, holdDown);
	}

	/** Frame the jump (or super jump release) happens. **/
	public function launchFrame():Int {
		return superCharge > 0 ? superStart + superCharge : jumpFrame;
	}

	/** True once every scripted change (launch, jump hold, move start, turn) has happened. **/
	public function scriptFinished(frame:Int):Bool {
		if (script != null) return false;
		var last = superCharge > 0 ? launchFrame() : jumpFrame + Std.int(Math.min(hold, 30));
		return frame >= last && frame >= moveStart && frame >= turnFrame;
	}

	public function describe():String {
		var stats = 'speed=$speed accel=$accel jump=$jump';
		if (script != null) return '$stats random inputs';
		var move = '${dir == 1 ? "right" : "left"}${moveStart > 0 ? ' from frame $moveStart' : ""}';
		if (turnFrame >= 0) move += ', turn at $turnFrame';
		var launch = superCharge > 0 ? 'super jump (charge $superCharge${superStart > 0 ? ' from frame $superStart' : ""})'
			: 'jump@$jumpFrame hold=${hold >= 999 ? "all" : Std.string(hold)}';
		return '$stats $move, $launch${down ? " +down" : ""}';
	}
}

/**
	The hat flags LocalCharacter.setHats copies onto its controller, so a
	simulated player moves like the real one (cowboy/santa stat floors, top hat
	vanish-block passing, propeller glide, ...). The moon hat's lower gravity is
	carried in the attempt's gravity instead.
**/
class ClipHats {
	public var propeller:Bool = false;
	public var cowboy:Bool = false;
	public var santa:Bool = false;
	public var crown:Bool = false;
	public var party:Bool = false;
	public var jellyfish:Bool = false;
	public var top:Bool = false;
	public var cheese:Bool = false;

	public function new() {}

	public static function from(controller:LocalPlayerController):ClipHats {
		var hats = new ClipHats();
		hats.propeller = controller.propellerHatActive;
		hats.cowboy = controller.cowboyHatActive;
		hats.santa = controller.santaHatActive;
		hats.crown = controller.crownHatActive;
		hats.party = controller.partyHatActive;
		hats.jellyfish = controller.jellyfishHatActive;
		hats.top = controller.topHatActive;
		hats.cheese = controller.cheeseHatActive;
		return hats;
	}

	public function applyTo(player:LocalPlayerController):Void {
		player.propellerHatActive = propeller;
		player.cowboyHatActive = cowboy;
		player.santaHatActive = santa;
		player.crownHatActive = crown;
		player.partyHatActive = party;
		player.jellyfishHatActive = jellyfish;
		player.topHatActive = top;
		player.cheeseHatActive = cheese;
		if (cowboy) player.ensureCowboyStats();
		if (santa) player.ensureSantaStats();
	}

	public function names():Array<String> {
		var out:Array<String> = [];
		if (propeller) out.push("propeller");
		if (cowboy) out.push("cowboy");
		if (santa) out.push("santa");
		if (crown) out.push("crown");
		if (party) out.push("party");
		if (jellyfish) out.push("jellyfish");
		if (top) out.push("top hat");
		if (cheese) out.push("cheese");
		return out;
	}
}

class ClipRun {
	/** Frame (0-based, after the settle frame) of the first clip, or -1. **/
	public final clipFrame:Int;
	public final x:Float;
	public final y:Float;
	public final vx:Float;
	public final vy:Float;
	/** Recorded poses (index 0 = start) when the run was asked to record. **/
	public final ghost:Null<Array<GhostFrame>>;
	public var startBlocked(default, null):Bool = false;

	public function new(clipFrame:Int, x:Float, y:Float, vx:Float, vy:Float, ghost:Null<Array<GhostFrame>>) {
		this.clipFrame = clipFrame;
		this.x = x;
		this.y = y;
		this.vx = vx;
		this.vy = vy;
		this.ghost = ghost;
	}

	public var clipped(get, never):Bool;
	inline function get_clipped():Bool return clipFrame >= 0;

	public static function blocked():ClipRun {
		var run = new ClipRun(-1, 0, 0, 0, 0, null);
		run.startBlocked = true;
		return run;
	}
}

/** One recorded frame of a run, enough to pose a ghost character. **/
class GhostFrame {
	public final x:Float;
	public final y:Float;
	public final state:CharacterState;
	public final facing:Int;
	public final inSolid:Bool;
	public final grounded:Bool;

	public function new(x:Float, y:Float, state:CharacterState, facing:Int, inSolid:Bool, grounded:Bool = false) {
		this.x = x;
		this.y = y;
		this.state = state;
		this.facing = facing;
		this.inSolid = inSolid;
		this.grounded = grounded;
	}

	public static function capture(player:LocalPlayerController, inSolid:Bool):GhostFrame {
		return new GhostFrame(player.x, player.y, player.stateSnapshot().characterState, player.facingScaleX, inSolid, player.grounded);
	}
}

/**
	A cropped, self-contained copy of part of a level. Level.blockAt is a linear
	scan, so a small crop keeps simulation fast even in huge levels. When a run
	leaves the crop, `growToInclude` widens it (up to the level's block extent
	plus a margin) and the run is repeated, so the simulated level always covers
	wherever the player goes.
**/
class ClipArea {
	/** Tiles added around a position the player reached outside the crop. **/
	public static inline var GROW_MARGIN:Int = 10;
	/** Tiles past the level's outermost blocks the crop may grow into (open air). **/
	public static inline var EDGE_MARGIN:Int = 20;

	public var minTileX(default, null):Int;
	public var minTileY(default, null):Int;
	public var maxTileX(default, null):Int;
	public var maxTileY(default, null):Int;
	/** Times the crop has grown, for tests and the status line. **/
	public var growCount(default, null):Int = 0;
	/** The whole level's block extent in pixels, as LocalPlayerController computes it. **/
	public final mapMinX:Float;
	public final mapMinY:Float;
	public final mapMaxX:Float;
	public final mapMaxY:Float;
	/** The level's blocks; the crop copies from these, so they are never mutated here. **/
	final source:Array<LevelBlock>;
	final extentMinTileX:Int;
	final extentMinTileY:Int;
	final extentMaxTileX:Int;
	final extentMaxTileY:Int;
	var template:Array<LevelBlock> = [];
	var startTile:TilePosition;
	var allStatic:Bool = true;
	var sharedLevel:Null<Level> = null;
	var sharedGravity:Float = 0;

	public function new(blocks:Array<LevelBlock>, minTileX:Int, minTileY:Int, maxTileX:Int, maxTileY:Int) {
		source = blocks;
		var t = ClipSimulator.TILE;
		var minX = 0, minY = 0, maxX = 0, maxY = 0;
		for (i in 0...blocks.length) {
			var b = blocks[i];
			if (i == 0) {
				minX = maxX = b.x;
				minY = maxY = b.y;
			} else {
				minX = Std.int(Math.min(minX, b.x));
				minY = Std.int(Math.min(minY, b.y));
				maxX = Std.int(Math.max(maxX, b.x));
				maxY = Std.int(Math.max(maxY, b.y));
			}
		}
		mapMinX = minX * t;
		mapMinY = minY * t;
		mapMaxX = maxX * t;
		mapMaxY = maxY * t;
		extentMinTileX = minX - EDGE_MARGIN;
		extentMinTileY = minY - EDGE_MARGIN;
		extentMaxTileX = maxX + EDGE_MARGIN;
		extentMaxTileY = maxY + EDGE_MARGIN;
		setRect(minTileX, minTileY, maxTileX, maxTileY);
	}

	/** The crop `radiusX` tiles left/right, `up` tiles above and `down` below a world pixel. **/
	public static function around(blocks:Array<LevelBlock>, worldX:Float, worldY:Float, radiusX:Int, up:Int, down:Int):ClipArea {
		var tx = ClipSimulator.tileOf(worldX);
		var ty = ClipSimulator.tileOf(worldY);
		return new ClipArea(blocks, tx - radiusX, ty - up, tx + radiusX, ty + down);
	}

	/**
		Widens the crop to take in the world pixel (plus GROW_MARGIN tiles), but
		not past the level's extent plus EDGE_MARGIN. Returns false when the
		crop cannot grow any further toward that point.
	**/
	public function growToInclude(px:Float, py:Float):Bool {
		var tx = ClipSimulator.tileOf(px);
		var ty = ClipSimulator.tileOf(py);
		var newMinX = clampInt(Std.int(Math.min(minTileX, tx - GROW_MARGIN)), extentMinTileX, extentMaxTileX);
		var newMinY = clampInt(Std.int(Math.min(minTileY, ty - GROW_MARGIN)), extentMinTileY, extentMaxTileY);
		var newMaxX = clampInt(Std.int(Math.max(maxTileX, tx + GROW_MARGIN)), extentMinTileX, extentMaxTileX);
		var newMaxY = clampInt(Std.int(Math.max(maxTileY, ty + GROW_MARGIN)), extentMinTileY, extentMaxTileY);
		newMinX = Std.int(Math.min(newMinX, minTileX));
		newMinY = Std.int(Math.min(newMinY, minTileY));
		newMaxX = Std.int(Math.max(newMaxX, maxTileX));
		newMaxY = Std.int(Math.max(newMaxY, maxTileY));
		if (newMinX == minTileX && newMinY == minTileY && newMaxX == maxTileX && newMaxY == maxTileY) return false;
		growCount++;
		setRect(newMinX, newMinY, newMaxX, newMaxY);
		return true;
	}

	function setRect(minX:Int, minY:Int, maxX:Int, maxY:Int):Void {
		minTileX = minX;
		minTileY = minY;
		maxTileX = maxX;
		maxTileY = maxY;
		template = [];
		for (block in source) {
			if (block.x >= minX && block.x <= maxX && block.y >= minY && block.y <= maxY) {
				template.push(LevelBlock.fromWorldPixels(block.code, block.worldX, block.worldY, block.options));
			}
		}
		startTile = new TilePosition(Std.int((minX + maxX) / 2), Std.int((minY + maxY) / 2));
		allStatic = Lambda.foreach(template, b -> isStatic(b.type));
		sharedLevel = null;
	}

	/**
		A Level for one run. The player's BlockController removes and adds
		blocks (crumble, mines, push), so runs only share a Level when every
		block in the area is one that never changes.
	**/
	public function buildLevel(gravity:Float):Level {
		if (sharedLevel != null && sharedGravity == gravity) return sharedLevel;
		var blocks = [for (b in template) LevelBlock.fromWorldPixels(b.code, b.worldX, b.worldY, b.options)];
		var level = new Level("clip-search", "Clip Search", maxTileX - minTileX + 1, maxTileY - minTileY + 1, ClipSimulator.TILE, gravity,
			new StatDefaults(50, 1, 3), startTile, startTile, blocks, minTileX, minTileY);
		if (allStatic) {
			sharedLevel = level;
			sharedGravity = gravity;
		}
		return level;
	}

	/** A start position is unusable if the standing player would overlap a block. **/
	public function overlapsSolid(level:Level, x:Float, y:Float):Bool {
		for (point in [[x - 9, y - 1], [x + 9, y - 1], [x, y - 15], [x, y - 30], [x - 9, y - 50], [x + 9, y - 50]]) {
			var block = level.blockAt(ClipSimulator.tileOf(point[0]), ClipSimulator.tileOf(point[1]));
			if (block != null && block.type.isSolid()) return true;
		}
		return false;
	}

	public function containsPixel(x:Float, y:Float):Bool {
		var t = ClipSimulator.TILE;
		return x >= minTileX * t && x < (maxTileX + 1) * t && y >= minTileY * t && y < (maxTileY + 2) * t;
	}

	public function blockCount():Int {
		return template.length;
	}

	static inline function clampInt(value:Int, min:Int, max:Int):Int {
		return value < min ? min : (value > max ? max : value);
	}

	static function isStatic(type:BlockType):Bool {
		return switch (type) {
			case Basic | Ice | Start | Water | ArrowUp | ArrowDown | ArrowLeft | ArrowRight: true;
			default: false;
		}
	}
}

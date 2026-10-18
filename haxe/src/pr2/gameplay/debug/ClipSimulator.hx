package pr2.gameplay.debug;

import pr2.character.CharacterState;
import pr2.gameplay.RotationMath;
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
@:access(pr2.gameplay.player.LocalPlayerController)
class ClipSimulator {
	public static inline var TILE:Int = 30;
	/** Seed for item-block rolls in simulations, so a run that collects an item gets the same one every time. **/
	public static inline var ITEM_SEED:Int = 20240611;

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

	/**
		A simulated player standing at the start in the same state every search
		uses (and "Replay on me" reproduces): fresh motion state, the given stats,
		gravity and hats, the whole level's map edges, then one idle frame.
	**/
	public static function preparePlayer(area:ClipArea, level:Level, startX:Float, startY:Float, speed:Float, accel:Float, jump:Float,
			gravity:Float, hats:Null<ClipHats>, ?items:ClipItems):LocalPlayerController {
		// Our own block controller: its clock counts frames, so move blocks and
		// freezes run the same way in every replay (the game's runs on the wall clock).
		var blocks = new ClipBlockController(level);
		var player = new LocalPlayerController(level, blocks);
		blocks.startGameplay();
		player.setStartingStats(speed, accel, jump);
		player.setGravity(gravity);
		if (hats != null) hats.applyTo(player);
		rollItemsFromState(player);
		if (items != null) items.applyTo(player);
		// Clears the constructor's grounded state, then one idle frame lets the
		// real collision pass decide it: floor starts stand, mid-air starts fall.
		player.resetPreRacePosition(startX, startY);
		// The fall-off-the-map return uses the whole level's extent, not the crop's.
		player.setMapBoundsForClipSearch(area.mapMinX, area.mapMinY, area.mapMaxX, area.mapMaxY);
		watchAddedBlocks(player);
		player.step(new LocalPlayerInput());
		return player;
	}

	/** One pass in the current area; null when the area grew and the attempt must restart. **/
	static function runOnce(area:ClipArea, attempt:ClipAttempt, recordGhost:Bool,
			onFrame:Null<Int->LocalPlayerInput->LocalPlayerController->Bool->Void>, tailFrames:Int):Null<ClipRun> {
		var level = area.buildLevel(attempt.gravity);
		if (area.overlapsSolid(level, attempt.startX, attempt.startY)) {
			return ClipRun.blocked();
		}
		var player = preparePlayer(area, level, attempt.startX, attempt.startY, attempt.speed, attempt.accel, attempt.jump, attempt.gravity,
			attempt.hats);

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
		var body = toLevel(player.x, player.y - 15, player.courseRotation);
		var block = level.blockAt(tileOf(body.x), tileOf(body.y));
		return block != null && block.type.isSolid() && !player.blockController.isBlockRemoved(block);
	}

	/**
		Item blocks roll with Math.random in the game. In a simulation the roll
		comes from the player's own state (position, speed, the block clock), so
		a replay of a script, or a copy of a player, always gets the same item
		(the real game may roll a different one).
	**/
	public static function rollItemsFromState(player:LocalPlayerController):Void {
		player.itemRandom = function():Float {
			var frames = Std.isOfType(player.blockController, ClipBlockController) ? (cast player.blockController : ClipBlockController).frames : 0;
			var h = ITEM_SEED ^ Std.int(player.x * 7) * 73856093 ^ Std.int(player.y * 7) * 19349663 ^ frames * 83492791;
			h = (h ^ (h >>> 13)) * 1274126177;
			h = h ^ (h >>> 16);
			return (h & 0x7fffffff) / 2147483648.0;
		};
	}

	/** Blocks the run adds (a placed mine, a returning crumble) join the indexed level's loose list. **/
	public static function watchAddedBlocks(player:LocalPlayerController):Void {
		if (Std.isOfType(player.level, ClipLevel)) {
			var indexed:ClipLevel = cast player.level;
			player.blockController.onBlockAdded = indexed.blockAdded;
		}
	}

	/**
		A point in the player's (course) space as a point in the level's own
		space. After a rotate block turns the course, the controller keeps the
		player in rotated coordinates; blocks, targets and the ghost use the
		level's. Same mapping as RotationMath.rotatePoint, without truncation.
	**/
	public static function toLevel(x:Float, y:Float, rotation:Int):{x:Float, y:Float} {
		return switch (RotationMath.normalizeDisplayRotation(rotation)) {
			case 90: {x: y, y: -x};
			case 180 | -180: {x: -x, y: -y};
			case -90: {x: -y, y: x};
			default: {x: x, y: y};
		}
	}

	/** The inverse of `toLevel`: a level point in a course turned by `rotation`. **/
	public static function toCourse(x:Float, y:Float, rotation:Int):{x:Float, y:Float} {
		return toLevel(x, y, -rotation);
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
		if (script != null) return frame < script.length ? script[frame] : new LocalPlayerInput();
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
	/** The feet, in the level's own space (the same as the player's while the course is upright). **/
	public final x:Float;
	public final y:Float;
	public final state:CharacterState;
	public final facing:Int;
	public final inSolid:Bool;
	public final grounded:Bool;
	/** How far the simulated course was turned by rotate blocks (0, 90, 180 or -90). **/
	public final rotation:Int;

	public function new(x:Float, y:Float, state:CharacterState, facing:Int, inSolid:Bool, grounded:Bool = false, rotation:Int = 0) {
		this.x = x;
		this.y = y;
		this.state = state;
		this.facing = facing;
		this.inSolid = inSolid;
		this.grounded = grounded;
		this.rotation = rotation;
	}

	public static function capture(player:LocalPlayerController, inSolid:Bool):GhostFrame {
		var feet = ClipSimulator.toLevel(player.x, player.y, player.courseRotation);
		return new GhostFrame(feet.x, feet.y, player.stateSnapshot().characterState, player.facingScaleX, inSolid, player.grounded,
			player.courseRotation);
	}
}

/**
	The item a simulated player starts with (normally the real player's), and
	which items the level's item blocks may give.
**/
class ClipItems {
	public var heldItem:Null<Int> = null;
	public var allowedItems:Null<Array<Int>> = null;

	public function new(?heldItem:Int, ?allowedItems:Array<Int>) {
		this.heldItem = heldItem;
		this.allowedItems = allowedItems;
	}

	/** From the real player: the item they hold and the level's allowed items. **/
	@:access(pr2.gameplay.player.LocalPlayerController)
	public static function from(player:LocalPlayerController):ClipItems {
		return new ClipItems(player.itemId, player.allowedItems.copy());
	}

	public function applyTo(player:LocalPlayerController):Void {
		if (allowedItems != null) player.setAllowedItems(allowedItems);
		var item = heldItem;
		if (item != null) player.grantItemForDebug(item);
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
		var level = new ClipLevel("clip-search", "Clip Search", maxTileX - minTileX + 1, maxTileY - minTileY + 1, ClipSimulator.TILE, gravity,
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

/**
	A simulation-only Level with a tile index, so `blockAt` doesn't scan every
	block (Level.blockAt is a linear scan; a big simulated area makes each
	frame slow). It answers exactly as the scan does: blocks that can change
	tile (push and move blocks) and blocks added during the run are kept in a
	short list that is still scanned, removed blocks are skipped (they lose
	collisionActive), and if two blocks match, the later one in `blocks` wins,
	like the scan from the end.
**/
class ClipLevel extends Level {
	final index:Map<Int, LevelBlock> = new Map();
	final loose:Array<LevelBlock> = [];

	public function new(id:String, name:String, widthTiles:Int, heightTiles:Int, tileSize:Int, gravity:Float, stats:StatDefaults,
			playerStart:TilePosition, finish:TilePosition, blocks:Array<LevelBlock>, minTileX:Int, minTileY:Int) {
		super(id, name, widthTiles, heightTiles, tileSize, gravity, stats, playerStart, finish, blocks, minTileX, minTileY);
		for (block in blocks) {
			if (block.isMarker() || !block.collisionActive) continue;
			if (canMove(block.type)) {
				loose.push(block);
			} else {
				index.set(key(block.x, block.y), block);
			}
		}
	}

	static inline function key(x:Int, y:Int):Int return (x & 0xffff) << 16 | (y & 0xffff);

	static function canMove(type:BlockType):Bool {
		return type == BlockType.Push || type == BlockType.Move;
	}

	public function blockAdded(block:LevelBlock):Void {
		if (!block.isMarker()) loose.push(block);
	}

	override public function blockAt(x:Int, y:Int):Null<LevelBlock> {
		var found = index.get(key(x, y));
		if (found != null && !(found.collisionActive && found.x == x && found.y == y)) found = null;
		for (block in loose) {
			if (block.collisionActive && block.x == x && block.y == y) {
				if (found == null || blocks.indexOf(block) > blocks.indexOf(found)) found = block;
			}
		}
		return found;
	}
}

/** Simulation block controller whose clock counts frames (30 a second) instead of reading the wall clock. **/
class ClipBlockController extends BlockController {
	public var frames:Int = 0;

	public function new(level:Level) {
		super(level);
		useFrameClock(this);
	}

	/** (Re)points the clock at this controller's own frame count (also after a copy). **/
	public static function useFrameClock(controller:ClipBlockController):Void {
		Reflect.setField(controller, "clock", function():Float return controller.frames * 1000 / pr2.Constants.SIMULATION_FRAME_RATE);
	}

	override public function update():Void {
		frames++;
		super.update();
	}
}

/**
	Copies a simulated player with everything it owns (its level and blocks,
	block controller, item state), so the route planner can try many moves from
	one spot without replaying the route from the start each time. Functions
	can't be copied, so the few the simulation sets up are pointed at the copy.
**/
@:access(pr2.gameplay.player.LocalPlayerController)
class ClipSnapshot {
	public static function copy(source:LocalPlayerController):LocalPlayerController {
		var seen = new haxe.ds.ObjectMap<Dynamic, Dynamic>();
		var player:LocalPlayerController = deep(source, seen);
		var blocks = player.blockController;
		if (Std.isOfType(blocks, ClipBlockController)) ClipBlockController.useFrameClock(cast blocks);
		ClipSimulator.rollItemsFromState(player);
		ClipSimulator.watchAddedBlocks(player);
		return player;
	}

	static function deep(value:Dynamic, seen:haxe.ds.ObjectMap<Dynamic, Dynamic>):Dynamic {
		switch (Type.typeof(value)) {
			case TNull | TInt | TFloat | TBool | TFunction | TEnum(_) | TUnknown:
				return value;
			case TClass(String):
				return value;
			default:
		}
		var known = seen.get(value);
		if (known != null) return known;
		if (Std.isOfType(value, Array)) {
			var items:Array<Dynamic> = value;
			var list:Array<Dynamic> = [];
			seen.set(value, list);
			for (item in items) list.push(deep(item, seen));
			return list;
		}
		if (Std.isOfType(value, haxe.ds.StringMap)) {
			var map:haxe.ds.StringMap<Dynamic> = value;
			var out = new haxe.ds.StringMap<Dynamic>();
			seen.set(value, out);
			for (key in map.keys()) out.set(key, deep(map.get(key), seen));
			return out;
		}
		if (Std.isOfType(value, haxe.ds.IntMap)) {
			var map:haxe.ds.IntMap<Dynamic> = value;
			var out = new haxe.ds.IntMap<Dynamic>();
			seen.set(value, out);
			for (key in map.keys()) out.set(key, deep(map.get(key), seen));
			return out;
		}
		if (Std.isOfType(value, haxe.ds.ObjectMap)) {
			var map:haxe.ds.ObjectMap<Dynamic, Dynamic> = value;
			var out = new haxe.ds.ObjectMap<Dynamic, Dynamic>();
			seen.set(value, out);
			for (key in map.keys()) out.set(deep(key, seen), deep(map.get(key), seen));
			return out;
		}
		var cls = Type.getClass(value);
		var copy:Dynamic = cls == null ? {} : Type.createEmptyInstance(cls);
		seen.set(value, copy);
		for (field in Reflect.fields(value)) {
			// Haxe/JS caches bound methods per object; a copy must bind its own.
			if (field == "hx__closures__" || field == "__id__") continue;
			Reflect.setField(copy, field, deep(Reflect.field(value, field), seen));
		}
		return copy;
	}
}

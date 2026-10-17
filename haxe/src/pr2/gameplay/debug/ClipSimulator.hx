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
	**/
	public static function run(area:ClipArea, attempt:ClipAttempt, recordGhost:Bool = false,
			?onFrame:Int->LocalPlayerInput->LocalPlayerController->Bool->Void):ClipRun {
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
		player.step(new LocalPlayerInput());

		var ghost:Null<Array<GhostFrame>> = recordGhost ? [GhostFrame.capture(player, bodyInSolid(level, player))] : null;
		var settledFrames = 0;
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
			if (clipFrame < 0 && inSolid) {
				clipFrame = frame;
				clipX = player.x;
				clipY = player.y;
				clipVx = player.vx;
				clipVy = player.vy;
				if (ghost == null && onFrame == null) break;
				if (ghost != null) stopAt = Std.int(Math.min(attempt.frames, frame + 1 + GHOST_TAIL_FRAMES));
			}
			if (onFrame == null) {
				// Over once the scripted jump is done and the player has stood
				// still for a while, or has left the cropped area.
				settledFrames = player.grounded && Math.abs(player.vx) < 0.5 && Math.abs(player.vy) < 1 ? settledFrames + 1 : 0;
				if (clipFrame < 0 && attempt.scriptFinished(frame) && settledFrames >= 10) break;
				if (clipFrame < 0 && !area.containsPixel(player.x, player.y)) break;
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
		Holds toward `dir` the whole time, holds jump from `jumpFrame` for `hold`
		frames, and (with `down`) holds down whenever airborne after the jump.
	**/
	public function inputAt(frame:Int, grounded:Bool):LocalPlayerInput {
		if (script != null) return script[frame];
		var jumping = frame >= jumpFrame && frame < jumpFrame + hold;
		var fastFall = down && frame >= jumpFrame && !grounded;
		return new LocalPlayerInput(dir == -1, dir == 1, jumping, fastFall);
	}

	public function scriptFinished(frame:Int):Bool {
		return script == null && frame >= jumpFrame + Std.int(Math.min(hold, 30));
	}

	public function describe():String {
		var stats = 'speed=$speed accel=$accel jump=$jump';
		if (script != null) return '$stats random inputs';
		return '$stats ${dir == 1 ? "right" : "left"} jump@$jumpFrame hold=${hold >= 999 ? "all" : Std.string(hold)}${down ? " +down" : ""}';
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

	public function new(x:Float, y:Float, state:CharacterState, facing:Int, inSolid:Bool) {
		this.x = x;
		this.y = y;
		this.state = state;
		this.facing = facing;
		this.inSolid = inSolid;
	}

	public static function capture(player:LocalPlayerController, inSolid:Bool):GhostFrame {
		return new GhostFrame(player.x, player.y, player.stateSnapshot().characterState, player.facingScaleX, inSolid);
	}
}

/**
	A cropped, self-contained copy of part of a level. Level.blockAt is a linear
	scan, so a small crop keeps simulation fast even in huge levels.
**/
class ClipArea {
	public final minTileX:Int;
	public final minTileY:Int;
	public final maxTileX:Int;
	public final maxTileY:Int;
	final template:Array<LevelBlock>;
	final startTile:TilePosition;
	final allStatic:Bool;
	var sharedLevel:Null<Level> = null;
	var sharedGravity:Float = 0;

	public function new(blocks:Array<LevelBlock>, minTileX:Int, minTileY:Int, maxTileX:Int, maxTileY:Int) {
		this.minTileX = minTileX;
		this.minTileY = minTileY;
		this.maxTileX = maxTileX;
		this.maxTileY = maxTileY;
		template = [];
		for (block in blocks) {
			if (block.x >= minTileX && block.x <= maxTileX && block.y >= minTileY && block.y <= maxTileY) {
				template.push(LevelBlock.fromWorldPixels(block.code, block.worldX, block.worldY, block.options));
			}
		}
		startTile = new TilePosition(Std.int((minTileX + maxTileX) / 2), Std.int((minTileY + maxTileY) / 2));
		allStatic = Lambda.foreach(template, b -> isStatic(b.type));
	}

	/** The crop `radiusX` tiles left/right, `up` tiles above and `down` below a world pixel. **/
	public static function around(blocks:Array<LevelBlock>, worldX:Float, worldY:Float, radiusX:Int, up:Int, down:Int):ClipArea {
		var tx = ClipSimulator.tileOf(worldX);
		var ty = ClipSimulator.tileOf(worldY);
		return new ClipArea(blocks, tx - radiusX, ty - up, tx + radiusX, ty + down);
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

	static function isStatic(type:BlockType):Bool {
		return switch (type) {
			case Basic | Ice | Start | Water | ArrowUp | ArrowDown | ArrowLeft | ArrowRight: true;
			default: false;
		}
	}
}

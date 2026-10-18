package pr2.gameplay.debug;

import pr2.gameplay.debug.ClipFinder.FoundClip;
import pr2.gameplay.debug.ClipScanner.ClipScanSettings;
import pr2.gameplay.debug.ClipSimulator.ClipArea;
import pr2.gameplay.debug.ClipSimulator.ClipAttempt;
import pr2.gameplay.debug.ClipSimulator.ClipItems;
import pr2.gameplay.player.LocalPlayerController;
import pr2.gameplay.player.LocalPlayerInput;
import pr2.level.BlockType;
import pr2.level.Level.LevelBlock;

/** What a movement glitch does that normal movement can't. **/
enum GlitchKind {
	/** Rises higher above the floor it left than any move can on open ground. **/
	TooHigh;
	/** Moves faster sideways than any move can on open ground. **/
	TooFast;
	/** Gains height while only walking (no jump, super jump or item), off no block meant to lift it. **/
	ClimbWithoutJump;
	/**
		Moved further in one frame than its speed carries it (more than 12 px
		past both frames' speed): the collision code snapped the player
		somewhere (not a respawn, teleport or course turn).
	**/
	CollisionSnap;
	/** Stays in the air without rising or falling for 8 frames or more (not swimming, flying a jetpack or with the cowboy hat). **/
	Hover;
}

/** One movement glitch: the moves that do it, the recorded run, and what happened. **/
class MovementGlitch {
	public final kind:GlitchKind;
	public final found:FoundClip;
	/** How much more than open ground: px of height, or px per frame of speed. **/
	public final excess:Float;
	/** The block involved when it happened (its type and tile), if any. **/
	public final cause:String;
	/** Frame it happened on. **/
	public final frame:Int;
	public final tileX:Int;
	public final tileY:Int;

	public function new(kind:GlitchKind, found:FoundClip, excess:Float, cause:String, frame:Int, tileX:Int, tileY:Int) {
		this.kind = kind;
		this.found = found;
		this.excess = excess;
		this.cause = cause;
		this.frame = frame;
		this.tileX = tileX;
		this.tileY = tileY;
	}

	public function describe():String {
		var what = switch (kind) {
			case TooHigh: 'jumps ${Math.round(excess)} px higher than anything can on open ground';
			case TooFast: 'moves ${Math.round(excess * 10) / 10} px/frame faster than anything can on open ground';
			case ClimbWithoutJump: 'climbs ${Math.round(excess)} px without jumping';
			case CollisionSnap: 'is snapped ${Math.round(excess)} px further than its speed carries it in one frame';
			case Hover: 'hangs in the air for ${Math.round(excess)} frames';
		}
		return '$what (frame ${frame + 1}, at tile $tileX,$tileY${cause != "" ? ", " + cause : ""})';
	}
}

/**
	Stage 3 of the Clip Finder: movement glitches. Every move is first played on
	open ground (a long flat floor) with your stats, gravity, hats and item, so
	the finder knows how high and how fast anything can go there. Then moves
	are played from spots you can stand on in the level, nearest first; a run
	that jumps higher or moves faster than that, climbs while only walking,
	is snapped further in one frame than its speed, or hangs in the air is a
	glitch. Head clips into block edges and clips through blocks are not (the
	clip stages cover those). Runs boosted by blocks that are meant to
	(arrows, mines, teleports, item blocks, rotate blocks, water) are left out,
	so what is listed comes from the level's shapes: bumps, corners, block
	edges, crouching and so on. Each glitch (one per spot, kind and block)
	goes in the clip list, with the ghost and Replay on me.
**/
@:access(pr2.gameplay.player.LocalPlayerController)
class MovementGlitchFinder {
	static inline var JET_PACK:Int = 6;
	/** Frames each move is played. **/
	public static inline var FRAMES:Int = 90;
	/** Extra height (px) and speed (px/frame) over open ground that count as a glitch. **/
	public static inline var HEIGHT_MARGIN:Float = 20;
	public static inline var SPEED_MARGIN:Float = 1.5;
	/** Spots tried, nearest the player first. **/
	public var maxSpots:Int = 400;

	public final settings:ClipScanSettings;
	public final glitches:Array<MovementGlitch> = [];
	public var spotIndex(default, null):Int = 0;
	public var tested(default, null):Int = 0;

	final blocks:Array<LevelBlock>;
	final probeCharges:Array<Int>;
	var openGround:Null<ClipArea> = null;
	static inline var OPEN_ROW:Int = 100;
	static inline var OPEN_COL:Int = 300;
	final spots:Array<{x:Int, row:Int}>;
	final moves:Array<GlitchMove>;
	var moveIndex:Int = 0;
	final seenKeys:Map<String, Bool> = new Map();

	/**
		`probeCharges` narrows the open-ground probes (super jump charges) and
		`onlyMoves` keeps the moves whose name contains it (both to keep tests quick).
	**/
	public function new(blocks:Array<LevelBlock>, settings:ClipScanSettings, ?probeCharges:Array<Int>, ?onlyMoves:String) {
		this.blocks = blocks;
		this.settings = settings;
		this.probeCharges = probeCharges != null ? probeCharges : PROBE_CHARGES;
		var seen = ClipSimulator.layoutFor(blocks, settings.courseRotation);
		var solid:Map<String, Bool> = new Map();
		for (b in seen) if (!b.isMarker() && b.type.isSolid()) solid.set(b.x + "," + b.y, true);
		inline function isSolid(x:Int, y:Int):Bool return solid.exists(x + "," + y);
		var list = [];
		for (b in seen) {
			// Not on a block that moves the player itself (an arrow bounces it before the move starts).
			if (b.isMarker() || !b.type.isSolid() || b.type == BlockType.Mine || boosts(b.type)) continue;
			if (!isSolid(b.x, b.y - 1) && !isSolid(b.x, b.y - 2)) list.push({x: b.x, row: b.y});
		}
		var ox = settings.originX, oy = settings.originY;
		inline function distance(s:{x:Int, row:Int}):Float {
			var dx = (s.x + 0.5) * ClipSimulator.TILE - ox, dy = s.row * ClipSimulator.TILE - oy;
			return dx * dx + dy * dy;
		}
		list.sort((a, b) -> Reflect.compare(distance(a), distance(b)));
		spots = list;
		var all = movesFor(settings);
		moves = onlyMoves == null ? all : [for (m in all) if (m.label.indexOf(onlyMoves) >= 0) m];
		openGroundLimits();
	}

	/** The most any move reaches on open ground: jump height above the floor left (px) and sideways speed (px/frame). **/
	public var maxRise(default, null):Float = 0;
	public var maxSpeed(default, null):Float = 0;

	public var spotCount(get, never):Int;
	inline function get_spotCount():Int return Std.int(Math.min(spots.length, maxSpots));

	public var done(get, never):Bool;
	inline function get_done():Bool return spotIndex >= spotCount;

	public function progressText(stopped:Bool):String {
		return '${stopped ? "Stopped at" : "Trying moves at"} spot ${Std.int(Math.min(spotIndex + 1, spotCount))}/$spotCount, ${glitches.length} movement glitch';
	}

	public function doneText():String return 'Movement scan done: ${glitches.length} glitches at $spotCount spots (${moves.length} moves each)';

	/** Plays moves until `maxRuns` runs or `deadline()` says time is up. Returns runs made. **/
	public function step(maxRuns:Int, ?deadline:Void->Bool):Int {
		var runs = 0;
		while (!done && runs < maxRuns && (deadline == null || runs == 0 || !deadline())) {
			if (moveIndex >= moves.length) {
				moveIndex = 0;
				spotIndex++;
				continue;
			}
			var spot = spots[spotIndex];
			var move = moves[moveIndex++];
			runs++;
			tryAt(spot, move);
		}
		return runs;
	}

	// ---- Moves -------------------------------------------------------------------

	/** The moves tried at every spot, facing each way, with the held item if any. **/
	static function movesFor(s:ClipScanSettings):Array<GlitchMove> {
		var moves:Array<GlitchMove> = [];
		var item = s.heldItem;
		for (dir in [1, -1]) {
			inline function keys(f:Int, left:Bool, right:Bool, jump:Bool, down:Bool, use:Bool = false):LocalPlayerInput {
				return new LocalPlayerInput(dir == 1 ? left : right, dir == 1 ? right : left, jump, down, use);
			}
			var side = dir == 1 ? "right" : "left";
			// Run and jump: jump held for different lengths, after different run-ups.
			for (run in [0, 8, 20]) for (hold in [999, 10, 3]) {
				moves.push(new GlitchMove('run $side ${run}f, jump held ${hold >= 999 ? "all" : Std.string(hold)}', dir,
					[for (f in 0...FRAMES) keys(f, false, true, f >= run && f < run + hold, false)]));
			}
			// Jump straight up against whatever is beside, then drift in.
			moves.push(new GlitchMove('jump up, drift $side', dir, [for (f in 0...FRAMES) keys(f, false, f >= 6, f < 999, false)]));
			// Hop repeatedly (jump, let go, jump) moving the whole time.
			moves.push(new GlitchMove('bunny hop $side', dir, [for (f in 0...FRAMES) keys(f, false, true, f % 12 < 6, false)]));
			// Super jumps: charge, then release running or standing.
			for (charge in [35, 50]) for (standing in [false, true]) {
				moves.push(new GlitchMove('super jump (charge $charge)${standing ? " then " + side : " running " + side}', dir,
					[for (f in 0...FRAMES) keys(f, false, !standing || f >= charge, false, f < charge)]));
			}
			// Crouch-walk and jump out (low ceilings bump and crouch the player).
			moves.push(new GlitchMove('crouch $side then jump', dir, [for (f in 0...FRAMES) keys(f, false, true, f >= 15 && f < 40, f < 15)]));
			// Only walking: nothing here should lift the player.
			moves.push(new GlitchMove('walk $side', dir, [for (f in 0...FRAMES) keys(f, false, true, false, false)], true));
			moves.push(new GlitchMove('walk $side, turn back at frame 30', dir, [for (f in 0...FRAMES) keys(f, f >= 30, f < 30, false, false)], true));
			moves.push(new GlitchMove('walk $side, stop at frame 20', dir, [for (f in 0...FRAMES) keys(f, false, f < 20, false, false)], true));
			// Fast-fall after a full jump.
			moves.push(new GlitchMove('jump $side, fast-fall', dir, [for (f in 0...FRAMES) keys(f, false, true, f < 12, f >= 12)]));
			if (item != null) {
				// Use the held item at the top of a jump, and at the start.
				for (at in [0, 10, 20]) {
					moves.push(new GlitchMove('jump $side, use item on frame $at', dir,
						[for (f in 0...FRAMES) keys(f, false, true, f < 999, false, f == at)]));
				}
			}
		}
		return moves;
	}

	/**
		How high and fast the player can go on open ground at all: every super
		jump charge (0-50 frames) with a jump pressed just before, on, or after
		the release, running the whole time, and the held item used on every
		frame of a full jump. A run in the level that beats these is a glitch,
		whatever its timing.
	**/
	function openGroundLimits():Void {
		var probes:Array<Array<LocalPlayerInput>> = [];
		for (charge in probeCharges) for (offset in [-1, 0, 1]) {
			var jumpAt = charge + offset;
			if (jumpAt < 0) continue;
			probes.push([for (f in 0...FRAMES) new LocalPlayerInput(false, f >= charge, f >= jumpAt, f < charge)]);
		}
		if (settings.heldItem != null) for (at in [for (a in 0...20) a * 2]) {
			probes.push([for (f in 0...FRAMES) new LocalPlayerInput(false, true, true, false, f == at)]);
		}
		for (inputs in probes) {
			var probe = new GlitchMove("open ground", 1, inputs);
			baseline(probe);
			maxRise = Math.max(maxRise, probe.baseRise);
			maxSpeed = Math.max(maxSpeed, probe.baseSpeed);
		}
	}

	/** Plays `move` on open ground to learn how high (above the floor) and how fast it goes. **/
	function baseline(move:GlitchMove):Void {
		var t = ClipSimulator.TILE;
		var floorRow = OPEN_ROW, startCol = OPEN_COL;
		var area = openGround;
		if (area == null) {
			// Built once: a long flat floor, the same for every probe.
			var floor = [for (c in startCol - 200...startCol + 201) new LevelBlock(c, floorRow, BlockType.Basic)];
			openGround = area = new ClipArea(floor, startCol - 220, floorRow - 150, startCol + 220, floorRow + 20);
		}
		var level = area.buildLevel(settings.gravity);
		var floorY = floorRow * t;
		var player = ClipSimulator.preparePlayer(area, level, startCol * t + 15, floorY, settings.speed, settings.accel, settings.jump,
			settings.gravity, settings.hats, items());
		var rise = 0.0, speed = 0.0;
		var ground:Float = floorY;
		for (f in 0...FRAMES) {
			player.step(move.inputs[f]);
			if (player.grounded) ground = player.y;
			rise = Math.max(rise, ground - player.y);
			speed = Math.max(speed, Math.abs(player.vx));
		}
		move.baseRise = rise;
		move.baseSpeed = speed;
	}

	function items():Null<ClipItems> return settings.heldItem == null ? null : new ClipItems(settings.heldItem);

	/** Px a frame's move may exceed both frames' speed before it counts as a snap, and the respawn size it stays under. **/
	static inline var SNAP_MARGIN:Float = 12;
	static inline var SNAP_LIMIT:Float = 200;
	/** Frames in the air without moving up or down that count as hovering. **/
	static inline var HOVER_FRAMES:Int = 8;
	/** Px of height gained while only walking that counts as climbing. **/
	static inline var CLIMB_MARGIN:Float = 8;
	/** Frames at the start ignored while the player settles onto the floor. **/
	static inline var SETTLE_FRAMES:Int = 3;
	/** Super jump charges (frames of down) probed on open ground: the shortest, the longest, and between. **/
	static final PROBE_CHARGES:Array<Int> = [0, 13, 20, 26, 30, 35, 40, 45, 50];

	/** Blocks that move the player on purpose: a boost from them is not a glitch. **/
	static function boosts(type:BlockType):Bool {
		return switch (type) {
			case ArrowUp | ArrowDown | ArrowLeft | ArrowRight | Mine | Teleport | Item | InfiniteItem | RotateLeft | RotateRight | Water | Happy
				| Sad | Heart | Time | CustomStats | Push | Move | Finish | Safety:
				true;
			default: false;
		}
	}

	/** Plays `move` from `spot` in the level and records a glitch if it beats open ground. **/
	function tryAt(spot:{x:Int, row:Int}, move:GlitchMove):Void {
		var t = ClipSimulator.TILE;
		var startX = spot.x * t + 15.0, floorY = spot.row * t * 1.0;
		var attempt = new ClipAttempt(startX, floorY, settings.speed, settings.accel, settings.jump, settings.gravity, move.dir, 0, 0, false, FRAMES);
		attempt.script = move.inputs;
		attempt.hats = settings.hats;
		attempt.items = items();
		attempt.courseRotation = settings.courseRotation;
		attempt.label = move.label + ' from tile ${spot.x},${spot.row - 1}';
		var area = ClipArea.aroundCourse(blocks, startX, floorY, 16, 14, 8, settings.courseRotation);
		var boosted = false;
		// Height is measured from the floor last stood on (a jump's height, not the climb).
		var ground = floorY;
		// For walking moves: the lowest floor stood on so far (climbing is measured from it).
		var lowest = floorY;
		var px = startX, py = floorY, pvx = 0.0, pvy = 0.0;
		var still = 0;
		var floats = settings.hats != null && settings.hats.cowboy || settings.heldItem == JET_PACK;
		var glitch:Null<{kind:GlitchKind, excess:Float, frame:Int, x:Float, y:Float, cause:String}> = null;
		var result = ClipSimulator.run(area, attempt, false, (frame:Int, input:LocalPlayerInput, player:LocalPlayerController, inSolid:Bool) -> {
			var touched = player.touchedBlock;
			if (touched != null && boosts(touched.type)) boosted = true;
			// The floor under the feet too (a step touches several blocks; the last one is remembered).
			var under = ClipSimulator.toLevel(player.x, player.y + 1, player.courseRotation);
			var floor = player.level.blockAt(ClipSimulator.tileOf(under.x), ClipSimulator.tileOf(under.y));
			if (player.grounded && floor != null && boosts(floor.type)) boosted = true;
			// A clip (the body midpoint inside a block) is the other stages' business,
			// and a knock-back (mine, sting, zap) or a freeze moves the player on purpose.
			if (inSolid || player.mode == LocalPlayerController.MODE_HURT || player.mode == LocalPlayerController.MODE_FROZEN_SOLID) boosted = true;
			if (player.grounded) {
				ground = player.y;
				// Measured once the start has settled (the first frames place the player on the floor).
				if (frame >= SETTLE_FRAMES) lowest = frame == SETTLE_FRAMES ? player.y : Math.max(lowest, player.y);
			}
			var dx = player.x - px, dy = player.y - py;
			var pvxBefore = pvx, pvyBefore = pvy;
			var snap = Math.max(Math.abs(dx) - Math.abs(pvx) - Math.abs(player.vx), Math.abs(dy) - Math.abs(pvy) - Math.abs(player.vy));
			var moved = Math.sqrt(dx * dx + dy * dy);
			still = !player.grounded && Math.abs(dy) < 0.3 && player.mode != LocalPlayerController.MODE_WATER ? still + 1 : 0;
			px = player.x;
			py = player.y;
			pvx = player.vx;
			pvy = player.vy;
			if (glitch != null || boosted || player.courseRotation != settings.courseRotation) return;
			var rise = ground - player.y;
			var cause = touched == null ? "" : '${touched.type} block';
			if (rise > maxRise + HEIGHT_MARGIN) {
				glitch = {kind: TooHigh, excess: rise - maxRise, frame: frame, x: player.x, y: player.y, cause: cause};
			} else if (Math.abs(player.vx) > maxSpeed + SPEED_MARGIN) {
				glitch = {kind: TooFast, excess: Math.abs(player.vx) - maxSpeed, frame: frame, x: player.x, y: player.y, cause: cause};
			} else if (move.walkOnly && frame > SETTLE_FRAMES && lowest - player.y > CLIMB_MARGIN) {
				glitch = {kind: ClimbWithoutJump, excess: lowest - player.y, frame: frame, x: player.x, y: player.y, cause: cause};
			} else if (snap > SNAP_MARGIN && moved < SNAP_LIMIT && frame > SETTLE_FRAMES) {
				var way = Math.abs(dy) - Math.abs(pvyBefore) >= Math.abs(dx) - Math.abs(pvxBefore) ? (dy < 0 ? "up" : "down") : (dx < 0 ? "left" : "right");
				// Snapped down is the head being pushed back out of a ceiling it was already in (a head clip): not counted.
				if (way != "down") glitch = {kind: CollisionSnap, excess: snap, frame: frame, x: player.x, y: player.y, cause: way + (cause != "" ? ", " + cause : "")};
			} else if (still >= HOVER_FRAMES && !floats) {
				glitch = {kind: Hover, excess: still, frame: frame, x: player.x, y: player.y, cause: cause};
			}
		});
		tested++;
		var g = glitch;
		if (result.startBlocked || g == null || boosted) return;
		var tileX = ClipSimulator.tileOf(g.x), tileY = ClipSimulator.tileOf(g.y - 15);
		var key = '${g.kind}:$tileX,$tileY';
		if (seenKeys.exists(key)) return;
		seenKeys.set(key, true);
		// Record it for the ghost and the replay.
		var recorded = ClipSimulator.run(area, attempt, true, null, 30);
		var level = ClipSimulator.toLevel(g.x, g.y - 15, settings.courseRotation);
		glitches.push(new MovementGlitch(g.kind, new FoundClip(attempt, recorded), g.excess, g.cause, g.frame, ClipSimulator.tileOf(level.x),
			ClipSimulator.tileOf(level.y)));
	}
}

/** One scripted move, with how it goes on open ground. **/
private class GlitchMove {
	public final label:String;
	public final dir:Int;
	public final inputs:Array<LocalPlayerInput>;
	public var baseRise:Float = 0;
	public var baseSpeed:Float = 0;
	/** Only walks (no jump, down or item): any height gained is a glitch. **/
	public final walkOnly:Bool;

	public function new(label:String, dir:Int, inputs:Array<LocalPlayerInput>, walkOnly:Bool = false) {
		this.label = label;
		this.dir = dir;
		this.inputs = inputs;
		this.walkOnly = walkOnly;
	}
}

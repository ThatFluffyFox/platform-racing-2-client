package pr2.gameplay.debug;

import pr2.gameplay.debug.ClipSimulator.ClipArea;
import pr2.gameplay.debug.ClipSimulator.ClipAttempt;
import pr2.gameplay.debug.ClipSimulator.ClipHats;
import pr2.gameplay.debug.ClipSimulator.ClipRun;
import pr2.gameplay.debug.ClipSimulator.GhostFrame;
import pr2.gameplay.debug.ClipScanner.ClipCorner;
import pr2.gameplay.debug.ClipScanner.ClipScanSettings;
import pr2.gameplay.player.LocalPlayerController;
import pr2.gameplay.player.LocalPlayerInput;
import pr2.level.BlockType;
import pr2.level.Level.LevelBlock;

class RouteSettings {
	public var startX:Float;
	public var startY:Float;
	public var speed:Float;
	public var accel:Float;
	public var jump:Float;
	public var gravity:Float;
	public var hats:Null<ClipHats> = null;
	/** The block to reach: touch it, stand on it, or end up inside it. **/
	public var targetTileX:Int;
	public var targetTileY:Int;
	/** Most steps (moves) in a route. **/
	public var maxSteps:Int = 8;
	/** Most standing spots explored before giving up. **/
	public var maxSpots:Int = 300;
	/** A step that goes through a block costs this many normal steps, so clips are only used when they pay off. **/
	public var clipCost:Int = 4;
	/** Clips are only tried toward a wall within this many tiles (negative = no clip moves). **/
	public var clipWallRange:Int = 10;
	/** Mine moves are tried at mines within this many tiles left or right of a spot. **/
	public var mineRange:Int = 8;
	/** The nearest this many mines get mine moves from each spot. **/
	public var minesPerSpot:Int = 3;
	/** False tries only clip and mine moves (no plain walks, jumps or super jumps): to check what they alone reach. **/
	public var normalMoves:Bool = true;
	/** Run-up distances tried when scanning a wall for its clip recipe (null = the scanner's full range). **/
	public var recipeDistances:Null<Array<Int>> = null;
	/** Launches tried for a recipe (null = the scanner's defaults). **/
	public var recipeJumpHolds:Null<Array<Int>> = null;
	public var recipeSuperCharges:Null<Array<Int>> = null;

	public function new(startX:Float, startY:Float, speed:Float, accel:Float, jump:Float, gravity:Float, targetTileX:Int, targetTileY:Int) {
		this.startX = startX;
		this.startY = startY;
		this.speed = speed;
		this.accel = accel;
		this.jump = jump;
		this.gravity = gravity;
		this.targetTileX = targetTileX;
		this.targetTileY = targetTileY;
	}
}

/** One move tried from a standing spot: a short input sequence, followed by letting go until the player is at rest. **/
class RouteMove {
	public final name:String;
	public final inputs:Array<LocalPlayerInput>;
	/** For a clip move, the wall corner to clip (its inputs come from the corner's scanned recipe). **/
	public final corner:Null<ClipCorner>;
	/** For a mine move, the pixel x to walk to and stop on before playing `inputs` (null = play them at once). **/
	public final approachX:Null<Float>;

	public function new(name:String, inputs:Array<LocalPlayerInput>, ?corner:ClipCorner, ?approachX:Float) {
		this.name = name;
		this.inputs = inputs;
		this.corner = corner;
		this.approachX = approachX;
	}
}

/** A standing spot reached by a route: the whole input script from the start to it, at rest. **/
class RouteSpot {
	public final script:Array<LocalPlayerInput>;
	public final x:Float;
	public final y:Float;
	public final steps:Array<String>;
	public final clips:Int;
	public final cost:Int;
	/** Mines blown up on the way here (they don't come back, so they change what the next moves do). **/
	public final minesGone:Int;

	public function new(script:Array<LocalPlayerInput>, x:Float, y:Float, steps:Array<String>, clips:Int, cost:Int, minesGone:Int = 0) {
		this.script = script;
		this.x = x;
		this.y = y;
		this.steps = steps;
		this.clips = clips;
		this.cost = cost;
		this.minesGone = minesGone;
	}

	/** One spot per tile and number of mines gone. **/
	public var key(get, never):String;
	inline function get_key():String return tileX + "," + tileY + "," + minesGone;

	public var tileX(get, never):Int;
	inline function get_tileX():Int return ClipSimulator.tileOf(x);

	public var tileY(get, never):Int;
	inline function get_tileY():Int return ClipSimulator.tileOf(y - 1);
}

/** A found route: the input script from the start to the frame the target is reached. **/
class Route {
	public final script:Array<LocalPlayerInput>;
	public final steps:Array<String>;
	public final clips:Int;
	/** Frame (index into `script`) the player reaches the target. **/
	public final reachFrame:Int;

	public function new(script:Array<LocalPlayerInput>, steps:Array<String>, clips:Int, reachFrame:Int) {
		this.script = script;
		this.steps = steps;
		this.clips = clips;
		this.reachFrame = reachFrame;
	}
}

/** What simulating a script did. **/
class RouteSim {
	public var reachFrame:Int = -1;
	public var clipped:Bool = false;
	public var respawned:Bool = false;
	public var restX:Float = 0;
	public var restY:Float = 0;
	public var atRest:Bool = false;
	public var endInSolid:Bool = false;
	/** Idle frames appended after the script until the player was at rest. **/
	public var idleFrames:Int = 0;
	public var ghost:Null<Array<GhostFrame>> = null;
	/** Inputs a live controller chose (clip moves), in order, after the script. **/
	public var policyInputs:Array<LocalPlayerInput> = [];
	/** The live controller never finished (could not stand on its pixel). **/
	public var policyFailed:Bool = false;
	/** Mines blown up from the start of the script to the end of the run (each one knocks the player back). **/
	public var minesHit:Int = 0;
	/** Mines blown up from `checkFrom` on (by this move). **/
	public var minesHitByMove:Int = 0;

	public function new() {}
}

/**
	Debug-only route planner for the Clip Finder: finds a sequence of moves
	from where the player stands to a chosen block, going through walls and
	floors when that is the way (or the shortest way) there.

	Every route is one input script from the start. A step is tried by
	replaying the route so far plus the new move from the start, in the real
	physics, so each step continues from the exact state the last one left
	(and the finished script replays exactly). Moves: walks of several
	lengths, jumps with several holds and run lengths, super jumps, a jump in
	place, and, toward a wall within reach, a clip. For a clip the level
	scanner first finds a recipe for that wall with these stats (a run-up
	from an exact pixel and a launch); the move then walks to that pixel,
	stops dead, and plays the recipe, and the inputs it used are recorded
	into the route.

	Mines: the real physics already blows them up and knocks the player away
	from their centre (vx/vy += 50 along the angle, then 60 hurt frames), and
	a blown-up mine stays gone for the rest of the route. On top of the moves
	that hit mines by chance, the planner tries mine moves at the nearest
	mines: walk to a set distance from the mine, stop, then walk, hop or jump
	into it (or jump up into one overhead, or step onto one in the floor), so
	the knockback can launch the player somewhere, even into a clip. A spot is
	kept per tile and per number of mines gone. After a move the keys are
	released until the player is at rest; that spot is where the next move
	starts. Spots are searched cheapest first (a step through a block costs
	`clipCost`), one spot per tile. Like the other searches it works a few
	simulations at a time (`step`).
**/
class ClipRoutePlanner {
	/** Idle frames allowed for the player to come to rest after a move. **/
	static inline var SETTLE_FRAMES:Int = 90;
	/** A jump this big between frames is the game returning the player to a safe spot. **/
	static inline var RESPAWN_JUMP:Float = 60;
	/** Most frames a clip move may take to walk to its pixel and play its recipe. **/
	static inline var MAX_POLICY_FRAMES:Int = 400;
	/** Frames a walk to a pixel may take before the move is given up. **/
	static inline var MAX_APPROACH_FRAMES:Int = 240;
	/** Mine moves stop within this many px of their spot (a clip's run-up needs its exact pixel; a mine doesn't). **/
	static inline var MINE_APPROACH_TOLERANCE:Float = 4;
	/** A live controller returns this to give the move up (it could not get where it needed to be). **/
	static final ABORT:LocalPlayerInput = new LocalPlayerInput();

	public final settings:RouteSettings;
	public var route(default, null):Null<Route> = null;
	public var spotsExplored(default, null):Int = 0;
	public var simulations(default, null):Int = 0;
	/** True once a route is found or every reachable spot (within the limits) is explored. **/
	public var done(default, null):Bool = false;

	final area:ClipArea;
	/** Every mine in the level (tile positions). **/
	final mines:Array<LevelBlock>;
	/** Spots waiting to be expanded, cheapest first. **/
	final open:Array<RouteSpot> = [];
	final visited:Map<String, Bool> = new Map();
	var current:Null<RouteSpot> = null;
	var currentMoves:Array<RouteMove> = [];
	var moveIndex:Int = 0;
	final blocksForScans:Array<LevelBlock>;

	public function new(blocks:Array<LevelBlock>, settings:RouteSettings) {
		this.settings = settings;
		blocksForScans = blocks;
		corners = ClipScanner.findCorners(blocks, 1).concat(ClipScanner.findCorners(blocks, -1));
		mines = [for (block in blocks) if (!block.isMarker() && block.type == BlockType.Mine) block];
		area = ClipArea.around(blocks, settings.startX, settings.startY, ClipFinder.AREA_RADIUS_X, ClipFinder.AREA_UP, ClipFinder.AREA_DOWN);
		// The start itself: simulate standing still, in case the target is already touched.
		var start = simulate([], 0, false);
		if (start.reachFrame >= 0) {
			route = new Route([], ["already touching the block"], 0, 0);
			done = true;
			return;
		}
		open.push(new RouteSpot([for (_ in 0...start.idleFrames) new LocalPlayerInput()], start.restX, start.restY, [], 0, 0, start.minesHit));
	}

	/** Runs simulations until `maxRuns` have run or `deadline()` says time is up. Returns runs made. **/
	public function step(maxRuns:Int, ?deadline:Void->Bool):Int {
		var runs = 0;
		while (!done && runs < maxRuns && (deadline == null || runs == 0 || !deadline())) {
			if (stepRecipeScan()) {
				runs++;
				continue;
			}
			if (current == null && !nextSpot()) {
				done = true;
				break;
			}
			var spot = current;
			if (moveIndex >= currentMoves.length) {
				current = null;
				continue;
			}
			var move = currentMoves[moveIndex++];
			runs++;
			if (move.corner != null) {
				// Waits for the wall's recipe scan, then tries the move again.
				if (!tryClipMove(spot, move)) moveIndex--;
			} else if (move.approachX != null) {
				tryApproachMove(spot, move);
			} else {
				tryMove(spot, move);
			}
		}
		return runs;
	}

	function nextSpot():Bool {
		while (open.length > 0) {
			var spot = open.shift();
			var key = spot.key;
			if (visited.exists(key)) continue;
			visited.set(key, true);
			if (spotsExplored >= settings.maxSpots) return false;
			spotsExplored++;
			if (spot.steps.length >= settings.maxSteps) continue;
			current = spot;
			currentMoves = movesFrom(spot);
			moveIndex = 0;
			return true;
		}
		return false;
	}

	function tryMove(spot:RouteSpot, move:RouteMove):Void {
		var script = spot.script.concat(move.inputs);
		finishMove(spot, move.name, script, simulate(script, spot.script.length, false));
	}

	/** Records what a move did: the route if it reached the target, else the spot it came to rest on. **/
	function finishMove(spot:RouteSpot, name:String, script:Array<LocalPlayerInput>, sim:RouteSim):Void {
		var clipped = sim.clipped;
		var stepName = name + (sim.minesHitByMove > 0 ? ' (hits ${sim.minesHitByMove == 1 ? "a mine" : sim.minesHitByMove + " mines"})' : "")
			+ (clipped ? " (through a block)" : "");
		var clips = spot.clips + (clipped ? 1 : 0);
		var cost = spot.cost + (clipped ? settings.clipCost : 1);
		if (sim.reachFrame >= 0) {
			// Reached while letting go after the move: the idle frames are part of the route.
			var reached = script.slice(0, sim.reachFrame + 1);
			while (reached.length <= sim.reachFrame) reached.push(new LocalPlayerInput());
			route = new Route(reached, spot.steps.concat([stepName]), clips, sim.reachFrame);
			done = true;
			return;
		}
		if (sim.respawned || !sim.atRest || sim.endInSolid) return;
		var key = ClipSimulator.tileOf(sim.restX) + "," + ClipSimulator.tileOf(sim.restY - 1) + "," + sim.minesHit;
		if (visited.exists(key)) return;
		var rested = script.concat([for (_ in 0...sim.idleFrames) new LocalPlayerInput()]);
		var landed = ' to ${ClipSimulator.tileOf(sim.restX)},${ClipSimulator.tileOf(sim.restY - 1)}';
		insert(new RouteSpot(rested, sim.restX, sim.restY, spot.steps.concat([stepName + landed]), clips, cost, sim.minesHit));
	}

	/** Keeps `open` sorted by cost (then fewer steps), so the cheapest spot is expanded next. **/
	function insert(spot:RouteSpot):Void {
		var i = open.length;
		while (i > 0 && (open[i - 1].cost > spot.cost || (open[i - 1].cost == spot.cost && open[i - 1].steps.length > spot.steps.length))) i--;
		open.insert(i, spot);
	}

	/**
		Replays `script` from the start, then (with `makePolicy`) lets a live
		controller choose each frame's input until it returns null, then lets go
		until the player is at rest. The target counts as reached on any frame
		from `checkFrom` on. The controller's inputs are returned in
		`policyInputs`, so the route script reproduces the run exactly.
	**/
	public function simulate(script:Array<LocalPlayerInput>, checkFrom:Int, record:Bool, ?makePolicy:Void->RoutePolicy):RouteSim {
		simulations++;
		while (true) {
			var sim = simulateOnce(script, checkFrom, record, makePolicy == null ? null : makePolicy());
			if (sim != null) return sim;
		}
	}

	function simulateOnce(script:Array<LocalPlayerInput>, checkFrom:Int, record:Bool, policy:Null<RoutePolicy>):Null<RouteSim> {
		var s = settings;
		var level = area.buildLevel(s.gravity);
		var player = ClipSimulator.preparePlayer(area, level, s.startX, s.startY, s.speed, s.accel, s.jump, s.gravity, s.hats);
		var sim = new RouteSim();
		if (record) sim.ghost = [GhostFrame.capture(player, ClipSimulator.bodyInSolid(level, player))];
		var prevX = player.x, prevY = player.y;
		var settled = 0;
		var frame = 0;
		var policyFrame = 0;
		var policyDone = policy == null;
		// Blown-up mines leave the level's block list, so counting them tells how many were hit.
		var minesAtStart = countMines(level);
		var minesAtCheck = minesAtStart;
		while (frame < script.length + MAX_POLICY_FRAMES + SETTLE_FRAMES) {
			if (frame == checkFrom) minesAtCheck = countMines(level);
			var input:LocalPlayerInput;
			var idle = false;
			if (frame < script.length) {
				input = script[frame];
			} else if (!policyDone) {
				var chosen = policy(policyFrame++, player);
				if (chosen == ABORT) {
					sim.policyFailed = true;
					break;
				}
				if (chosen == null || policyFrame > MAX_POLICY_FRAMES) {
					policyDone = true;
					if (policyFrame > MAX_POLICY_FRAMES) sim.policyFailed = true;
					if (sim.policyFailed) break;
					idle = true;
					input = new LocalPlayerInput();
				} else {
					sim.policyInputs.push(chosen);
					input = chosen;
				}
			} else {
				idle = true;
				input = new LocalPlayerInput();
			}
			player.step(input);
			var inSolid = ClipSimulator.bodyInSolid(level, player);
			if (sim.ghost != null) sim.ghost.push(GhostFrame.capture(player, inSolid));
			if (!area.containsPixel(player.x, player.y)) {
				if (area.growToInclude(player.x, player.y)) return null;
				sim.respawned = true;
				break;
			}
			if (Math.abs(player.x - prevX) > RESPAWN_JUMP || Math.abs(player.y - prevY) > RESPAWN_JUMP) {
				sim.respawned = true;
				break;
			}
			prevX = player.x;
			prevY = player.y;
			if (frame >= checkFrom) {
				if (inSolid) sim.clipped = true;
				if (touchesTarget(player)) {
					sim.reachFrame = frame;
					break;
				}
			}
			if (idle) {
				sim.idleFrames++;
				settled = player.grounded && Math.abs(player.vx) < 0.5 && Math.abs(player.vy) < 1 ? settled + 1 : 0;
				if (settled >= 10) {
					sim.atRest = true;
					break;
				}
			}
			frame++;
		}
		sim.restX = player.x;
		sim.restY = player.y;
		sim.endInSolid = ClipSimulator.bodyInSolid(level, player);
		var minesAtEnd = countMines(level);
		sim.minesHit = minesAtStart - minesAtEnd;
		sim.minesHitByMove = minesAtCheck - minesAtEnd;
		return sim;
	}

	static function countMines(level:pr2.level.Level):Int {
		var count = 0;
		for (block in level.blocks) if (block.type == BlockType.Mine) count++;
		return count;
	}

	/** The player's box (20 x 55 above the feet) touches or overlaps the target tile. **/
	function touchesTarget(player:LocalPlayerController):Bool {
		var t = ClipSimulator.TILE;
		var left = settings.targetTileX * t - 1, top = settings.targetTileY * t - 1;
		var right = left + t + 2, bottom = top + t + 2;
		var half = LocalPlayerController.STANDING_WIDTH / 2;
		return player.x + half > left && player.x - half < right && player.y > top && player.y - LocalPlayerController.STANDING_HEIGHT < bottom;
	}

	/** The moves tried from a spot. **/
	function movesFrom(spot:RouteSpot):Array<RouteMove> {
		var moves:Array<RouteMove> = [];
		for (dir in [1, -1]) {
			var side = dir == 1 ? "right" : "left";
			if (settings.normalMoves) {
				for (frames in [3, 6, 10, 16, 25, 40]) moves.push(new RouteMove('walk $side $frames', hold(dir, frames, 0, 0, false)));
				for (hop in [3, 8, 30]) for (run in [8, 16, 30, 60]) {
					moves.push(new RouteMove('jump $side (hold $hop, run $run)', hold(dir, run, 0, hop, false)));
				}
				// Only one super jump straight up: it is the same for both directions.
				for (run in (dir == 1 ? [0, 15, 60] : [15, 60])) {
					var inputs = [for (_ in 0...ClipAttempt.MAX_SUPER_CHARGE) new LocalPlayerInput(false, false, false, true)];
					inputs = inputs.concat(hold(dir, run, 0, 0, false));
					moves.push(new RouteMove(run == 0 ? 'super jump' : 'super jump $side (run $run)', inputs));
				}
			}
			var corner = cornerAhead(spot, dir);
			if (corner != null) {
				moves.push(new RouteMove('clip through the wall at ${corner.wallTileX},${corner.y}', [], corner));
			}
		}
		if (settings.normalMoves) moves.push(new RouteMove("jump in place", hold(0, 30, 0, 30, false)));
		return moves.concat(mineMoves(spot));
	}

	/**
		Moves that use a mine's knockback, at the nearest mines to the spot: walk
		to a set gap from the mine and stop, then walk, hop or jump into it; jump
		up into a mine overhead; or step onto a mine in the floor. Where the
		player touches the mine sets the blast angle, so the gaps and jumps give
		different launches.
	**/
	function mineMoves(spot:RouteSpot):Array<RouteMove> {
		var t = ClipSimulator.TILE;
		var half = LocalPlayerController.STANDING_WIDTH / 2;
		var near = [for (mine in mines) {
			var dx = mine.x - spot.tileX;
			var dy = mine.y - spot.tileY;
			// From the floor under the spot (dy = 1) up to three tiles above the head.
			if (Math.abs(dx) <= settings.mineRange && dy <= 1 && dy >= -4) mine;
		}];
		near.sort((a, b) -> Reflect.compare(Math.abs(a.x - spot.tileX) + Math.abs(a.y - spot.tileY), Math.abs(b.x - spot.tileX) + Math.abs(b.y - spot.tileY)));
		var moves:Array<RouteMove> = [];
		for (i in 0...Std.int(Math.min(near.length, settings.minesPerSpot))) {
			var mine = near[i];
			var name = 'mine at ${mine.x},${mine.y}';
			var centerX = (mine.x + 0.5) * t;
			var dy = mine.y - spot.tileY;
			var sides = mine.x > spot.tileX ? [1] : (mine.x < spot.tileX ? [-1] : [1, -1]);
			if (dy <= -2) {
				// Overhead: stand under it and jump up into it (blast pushes down and away).
				for (offset in [0.0, 12.0]) {
					moves.push(new RouteMove('$name: jump up into it (${offset == 0 ? "centre" : "off-centre"})', hold(0, 30, 0, 30, false), null,
						centerX - offset));
				}
				continue;
			}
			for (dir in sides) {
				// The mine's face on the near side; the player stops `gap` px short of it.
				var face = dir == 1 ? mine.x * t : (mine.x + 1) * t;
				if (dy == 1) {
					// In the floor: the blast throws the player up. Step onto it, or run
					// across it from further back and keep holding the direction in the
					// air, so the launch also carries sideways.
					for (gap in [4, 60]) {
						var x = face - dir * (half + gap);
						moves.push(new RouteMove('$name: step onto it from ${gap}px', hold(dir, 20 + gap, 0, 0, false), null, x));
						moves.push(new RouteMove('$name: run across it from ${gap}px', hold(dir, 90, 0, 0, false), null, x));
					}
					continue;
				}
				for (gap in [2, 40]) {
					var x = face - dir * (half + gap);
					moves.push(new RouteMove('$name: walk at it from ${gap}px', hold(dir, 30, 0, 0, false), null, x));
					moves.push(new RouteMove('$name: hop at it from ${gap}px', hold(dir, 30, 0, 3, false), null, x));
					moves.push(new RouteMove('$name: jump at it from ${gap}px', hold(dir, 30, 0, 30, false), null, x));
				}
			}
		}
		return moves;
	}

	/** A mine move: walk to its pixel and stop, then play its inputs live (recorded into the route). **/
	function tryApproachMove(spot:RouteSpot, move:RouteMove):Void {
		var inputs = move.inputs;
		var sim = simulate(spot.script, spot.script.length, false, () -> walkThen(move.approachX, MINE_APPROACH_TOLERANCE, inputs.length, (i, _) -> inputs[i]));
		if (sim.policyFailed) return;
		finishMove(spot, move.name, spot.script.concat(sim.policyInputs), sim);
	}

	/**
		Holds `dir` (0 = none) for `frames` frames; jump from `jumpFrame` for
		`jumpHold` frames (0 = no jump); with `fastFall`, down after the jump.
	**/
	static function hold(dir:Int, frames:Int, jumpFrame:Int, jumpHold:Int, fastFall:Bool):Array<LocalPlayerInput> {
		var length = Std.int(Math.max(frames, jumpFrame + jumpHold));
		return [for (f in 0...length) {
			var jumping = jumpHold > 0 && f >= jumpFrame && f < jumpFrame + jumpHold;
			var down = fastFall && f >= jumpFrame + jumpHold;
			new LocalPlayerInput(dir == -1 && f < frames, dir == 1 && f < frames, jumping, down);
		}];
	}

	/** The nearest inside corner facing `dir` on the spot's own row, within `clipWallRange` tiles. **/
	function cornerAhead(spot:RouteSpot, dir:Int):Null<ClipCorner> {
		var best:Null<ClipCorner> = null;
		for (corner in corners) {
			if (corner.dir != dir || corner.y != spot.tileY) continue;
			var ahead = dir * (corner.x - spot.tileX);
			if (ahead < 0 || ahead > settings.clipWallRange) continue;
			if (best == null || dir * (corner.x - best.x) < 0) best = corner;
		}
		return best;
	}

	// ---- Clips: recipes per wall, then walk to the exact pixel and run it --------

	/** Per corner: the scanned recipe (start x + launch) that clips it with these stats, or null. **/
	final recipes:Map<String, Null<ClipAttempt>> = new Map();
	/** A corner being scanned for its recipe (spread over `step` calls). **/
	var recipeScan:Null<ClipScanner> = null;
	var recipeKey:String = "";
	final corners:Array<ClipCorner>;

	static inline function cornerKey(corner:ClipCorner):String return corner.x + "," + corner.y + "," + corner.dir;

	/** Advances a pending recipe scan by one attempt. Returns true while one is running. **/
	function stepRecipeScan():Bool {
		var scan = recipeScan;
		if (scan == null) return false;
		scan.step(1);
		if (scan.done) {
			recipes.set(recipeKey, scan.portals.length > 0 ? scan.portals[0].attempt : null);
			recipeScan = null;
		}
		return true;
	}

	/**
		A clip move: walk to the recipe's exact start pixel and stop dead, then
		play the recipe (whose fast-fall depends on being airborne, so it runs
		live and is recorded). Returns false when the move must wait for the
		recipe scan, true when it was tried (or there is no recipe).
	**/
	function tryClipMove(spot:RouteSpot, move:RouteMove):Bool {
		var corner = move.corner;
		var key = cornerKey(corner);
		if (!recipes.exists(key)) {
			var scanSettings = new ClipScanSettings(settings.speed, settings.accel, settings.jump, settings.gravity);
			scanSettings.hats = settings.hats;
			scanSettings.passThroughOnly = true;
			if (settings.recipeDistances != null) scanSettings.distances = settings.recipeDistances;
			if (settings.recipeJumpHolds != null) scanSettings.jumpHolds = settings.recipeJumpHolds;
			if (settings.recipeSuperCharges != null) scanSettings.superCharges = settings.recipeSuperCharges;
			recipeScan = new ClipScanner(blocksForScans, scanSettings, corner);
			recipeKey = key;
			return false;
		}
		var recipe = recipes.get(key);
		if (recipe == null) return true;
		var sim = simulate(spot.script, spot.script.length, false, () -> walkThenRecipe(recipe));
		if (sim.policyFailed) return true;
		finishMove(spot, move.name, spot.script.concat(sim.policyInputs), sim);
		return true;
	}

	/** Walk to the recipe's start x and stop, then play the recipe until the keys are let go after the clip. **/
	static function walkThenRecipe(recipe:ClipAttempt):RoutePolicy {
		var length = recipe.releaseFrame >= 0 ? recipe.releaseFrame : recipe.frames;
		return walkThen(recipe.startX, 0.5, length, recipe.inputAt);
	}

	/**
		Live controller: walk toward `targetX`, brake, then nudge with short taps
		until standing exactly there; then play `length` frames of `inputAt`
		(frame, grounded). Returns null when they are over, or ABORT when the
		walk goes wrong: it leaves the floor it started on (a fall, or a mine
		on the way) or takes too long.
	**/
	static function walkThen(targetX:Float, tolerance:Float, length:Int, inputAt:(Int, Bool) -> LocalPlayerInput):RoutePolicy {
		var launching = false;
		var launchFrame = 0;
		var tap = 0;
		var tapDir = 0;
		var still = 0;
		var floorY:Null<Float> = null;
		return function(frame:Int, player:LocalPlayerController):Null<LocalPlayerInput> {
			if (launching) {
				var i = frame - launchFrame;
				return i < length ? inputAt(i, player.grounded) : null;
			}
			if (floorY == null) floorY = player.y;
			if (frame > MAX_APPROACH_FRAMES || (player.grounded && Math.abs(player.y - floorY) > 2)) return ABORT;
			var err = targetX - player.x;
			var dir = err > 0 ? 1 : -1;
			var moving = Math.abs(player.vx) > 0.02 || !player.grounded;
			if (tap > 0) {
				tap--;
				return new LocalPlayerInput(tapDir == -1, tapDir == 1, false, false);
			}
			if (moving) {
				// Keep walking while far; let go early enough to coast to a stop.
				var coast = Math.abs(player.vx) * 3 + 2;
				var walkOn = Math.abs(err) > coast && (player.vx == 0 || (player.vx > 0) == (dir > 0));
				still = 0;
				return walkOn ? new LocalPlayerInput(dir == -1, dir == 1, false, false) : new LocalPlayerInput();
			}
			if (Math.abs(err) < tolerance) {
				// Stopped on the pixel: a few still frames, then go.
				if (++still >= 3) {
					launching = true;
					launchFrame = frame + 1;
				}
				return new LocalPlayerInput();
			}
			still = 0;
			if (Math.abs(err) > 30) return new LocalPlayerInput(dir == -1, dir == 1, false, false);
			// Close and stopped: a short tap toward the pixel, longer the further away.
			var a = Math.abs(err);
			tap = a <= 1 ? 1 : (a <= 3 ? 2 : (a <= 6 ? 3 : (a <= 12 ? 4 : 6)));
			tapDir = dir;
			tap--;
			return new LocalPlayerInput(tapDir == -1, tapDir == 1, false, false);
		};
	}

	/** The found route's recording (for the ghost), from the start to the frame the target is reached. **/
	public function recordRoute():Null<RouteSim> {
		var found = route;
		if (found == null) return null;
		return simulate(found.script, 0, true);
	}

	/**
		The found route as a clip (its script as the attempt's inputs, with the
		recorded run), so the ghost plays it and "Replay on me" runs it.
	**/
	public function foundClip():Null<ClipFinder.FoundClip> {
		var found = route;
		var sim = recordRoute();
		if (found == null || sim == null) return null;
		var s = settings;
		var attempt = new ClipAttempt(s.startX, s.startY, s.speed, s.accel, s.jump, s.gravity, 1, 0, 0, false, found.script.length);
		attempt.script = found.script;
		attempt.hats = s.hats;
		var ghost = sim.ghost;
		var clipFrame = -1;
		if (ghost != null) {
			// ghost[i] is the pose after frame i - 1.
			for (i in 1...ghost.length) if (ghost[i].inSolid) {
				clipFrame = i - 1;
				break;
			}
		}
		var last = ghost == null || ghost.length == 0 ? null : ghost[ghost.length - 1];
		var run = new ClipRun(clipFrame, last == null ? s.startX : last.x, last == null ? s.startY : last.y, 0, 0, ghost);
		return new ClipFinder.FoundClip(attempt, run);
	}

	/** The steps of the found route, one per line, for the panel. **/
	public function describeRoute():String {
		var found = route;
		if (found == null) return "";
		var clipText = found.clips == 0 ? "no clips" : '${found.clips} clip${found.clips == 1 ? "" : "s"}';
		return '${found.steps.length} steps, $clipText, ${found.reachFrame + 1} frames: ' + found.steps.join("; ");
	}
}

typedef RoutePolicy = Int->LocalPlayerController->Null<LocalPlayerInput>;
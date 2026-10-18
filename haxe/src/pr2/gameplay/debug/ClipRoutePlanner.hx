package pr2.gameplay.debug;

import pr2.gameplay.debug.ClipSimulator.ClipArea;
import pr2.gameplay.debug.ClipSimulator.ClipAttempt;
import pr2.gameplay.debug.ClipSimulator.ClipHats;
import pr2.gameplay.debug.ClipSimulator.ClipItems;
import pr2.gameplay.debug.ClipSimulator.ClipRun;
import pr2.gameplay.debug.ClipSimulator.GhostFrame;
import pr2.gameplay.debug.ClipScanner.ClipCorner;
import pr2.gameplay.debug.ClipScanner.ClipScanSettings;
import pr2.gameplay.player.LocalPlayerController;
import pr2.gameplay.player.LocalPlayerInput;
import pr2.level.BlockType;
import pr2.gameplay.BlockController;
import pr2.gameplay.Items;
import pr2.level.Level;
import pr2.level.Level.LevelBlock;

class RouteSettings {
	public var startX:Float;
	public var startY:Float;
	public var speed:Float;
	public var accel:Float;
	public var jump:Float;
	public var gravity:Float;
	public var hats:Null<ClipHats> = null;
	/** The item the player starts with and the level's allowed items (null = none / every item). **/
	public var items:Null<ClipItems> = null;
	/** The block to reach: touch it, stand on it, or end up inside it. **/
	public var targetTileX:Int;
	public var targetTileY:Int;
	/** Most steps (moves) in a route. **/
	public var maxSteps:Int = 200;
	/** Most standing spots explored before giving up. **/
	public var maxSpots:Int = 5000;
	/**
		How strongly the search heads for the target: a spot's priority is its
		cost plus this times its distance to the target (through open tiles) in moves (about 4 tiles
		a move). 0 searches evenly in every direction; above 1 it trades the
		cheapest route for finding one sooner in big levels.
	**/
	public var targetPull:Float = 1.5;
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
	/** Laser recoil attempts tried for a recipe (null = the scanner's defaults). **/
	public var recipeLaserHolds:Null<Array<Int>> = null;
	public var recipeLaserFireFrames:Null<Array<Int>> = null;
	public var recipeLaserGaps:Null<Array<Float>> = null;

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
	/** The feet, in the level's own space. **/
	public final x:Float;
	public final y:Float;
	public final steps:Array<String>;
	public final clips:Int;
	public final cost:Int;
	/** The state the spot was reached in (`RouteSim` at rest): tile, rotation, mines gone, item, water. **/
	public final state:RouteSim;

	public function new(script:Array<LocalPlayerInput>, steps:Array<String>, clips:Int, cost:Int, state:RouteSim) {
		this.script = script;
		this.x = state.restX;
		this.y = state.restY;
		this.steps = steps;
		this.clips = clips;
		this.cost = cost;
		this.state = state;
	}

	/** Order in the search: cost so far plus the pull toward the target. **/
	public var priority:Float = 0;

	/** One spot per tile, course rotation and item held. **/
	public var key(get, never):String;
	inline function get_key():String return state.restKey();

	/** The tile the player stands in (level space). **/
	public var tileX(get, never):Int;
	inline function get_tileX():Int return state.restTileX;

	public var tileY(get, never):Int;
	inline function get_tileY():Int return state.restTileY;

	/** The course's rotation here (rotate blocks turn it by 90). **/
	public var rotation(get, never):Int;
	inline function get_rotation():Int return state.restRotation;

	public var item(get, never):Null<Int>;
	inline function get_item():Null<Int> return state.restItem;

	public var inWater(get, never):Bool;
	inline function get_inWater():Bool return state.restInWater;

	/** Mines blown up on the way here (they don't come back, so they change what the next moves do). **/
	public var minesGone(get, never):Int;
	inline function get_minesGone():Int return state.minesHit;
}

/** A found route: the input script from the start to the frame the target is reached. **/
class Route {
	public final script:Array<LocalPlayerInput>;
	public final steps:Array<String>;
	public final clips:Int;
	/** Frame (index into `script`) the player reaches the target. **/
	public final reachFrame:Int;
	/** Items the route takes from item blocks (which roll at random in the game). **/
	public final picks:Array<ItemPick>;

	public function new(script:Array<LocalPlayerInput>, steps:Array<String>, clips:Int, reachFrame:Int, ?picks:Array<ItemPick>) {
		this.script = script;
		this.steps = steps;
		this.clips = clips;
		this.reachFrame = reachFrame;
		this.picks = picks == null ? [] : picks;
	}
}

/** The item an item block gives on a frame of the route (the game rolls it; the route chooses it). **/
class ItemPick {
	public final frame:Int;
	public final item:Int;

	public function new(frame:Int, item:Int) {
		this.frame = frame;
		this.item = item;
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
	/** Where it ended, in the level's own space: the tile the player stands in and the course rotation. **/
	public var restTileX:Int = 0;
	public var restTileY:Int = 0;
	public var restRotation:Int = 0;
	/** The item held at the end, and the item held when the move started. **/
	public var restItem:Null<Int> = null;
	public var itemAtCheck:Null<Int> = null;
	/** Ended in water (swim moves apply). **/
	public var restInWater:Bool = false;
	/** Rotate blocks hit by this move. **/
	public var rotationsByMove:Int = 0;
	/** Item picks in force for this run (from the start). **/
	public var picks:Array<ItemPick> = [];
	/** Frame this move took an item from a block (-1 = none), the item, and where. **/
	public var gainFrame:Int = -1;
	public var gainItem:Int = 0;
	public var gainX:Float = 0;
	public var gainY:Float = 0;

	public function new() {}

	/**
		One spot per tile, course rotation and item. Mines blown up on the way
		aren't part of it: levels with hundreds of mines would otherwise keep a
		copy of every tile per count (the first, cheapest way there is kept).
	**/
	public function restKey():String {
		return restTileX + "," + restTileY + "," + restRotation + "," + (restItem == null ? "-" : Std.string(restItem));
	}

	/** What the move changed, for its step name: mines, item, course rotation. **/
	public function effects():String {
		var parts:Array<String> = [];
		if (minesHitByMove > 0) parts.push(minesHitByMove == 1 ? "hits a mine" : 'hits $minesHitByMove mines');
		if (restItem != itemAtCheck) {
			var gained = restItem;
			parts.push(gained == null ? "uses up the item" : 'gets ${Items.getNameFromCode(gained)}');
		}
		if (rotationsByMove > 0) parts.push(rotationsByMove == 1 ? "turns the course" : 'turns the course $rotationsByMove times');
		return parts.length == 0 ? "" : " (" + parts.join(", ") + ")";
	}
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
	the knockback can launch the player somewhere, even into a clip.

	Rotate blocks turn the whole course; positions are followed in the
	level's own space, so a route may turn the course (and turn it back) and
	the spot is kept per rotation too. Items: the player starts with the item
	they hold, item blocks give items (rolled from a fixed seed so replays
	match; the real game rolls at random), and a spot holding an item tries
	using it (tap, while running, mid-jump, held for the jetpack). Water: 10 frames
	swimming count as a spot (a pool may have no bottom), and swim moves are tried from spots
	in water. Vanish blocks: a player on a fading vanish block is not at rest
	(it drops through), and next to one the planner tries touching it,
	waiting for it to fade, then going through. After a move the keys are
	released until the player is at rest; that spot is where the next move
	starts. Spots are searched by cost (a step through a block costs
	`clipCost`) plus a pull toward the target (`targetPull`, weighted A*), so
	the search heads for far targets instead of filling the whole level; one
	spot per tile, course rotation and item. Like the other searches it works a few
	simulations at a time (`step`).
**/
@:access(pr2.gameplay.player.LocalPlayerController)
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
	/** How close counts when the exact pixel can't be reached (pressed against a wall). **/
	static inline var WALL_TOLERANCE:Float = 1.5;
	/** A live controller returns this to give the move up (it could not get where it needed to be). **/
	static final ABORT:LocalPlayerInput = new LocalPlayerInput();

	public final settings:RouteSettings;
	public var route(default, null):Null<Route> = null;
	public var spotsExplored(default, null):Int = 0;
	public var simulations(default, null):Int = 0;
	/** Why moves were dropped (for the "no route" status): sent back to a safe spot or off the map, never came to rest, ended inside a block, came to rest on a spot already found, couldn't walk to its starting pixel. **/
	public var rejectedRespawn(default, null):Int = 0;
	public var rejectedNoRest(default, null):Int = 0;
	public var rejectedInSolid(default, null):Int = 0;
	public var rejectedRevisit(default, null):Int = 0;
	public var rejectedApproach(default, null):Int = 0;

	/** One line on why the search ran out, for the status text. **/
	public function rejectionSummary():String {
		var parts:Array<String> = [];
		if (rejectedRevisit > 0) parts.push('$rejectedRevisit back to known spots');
		if (rejectedNoRest > 0) parts.push('$rejectedNoRest never settled');
		if (rejectedRespawn > 0) parts.push('$rejectedRespawn sent back/fell out');
		if (rejectedInSolid > 0) parts.push('$rejectedInSolid stuck in blocks');
		if (rejectedApproach > 0) parts.push('$rejectedApproach could not line up');
		return parts.join(", ");
	}

	/** True once a route is found or every reachable spot (within the limits) is explored. **/
	public var done(default, null):Bool = false;

	final area:ClipArea;
	/** Distance to the target through the level's open tiles (guides the search around walls). **/
	final field:TargetField;
	/** Every mine in the level (tile positions). **/
	final mines:Array<LevelBlock>;
	/** Every vanish block in the level. **/
	final vanishes:Array<LevelBlock>;
	/** Every item block (for the items each can give). **/
	final itemBlocks:Array<LevelBlock>;
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
		vanishes = [for (block in blocks) if (!block.isMarker() && block.type == BlockType.Vanish) block];
		itemBlocks = [for (block in blocks) if (block.type == BlockType.Item || block.type == BlockType.InfiniteItem) block];
		field = new TargetField(blocks, settings.targetTileX, settings.targetTileY);
		area = ClipArea.around(blocks, settings.startX, settings.startY, ClipFinder.AREA_RADIUS_X, ClipFinder.AREA_UP, ClipFinder.AREA_DOWN);
		// The start itself: simulate standing still, in case the target is already touched.
		var start = simulate([], 0, false);
		if (start.reachFrame >= 0) {
			route = new Route([], ["already touching the block"], 0, 0);
			done = true;
			return;
		}
		insert(new RouteSpot([for (_ in 0...start.idleFrames) new LocalPlayerInput()], [], 0, 0, start));
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
		runMove(spot, move.name, picks -> simulate(script, spot.script.length, false, null, true, picks), _ -> script);
	}

	/**
		Simulates a move and records it; if it took an item from a block, also
		tries it with each other useful item that block could give (the game
		rolls it at random), so a route can count on the one it needs.
	**/
	function runMove(spot:RouteSpot, name:String, run:Array<ItemPick>->RouteSim, scriptOf:RouteSim->Array<LocalPlayerInput>):Void {
		var sim = run(spot.state.picks);
		if (sim.policyFailed) {
			rejectedApproach++;
			return;
		}
		finishMove(spot, name, scriptOf(sim), sim);
		if (done || sim.gainFrame < 0) return;
		for (item in otherItems(sim)) {
			var other = run(spot.state.picks.concat([new ItemPick(sim.gainFrame, item)]));
			if (other.policyFailed) continue;
			finishMove(spot, name, scriptOf(other), other);
			if (done) return;
		}
	}

	/** Items that help movement (laser, teleport, super jump, jetpack, speed burst, sword). **/
	static final MOVEMENT_ITEMS:Array<Int> = [1, 4, 5, 6, 7, 8];

	/** The other movement items the block the move took an item from could have given. **/
	function otherItems(sim:RouteSim):Array<Int> {
		var allowed = settings.items != null && settings.items.allowedItems != null ? settings.items.allowedItems : Items.getAllCodes();
		var block:Null<LevelBlock> = null;
		var best = Math.POSITIVE_INFINITY;
		var t = ClipSimulator.TILE;
		for (b in itemBlocks) {
			var dx = (b.x + 0.5) * t - sim.gainX, dy = (b.y + 0.5) * t - sim.gainY;
			var d = dx * dx + dy * dy;
			if (d < best) {
				best = d;
				block = b;
			}
		}
		var candidates = allowed;
		if (block != null && best < (3 * t) * (3 * t) && block.options != "") {
			candidates = block.options == "none" ? [] : [for (id in block.options.split("-")) if (Std.parseInt(id) != null) Std.parseInt(id)];
		}
		return [for (item in MOVEMENT_ITEMS) if (item != sim.gainItem && candidates.indexOf(item) >= 0) item];
	}

	/** Records what a move did: the route if it reached the target, else the spot it came to rest on. **/
	function finishMove(spot:RouteSpot, name:String, script:Array<LocalPlayerInput>, sim:RouteSim):Void {
		var clipped = sim.clipped;
		var stepName = name + sim.effects() + (clipped ? " (through a block)" : "");
		var clips = spot.clips + (clipped ? 1 : 0);
		var cost = spot.cost + (clipped ? settings.clipCost : 1);
		if (sim.reachFrame >= 0) {
			// Reached while letting go after the move: the idle frames are part of the route.
			var reached = script.slice(0, sim.reachFrame + 1);
			while (reached.length <= sim.reachFrame) reached.push(new LocalPlayerInput());
			route = new Route(reached, spot.steps.concat([stepName]), clips, sim.reachFrame, sim.picks);
			done = true;
			return;
		}
		if (sim.respawned) {
			rejectedRespawn++;
			return;
		}
		if (!sim.atRest) {
			rejectedNoRest++;
			return;
		}
		if (sim.endInSolid) {
			rejectedInSolid++;
			return;
		}
		var key = sim.restKey();
		if (visited.exists(key)) {
			rejectedRevisit++;
			return;
		}
		var rested = script.concat([for (_ in 0...sim.idleFrames) new LocalPlayerInput()]);
		var landed = ' to ${sim.restTileX},${sim.restTileY}' + (sim.restInWater ? " (in water)" : "");
		insert(new RouteSpot(rested, spot.steps.concat([stepName + landed]), clips, cost, sim));
	}

	/** About how many tiles one move covers, for the distance part of a spot's priority. **/
	static inline var TILES_PER_MOVE:Float = 4;

	/**
		Keeps `open` sorted by priority (then fewer steps), so the most
		promising spot is expanded next: cost so far plus `targetPull` times
		the moves still needed at about 4 tiles a move (weighted A*).
	**/
	function insert(spot:RouteSpot):Void {
		spot.priority = spot.cost + settings.targetPull * field.distance(spot.tileX, spot.tileY) / TILES_PER_MOVE;
		var i = open.length;
		while (i > 0 && (open[i - 1].priority > spot.priority || (open[i - 1].priority == spot.priority && open[i - 1].steps.length > spot.steps.length))) i--;
		open.insert(i, spot);
	}

	/**
		Replays `script` from the start, then (with `makePolicy`) lets a live
		controller choose each frame's input until it returns null, then lets go
		until the player is at rest. The target counts as reached on any frame
		from `checkFrom` on. The controller's inputs are returned in
		`policyInputs`, so the route script reproduces the run exactly.
	**/
	public function simulate(script:Array<LocalPlayerInput>, checkFrom:Int, record:Bool, ?makePolicy:Void->RoutePolicy, fromSpot:Bool = false,
			?picks:Array<ItemPick>):RouteSim {
		simulations++;
		if (picks == null) picks = [];
		while (true) {
			// A move from the spot being expanded starts from a copy of the player
			// standing there, instead of replaying the whole route from the start.
			var from = fromSpot && !record ? spotBase(script, checkFrom) : null;
			var sim = simulateOnce(script, checkFrom, record, makePolicy == null ? null : makePolicy(), from, picks);
			if (sim != null) return sim;
			// The area grew: copies of the old area are stale.
			base = null;
		}
	}

	/** The player standing on the spot being expanded (built once per spot by replaying its script). **/
	var base:Null<SpotBase> = null;

	function spotBase(script:Array<LocalPlayerInput>, frames:Int):Null<SpotBase> {
		var b = base;
		if (b != null && b.frame == frames && b.script == current) return b;
		while (true) {
			var s = settings;
			var level = area.buildLevel(s.gravity);
			var player = ClipSimulator.preparePlayer(area, level, s.startX, s.startY, s.speed, s.accel, s.jump, s.gravity, s.hats, s.items);
			var minesAtStart = countMines(level);
			var grew = false;
			var spotPicks = current == null ? [] : current.state.picks;
			for (frame in 0...frames) {
				player.step(script[frame]);
				applyPick(spotPicks, frame, player);
				var feet = ClipSimulator.toLevel(player.x, player.y, player.courseRotation);
				if (!area.containsPixel(feet.x, feet.y)) {
					if (area.growToInclude(feet.x, feet.y)) {
						grew = true;
						break;
					}
				}
			}
			if (grew) continue;
			base = new SpotBase(player, frames, minesAtStart, current, ClipSimulator.itemUses());
			return base;
		}
	}

	/** Gives the player the route's chosen item on the frame an item block gave one. Returns true if it did. **/
	static function applyPick(picks:Array<ItemPick>, frame:Int, player:LocalPlayerController):Bool {
		for (pick in picks) {
			if (pick.frame == frame) {
				if (player.itemId != pick.item) player.grantItemForDebug(pick.item);
				return true;
			}
		}
		return false;
	}

	function simulateOnce(script:Array<LocalPlayerInput>, checkFrom:Int, record:Bool, policy:Null<RoutePolicy>, ?from:SpotBase,
			?picks:Array<ItemPick>):Null<RouteSim> {
		if (picks == null) picks = [];
		var s = settings;
		var player:LocalPlayerController;
		var frame = 0;
		var minesAtStart:Int;
		if (from != null) {
			player = ClipSimulator.ClipSnapshot.copy(from.player);
			ClipSimulator.setItemUses(from.itemUses);
			frame = from.frame;
			minesAtStart = from.minesAtStart;
		} else {
			player = ClipSimulator.preparePlayer(area, area.buildLevel(s.gravity), s.startX, s.startY, s.speed, s.accel, s.jump, s.gravity, s.hats,
				s.items);
			minesAtStart = -1;
		}
		var level = player.level;
		var sim = new RouteSim();
		if (record) sim.ghost = [GhostFrame.capture(player, ClipSimulator.bodyInSolid(level, player))];
		// Positions are compared in the level's own space, which stays continuous when a rotate block turns the course.
		var feet = ClipSimulator.toLevel(player.x, player.y, player.courseRotation);
		var prevX = feet.x, prevY = feet.y;
		var settled = 0;
		var policyFrame = 0;
		var policyDone = policy == null;
		// Blown-up mines leave the level's block list, so counting them tells how many were hit.
		if (minesAtStart < 0) minesAtStart = countMines(level);
		var minesAtCheck = minesAtStart;
		sim.itemAtCheck = player.itemId;
		var rotationAtCheck = player.courseRotation;
		var lastRotation = player.courseRotation;
		var settleLimit = SETTLE_FRAMES;
		var swimming = 0;
		var onGround = 0;
		while (true) {
			if (frame == checkFrom) {
				minesAtCheck = countMines(level);
				sim.itemAtCheck = player.itemId;
				rotationAtCheck = player.courseRotation;
				sim.rotationsByMove = 0;
			}
			if (frame >= script.length + MAX_POLICY_FRAMES + settleLimit) break;
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
			var itemBefore = player.itemId;
			player.step(input);
			var picked = applyPick(picks, frame, player);
			// An item from a block during this move: remember when and where, so other items it could give can be tried.
			if (!picked && frame >= checkFrom && player.itemId != null && player.itemId != itemBefore && sim.gainFrame < 0) {
				sim.gainFrame = frame;
				sim.gainItem = player.itemId;
				var at = ClipSimulator.toLevel(player.x, player.y - 27, player.courseRotation);
				sim.gainX = at.x;
				sim.gainY = at.y;
			}
			var inSolid = ClipSimulator.bodyInSolid(level, player);
			if (sim.ghost != null) sim.ghost.push(GhostFrame.capture(player, inSolid));
			feet = ClipSimulator.toLevel(player.x, player.y, player.courseRotation);
			if (!area.containsPixel(feet.x, feet.y)) {
				if (area.growToInclude(feet.x, feet.y)) return null;
				sim.respawned = true;
				break;
			}
			// A big jump is the game sending the player back to its last safe spot,
			// unless it landed somewhere else: a teleport block or the Teleport item.
			if ((Math.abs(feet.x - prevX) > RESPAWN_JUMP || Math.abs(feet.y - prevY) > RESPAWN_JUMP)
					&& player.x == player.lastSafeX && player.y == player.lastSafeY) {
				sim.respawned = true;
				break;
			}
			prevX = feet.x;
			prevY = feet.y;
			if (player.courseRotation != lastRotation) {
				lastRotation = player.courseRotation;
				if (frame >= checkFrom) sim.rotationsByMove++;
			}
			if (frame >= checkFrom) {
				if (inSolid) sim.clipped = true;
				if (touchesTarget(player)) {
					sim.reachFrame = frame;
					break;
				}
			}
			if (idle) {
				sim.idleFrames++;
				var floor = player.grounded ? floorType(level, player) : null;
				// Arrow blocks keep pushing and ice keeps sliding, so a player riding them
				// never stops: standing on them counts as a spot (so does a long time on the ground).
				var riding = floor != null && isConveyorOrIce(floor);
				var still = player.grounded && Math.abs(player.vy) < 1 && (Math.abs(player.vx) < 0.5 || riding);
				// Standing on a vanish block isn't rest: it fades and drops the player.
				if (still && floor == BlockType.Vanish && onFadingFloor(level, player)) still = false;
				settled = still ? settled + 1 : 0;
				onGround = player.grounded && floor != BlockType.Vanish ? onGround + 1 : 0;
				if (onGround >= LONG_GROUNDED) settled = 10;
				// Swimming counts as a spot too: water is slow and fully steerable, and a
				// pool may have no bottom to sink to (the player would drop out of it).
				swimming = player.mode == LocalPlayerController.MODE_WATER ? swimming + 1 : 0;
				if (settled >= 10 || swimming >= 10) {
					sim.atRest = true;
					break;
				}
			}
			frame++;
		}
		sim.restX = feet.x;
		sim.restY = feet.y;
		sim.restRotation = player.courseRotation;
		// The tile the player stands in: just above the feet, along the course's own "up".
		var standing = ClipSimulator.toLevel(player.x, player.y - 1, player.courseRotation);
		sim.restTileX = ClipSimulator.tileOf(standing.x);
		sim.restTileY = ClipSimulator.tileOf(standing.y);
		sim.restItem = player.itemId;
		sim.picks = picks;
		sim.restInWater = inWater(level, player);
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

	/**
		The player's box (20 x 55 above the feet, along the course's "up", which
		a rotate block turns) touches or overlaps the target tile.
	**/
	function touchesTarget(player:LocalPlayerController):Bool {
		var t = ClipSimulator.TILE;
		var half = LocalPlayerController.STANDING_WIDTH / 2;
		var r = player.courseRotation;
		var a = ClipSimulator.toLevel(player.x - half, player.y, r);
		var b = ClipSimulator.toLevel(player.x + half, player.y - LocalPlayerController.STANDING_HEIGHT, r);
		var minX = Math.min(a.x, b.x), maxX = Math.max(a.x, b.x);
		var minY = Math.min(a.y, b.y), maxY = Math.max(a.y, b.y);
		// Overlap with the tile itself along each axis (negative = a gap). A face
		// counts (standing on it, against it, or under it): the box shares at
		// least 5 px of that face and is within 1 px of it. A corner graze doesn't.
		var tileLeft = settings.targetTileX * t, tileTop = settings.targetTileY * t;
		var overlapX = Math.min(maxX, tileLeft + t) - Math.max(minX, tileLeft);
		var overlapY = Math.min(maxY, tileTop + t) - Math.max(minY, tileTop);
		return (overlapX >= TOUCH_FACE && overlapY >= -1) || (overlapY >= TOUCH_FACE && overlapX >= -1);
	}

	/** Px of a target face the player's box must share to count as touching it. **/
	static inline var TOUCH_FACE:Float = 5;

	/** Frames on the ground (any floor) that count as a spot even while still moving. **/
	static inline var LONG_GROUNDED:Int = 45;

	/** The type of the block under the feet (along the course's "down"), or null. **/
	static function floorType(level:Level, player:LocalPlayerController):Null<BlockType> {
		var below = ClipSimulator.toLevel(player.x, player.y + 1, player.courseRotation);
		var block = level.blockAt(ClipSimulator.tileOf(below.x), ClipSimulator.tileOf(below.y));
		return block == null || player.blockController.isBlockRemoved(block) ? null : block.type;
	}

	static function isConveyorOrIce(type:BlockType):Bool {
		return switch (type) {
			case BlockType.ArrowLeft | BlockType.ArrowRight | BlockType.ArrowUp | BlockType.ArrowDown | BlockType.Ice: true;
			default: false;
		}
	}

	/** The block under the feet (along the course's "down") is a vanish block that hasn't gone yet. **/
	static function onFadingFloor(level:Level, player:LocalPlayerController):Bool {
		var below = ClipSimulator.toLevel(player.x, player.y + 1, player.courseRotation);
		var block = level.blockAt(ClipSimulator.tileOf(below.x), ClipSimulator.tileOf(below.y));
		return block != null && block.type == BlockType.Vanish && !player.blockController.isBlockRemoved(block);
	}

	/** The player's body (or feet) is in a water block. **/
	static function inWater(level:Level, player:LocalPlayerController):Bool {
		if (player.mode == LocalPlayerController.MODE_WATER) return true;
		for (up in [5.0, 25.0]) {
			var p = ClipSimulator.toLevel(player.x, player.y - up, player.courseRotation);
			var block = level.blockAt(ClipSimulator.tileOf(p.x), ClipSimulator.tileOf(p.y));
			if (block != null && block.type == BlockType.Water) return true;
		}
		return false;
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
			// Clip and mine moves aim at level positions, so they run on an upright course.
			var corner = spot.rotation == 0 ? cornerAhead(spot, dir) : null;
			if (corner != null) {
				moves.push(new RouteMove('clip through the wall at ${corner.wallTileX},${corner.y}', [], corner));
			}
		}
		if (settings.normalMoves) moves.push(new RouteMove("jump in place", hold(0, 30, 0, 30, false)));
		moves = moves.concat(itemMoves(spot)).concat(swimMoves(spot));
		if (spot.rotation != 0) return moves;
		return moves.concat(vanishMoves(spot)).concat(mineMoves(spot));
	}

	/**
		With an item in hand: use it standing, while running each way, at the top
		of a jump each way, and held down (the jetpack flies while it is held).
	**/
	function itemMoves(spot:RouteSpot):Array<RouteMove> {
		var item = spot.item;
		if (item == null) return [];
		var name = Items.getNameFromCode(item);
		var moves = [new RouteMove('use $name', withItem(hold(0, 20, 0, 0, false), 0, 1))];
		for (dir in [1, -1]) {
			var side = dir == 1 ? "right" : "left";
			moves.push(new RouteMove('use $name running $side', withItem(hold(dir, 40, 0, 0, false), 5, 1)));
			moves.push(new RouteMove('use $name mid-jump $side', withItem(hold(dir, 40, 0, 30, false), 12, 1)));
			moves.push(new RouteMove('hold $name going $side', withItem(hold(dir, 60, 0, 0, false), 0, 60)));
		}
		moves.push(new RouteMove('hold $name going up', withItem(hold(0, 60, 0, 30, false), 0, 60)));
		return moves;
	}

	/** `inputs` with the item key held from `from` for `frames` frames. **/
	static function withItem(inputs:Array<LocalPlayerInput>, from:Int, frames:Int):Array<LocalPlayerInput> {
		while (inputs.length < from + frames) inputs.push(new LocalPlayerInput());
		for (i in from...from + frames) inputs[i] = new LocalPlayerInput(inputs[i].left, inputs[i].right, inputs[i].jump, inputs[i].down, true);
		return inputs;
	}

	/** In water: swim up (jump held) straight or to each side, and dive (down) to each side. **/
	function swimMoves(spot:RouteSpot):Array<RouteMove> {
		if (!spot.inWater) return [];
		var moves = [new RouteMove("swim up", hold(0, 60, 0, 60, false))];
		for (dir in [1, -1]) {
			var side = dir == 1 ? "right" : "left";
			for (frames in [40, 90]) moves.push(new RouteMove('swim up and $side ($frames)', hold(dir, frames, 0, frames, false)));
			moves.push(new RouteMove('swim $side (90)', hold(dir, 90, 0, 0, false)));
			moves.push(new RouteMove('dive $side', [for (_ in 0...40) new LocalPlayerInput(dir == -1, dir == 1, false, true)]));
		}
		return moves;
	}

	/**
		Next to a vanish block: touch it (walk into it, or jump up into it), wait
		for it to fade, then go through where it was before it comes back.
	**/
	function vanishMoves(spot:RouteSpot):Array<RouteMove> {
		var moves:Array<RouteMove> = [];
		var wait = BlockController.VANISH_FADE_FRAMES + 2;
		for (block in vanishes) {
			var dx = block.x - spot.tileX;
			var dy = block.y - spot.tileY;
			if (Math.abs(dx) > 2 || dy < -3 || dy > 0) continue;
			var name = 'vanish block at ${block.x},${block.y}';
			if (dx != 0) {
				var dir = dx > 0 ? 1 : -1;
				var side = dir == 1 ? "right" : "left";
				// Walk into it, stand still while it fades, then walk through.
				var inputs = hold(dir, 12 + Std.int(Math.abs(dx)) * 8, 0, 0, false);
				for (_ in 0...wait) inputs.push(new LocalPlayerInput());
				moves.push(new RouteMove('$name: push it, wait, walk $side', inputs.concat(hold(dir, 40, 0, 0, false))));
			}
			if (dy <= -2) {
				// Overhead: jump up into it, wait for it to fade, then jump up through (and to each side).
				for (dir in [0, 1, -1]) {
					var inputs = hold(0, 10, 0, 10, false);
					for (_ in 0...wait) inputs.push(new LocalPlayerInput());
					var side = dir == 0 ? "up" : (dir == 1 ? "up and right" : "up and left");
					moves.push(new RouteMove('$name: bump it, wait, jump $side', inputs.concat(hold(dir, 40, 0, 30, false))));
				}
			}
		}
		return moves;
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
		runMove(spot, move.name,
			picks -> simulate(spot.script, spot.script.length, false, () -> walkThen(move.approachX, MINE_APPROACH_TOLERANCE, inputs.length, (i, _) -> inputs[i]),
				true, picks),
			sim -> spot.script.concat(sim.policyInputs));
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

	/** How a recipe uses an item, for the step name. **/
	static function itemTag(recipe:ClipAttempt):String {
		var items = recipe.items;
		if (items == null || items.heldItem == null) return "";
		return switch (items.heldItem) {
			case 1: " (laser recoil)";
			case 8: " (sword lunge)";
			case 5: " (super jump item)";
			case 7: " (speed burst)";
			default: "";
		}
	}

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
		// A held item (laser, sword, super jump, speed burst) opens its own clips: a separate recipe per item.
		var item = spot.item;
		var key = cornerKey(corner) + (item != null ? '+item$item' : "");
		if (!recipes.exists(key)) {
			var scanSettings = new ClipScanSettings(settings.speed, settings.accel, settings.jump, settings.gravity);
			scanSettings.hats = settings.hats;
			scanSettings.passThroughOnly = true;
			scanSettings.heldItem = item;
			if (settings.recipeDistances != null) scanSettings.distances = settings.recipeDistances;
			if (settings.recipeJumpHolds != null) scanSettings.jumpHolds = settings.recipeJumpHolds;
			if (settings.recipeSuperCharges != null) scanSettings.superCharges = settings.recipeSuperCharges;
			if (settings.recipeLaserHolds != null) scanSettings.laserHolds = settings.recipeLaserHolds;
			if (settings.recipeLaserFireFrames != null) scanSettings.laserFireFrames = settings.recipeLaserFireFrames;
			if (settings.recipeLaserGaps != null) scanSettings.laserGaps = settings.recipeLaserGaps;
			recipeScan = new ClipScanner(blocksForScans, scanSettings, corner);
			recipeKey = key;
			return false;
		}
		var recipe = recipes.get(key);
		if (recipe == null) return true;
		runMove(spot, move.name + itemTag(recipe), picks -> simulate(spot.script, spot.script.length, false, () -> walkThenRecipe(recipe), true, picks),
			sim -> spot.script.concat(sim.policyInputs));
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
		var bestErr = Math.POSITIVE_INFINITY;
		var stale = 0;
		var idleAtWall = 0;
		return function(frame:Int, player:LocalPlayerController):Null<LocalPlayerInput> {
			if (launching) {
				var i = frame - launchFrame;
				return i < length ? inputAt(i, player.grounded) : null;
			}
			if (floorY == null) floorY = player.y;
			if (frame > MAX_APPROACH_FRAMES || (player.grounded && Math.abs(player.y - floorY) > 2)) return ABORT;
			var err = targetX - player.x;
			// Against a wall the exact pixel may be out of reach (the wall nudges the
			// player back a fraction each tap): close enough and no longer getting
			// closer counts, after a few idle frames (the physics decides the rest).
			if (Math.abs(err) < bestErr - 0.05) {
				bestErr = Math.abs(err);
				stale = 0;
			} else {
				stale++;
			}
			if (bestErr <= WALL_TOLERANCE && stale >= 30 && Math.abs(err) <= WALL_TOLERANCE && player.grounded && tap == 0) {
				if (++idleAtWall >= 3) {
					launching = true;
					launchFrame = frame + 1;
				}
				return new LocalPlayerInput();
			}
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
		return simulate(found.script, 0, true, null, false, found.picks);
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

/** A player standing on a spot (after `frame` frames of its script), copied for each move tried from it. **/
private class SpotBase {
	public final player:LocalPlayerController;
	public final frame:Int;
	/** Mines in the level when the run started, so mines hit count from the start. **/
	public final minesAtStart:Int;
	/** The spot it belongs to. **/
	public final script:Null<RouteSpot>;
	/** Uses left on the held item there (item uses live in a global store, not on the player). **/
	public final itemUses:Float;

	public function new(player:LocalPlayerController, frame:Int, minesAtStart:Int, script:Null<RouteSpot>, itemUses:Float) {
		this.player = player;
		this.frame = frame;
		this.minesAtStart = minesAtStart;
		this.script = script;
		this.itemUses = itemUses;
	}
}
/**
	How far each tile is from the target, going through the level's open tiles
	(Dijkstra over the tile grid, 8 directions). Blocks a player can get
	through (vanish, brick, crumble, mine, push, move) count as open but cost
	more; other solid blocks are walls. The route planner uses it so a far
	target pulls the search along corridors instead of straight into walls.
	Tiles it can't reach (or outside the level) fall back to straight-line
	distance plus a penalty.
**/
class TargetField {
	static inline var MARGIN:Int = 6;
	static inline var SOFT_COST:Float = 4;
	static inline var UNREACHABLE_PENALTY:Float = 40;

	final minX:Int;
	final minY:Int;
	final width:Int;
	final height:Int;
	final targetX:Int;
	final targetY:Int;
	final dist:Array<Float>;

	public function new(blocks:Array<LevelBlock>, targetX:Int, targetY:Int) {
		this.targetX = targetX;
		this.targetY = targetY;
		var x0 = targetX, y0 = targetY, x1 = targetX, y1 = targetY;
		for (b in blocks) {
			if (b.x < x0) x0 = b.x;
			if (b.y < y0) y0 = b.y;
			if (b.x > x1) x1 = b.x;
			if (b.y > y1) y1 = b.y;
		}
		minX = x0 - MARGIN;
		minY = y0 - MARGIN;
		width = x1 - x0 + 1 + MARGIN * 2;
		height = y1 - y0 + 1 + MARGIN * 2;
		// Step cost into each tile: 1 for open, SOFT_COST for blocks that can be cleared, -1 for walls.
		var cost = [for (_ in 0...width * height) 1.0];
		for (b in blocks) {
			if (b.isMarker() || !b.type.isSolid()) continue;
			var i = (b.y - minY) * width + (b.x - minX);
			cost[i] = switch (b.type) {
				case BlockType.Vanish | BlockType.Brick | BlockType.Crumble | BlockType.Mine | BlockType.Push | BlockType.Move: SOFT_COST;
				default: -1;
			};
		}
		dist = [for (_ in 0...width * height) Math.POSITIVE_INFINITY];
		// Start from the target itself (it is usually solid; its open neighbours get 1).
		var heap = new FieldHeap();
		var start = index(targetX, targetY);
		if (start >= 0) {
			dist[start] = 0;
			heap.push(start, 0);
		}
		var dirs = [[1, 0, 1.0], [-1, 0, 1.0], [0, 1, 1.0], [0, -1, 1.0], [1, 1, 1.42], [1, -1, 1.42], [-1, 1, 1.42], [-1, -1, 1.42]];
		while (heap.size > 0) {
			var at = heap.popIndex();
			var d = heap.lastKey;
			if (d > dist[at]) continue;
			var ax = at % width, ay = Std.int(at / width);
			for (dir in dirs) {
				var nx = ax + Std.int(dir[0]), ny = ay + Std.int(dir[1]);
				if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
				var n = ny * width + nx;
				var step = cost[n];
				if (step < 0) continue;
				var nd = d + dir[2] * step;
				if (nd < dist[n]) {
					dist[n] = nd;
					heap.push(n, nd);
				}
			}
		}
	}

	inline function index(x:Int, y:Int):Int {
		var gx = x - minX, gy = y - minY;
		return gx < 0 || gy < 0 || gx >= width || gy >= height ? -1 : gy * width + gx;
	}

	/** Tiles to the target through open space (straight-line plus a penalty where the field doesn't reach). **/
	public function distance(x:Int, y:Int):Float {
		var i = index(x, y);
		var d = i < 0 ? Math.POSITIVE_INFINITY : dist[i];
		if (d != Math.POSITIVE_INFINITY) return d;
		var dx = x - targetX, dy = y - targetY;
		return Math.sqrt(dx * dx + dy * dy) + UNREACHABLE_PENALTY;
	}
}

/** A small binary min-heap of (tile index, distance) for TargetField. **/
private class FieldHeap {
	final keys:Array<Float> = [];
	final items:Array<Int> = [];
	public var lastKey(default, null):Float = 0;

	public function new() {}

	public var size(get, never):Int;
	inline function get_size():Int return items.length;

	public function push(item:Int, key:Float):Void {
		var i = items.length;
		items.push(item);
		keys.push(key);
		while (i > 0) {
			var parent = (i - 1) >> 1;
			if (keys[parent] <= keys[i]) break;
			swap(i, parent);
			i = parent;
		}
	}

	public function popIndex():Int {
		var top = items[0];
		lastKey = keys[0];
		var last = items.length - 1;
		swap(0, last);
		items.pop();
		keys.pop();
		var i = 0;
		while (true) {
			var l = i * 2 + 1, r = l + 1, m = i;
			if (l < items.length && keys[l] < keys[m]) m = l;
			if (r < items.length && keys[r] < keys[m]) m = r;
			if (m == i) break;
			swap(i, m);
			i = m;
		}
		return top;
	}

	inline function swap(a:Int, b:Int):Void {
		var k = keys[a];
		keys[a] = keys[b];
		keys[b] = k;
		var t = items[a];
		items[a] = items[b];
		items[b] = t;
	}
}

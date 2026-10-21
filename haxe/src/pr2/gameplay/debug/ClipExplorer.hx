package pr2.gameplay.debug;

import pr2.gameplay.debug.ClipSimulator.ClipArea;
import pr2.gameplay.debug.ClipSimulator.ClipAttempt;
import pr2.gameplay.debug.ClipSimulator.ClipHats;
import pr2.gameplay.debug.ClipSimulator.ClipItems;
import pr2.gameplay.debug.ClipSimulator.ClipSnapshot;
import pr2.gameplay.player.LocalPlayerController;
import pr2.gameplay.player.LocalPlayerInput;
import pr2.level.BlockType;
import pr2.level.Level;
import pr2.level.Level.LevelBlock;

class ExploreSettings {
	public var startX:Float;
	public var startY:Float;
	public var speed:Float;
	public var accel:Float;
	public var jump:Float;
	public var gravity:Float;
	public var hats:Null<ClipHats> = null;
	public var items:Null<ClipItems> = null;
	/** The course turn the search starts in (start and target are in its course coordinates). **/
	public var courseRotation:Int = 0;
	/** Only clips into this tile count (null = any block). **/
	public var targetTileX:Null<Int> = null;
	public var targetTileY:Null<Int> = null;
	/** Longest input script tried, in frames. **/
	public var maxFrames:Int = 420;
	/** States kept waiting to be expanded (the worst are dropped beyond this). **/
	public var maxOpen:Int = 2500;
	/** States expanded before the search gives up (0 = until stopped). **/
	public var maxExpansions:Int = 0;
	/** Clips kept before it stops. **/
	public var maxClips:Int = 30;
	/** Tiles around the start (and the target) the simulated level covers. **/
	public var margin:Int = 18;
	/** Any block of the target's mass counts as a hit (the "any block" hunt aims at a block but takes any clip into its mass). **/
	public var wholeMass:Bool = false;

	public function new(startX:Float, startY:Float, speed:Float, accel:Float, jump:Float, gravity:Float) {
		this.startX = startX;
		this.startY = startY;
		this.speed = speed;
		this.accel = accel;
		this.jump = jump;
		this.gravity = gravity;
	}
}

/** A clip the explorer found, with the mechanics that made it happen. **/
class ExploredClip {
	public final found:ClipFinder.FoundClip;
	/** Why it clips, in words (from the state on the frames before the clip). **/
	public final why:String;

	public function new(found:ClipFinder.FoundClip, why:String) {
		this.found = found;
		this.why = why;
	}
}

/**
	Stage 4 of the Clip Finder: a search that knows *why* the player clips,
	from LocalPlayerController's collision code, instead of trying random keys.

	What the collision code checks (every frame, after moving):
	- Standing: only the point under the feet's middle (x, y). It only counts
	  when the point 30 px up (x, y - 30) is open; if that point is inside a
	  block, the floor is ignored and the player falls into it.
	- Walls: only two points, 10 px above the feet at x - 10 and x + 10, and
	  only against a block whose open side faces the player.
	- Going up on land: the middle at 30, 25 and 55 px up, and only a block
	  with open space under it. Everything else in the 20 x 55 body (its
	  corners, the sides above the wall points) is never checked.
	- Swimming (and Cowboy Hat flight, which uses the swim code): going up
	  only the top of the head (x, y - 55) is checked, and still only against a
	  block with open space under it. So the head and body can be pushed into
	  a block's lower corner, or into a wall that has a block under its bottom
	  block, and keep going.
	- The Super Jump item adds 25 px a frame upward (more than a block's
	  height is never skipped, but it carries the body past the side checks),
	  and the land super jump's charge (crouchCharge) is only spent by the
	  land code: charge it on the ground, swim (water code runs instead) and
	  it is kept until the player is back on land with down let go, so it
	  can launch in mid-air or as the player leaves the water.
	- The Teleport item moves 120 px sideways after checking one point, 5 px
	  above the feet: the rest of the body can land inside blocks, and the
	  exact 120 px step lines the player up with a corner.
	- Mines blow up when touched, so being inside one is not a clip.

	So instead of the feet alone, the search watches the whole body: how much
	of it is inside blocks where these checks don't look. A move that pushes
	more of the body in (toward the target, if one is picked) is followed up
	first; a move that loses it is followed up last. Saved super jump charge
	and being in the water near blocks count in a move's favour too. Each
	state is a copy of the simulated player, and each move from it is a
	short held combination of keys (left/right, jump, down, item; 1, 3 or 8
	frames), so from any state the search can swim into a corner, press
	against a wall and fire an item, charge a super jump and carry it into
	the water, or teleport to line up. A found clip is replayed from the
	start in a fresh simulation (so it is exact), and comes with what made it.
**/
@:access(pr2.gameplay.player.LocalPlayerController)
class ClipExplorer {
	public final settings:ExploreSettings;
	public final clips:Array<ExploredClip> = [];
	public var expansions(default, null):Int = 0;
	public var simulations(default, null):Int = 0;
	public var done(default, null):Bool = false;
	/** The start overlaps a block. **/
	public var blockedStart(default, null):Bool = false;
	/** Scripts (from the start) that reached the target, for a caller that only wants the first (the route planner). **/
	public var firstScript(default, null):Null<Array<LocalPlayerInput>> = null;

	final blocks:Array<LevelBlock>;
	final area:ClipArea;
	/** Objects copies of the player share (the level, when nothing in it can change). **/
	final shared:Null<Array<Dynamic>>;
	/** States by score (best first), and by script length (shortest first: every third expansion, so the search keeps some breadth). **/
	final open:NodeHeap = new NodeHeap(n -> n.score);
	final shallow:NodeHeap = new NodeHeap(n -> n.script.length);
	final seen:Map<String, Bool> = new Map();
	var seenCount:Int = 0;
	static inline var MAX_SEEN:Int = 200000;
	/** States kept waiting at most (fewer when each carries its own level copy). **/
	var openLimit:Int = 0;
	/** Clips already kept (by where and how), so the same clip isn't listed twice. **/
	final clipKeys:Map<String, Bool> = new Map();
	/** Moves (key combinations) tried from every state. **/
	final moves:Array<ExploreMove>;
	/** Inputs played before the search's own start state (a route planner spot), and how a found script is checked. **/
	final prefix:Array<LocalPlayerInput>;
	final verify:Null<Array<LocalPlayerInput>->Bool>;
	final target:Null<TargetRegion>;

	/**
		`from`: start from a simulated player that is already somewhere (the
		route planner's spots) instead of a fresh one at the settings' start.
	**/
	public function new(blocks:Array<LevelBlock>, settings:ExploreSettings, ?from:ExploreStart) {
		this.blocks = blocks;
		this.settings = settings;
		moves = ExploreMove.all(true);
		var start:LocalPlayerController;
		if (from != null) {
			area = from.area;
			prefix = from.prefix;
			verify = from.verify;
			start = ClipSnapshot.copy(from.player);
			ClipSimulator.setItemUses(from.itemUses);
		} else {
			prefix = [];
			verify = null;
			var sx = ClipSimulator.tileOf(settings.startX), sy = ClipSimulator.tileOf(settings.startY);
			var minX = sx, maxX = sx, minY = sy, maxY = sy;
			if (settings.targetTileX != null && settings.targetTileY != null) {
				// The target is a level tile; the area is built in course tiles.
				var aim = ClipSimulator.layoutTile(settings.targetTileX, settings.targetTileY, settings.courseRotation);
				minX = Std.int(Math.min(minX, aim.x));
				maxX = Std.int(Math.max(maxX, aim.x));
				minY = Std.int(Math.min(minY, aim.y));
				maxY = Std.int(Math.max(maxY, aim.y));
			}
			var m = settings.margin;
			area = ClipArea.forCourse(blocks, minX - m, minY - m, maxX + m, maxY + m, settings.courseRotation);
			var level = area.buildLevel(settings.gravity);
			if (area.overlapsSolid(level, settings.startX, settings.startY, settings.courseRotation)) {
				blockedStart = true;
				done = true;
				shared = null;
				target = null;
				return;
			}
			start = ClipSimulator.preparePlayer(area, level, settings.startX, settings.startY, settings.speed, settings.accel, settings.jump,
				settings.gravity, settings.hats, settings.items, settings.courseRotation);
		}
		// A level of blocks that never change is shared by every copy (a placed mine would change it).
		var level = start.level;
		var mineItem = start.itemId == 2;
		shared = area.staticBlocks() && !mineItem && !hasItemBlocks() ? [level, level.blocks] : null;
		// Each state of a level whose blocks can change carries its own copy of the area: keep fewer.
		openLimit = shared != null ? settings.maxOpen : Std.int(Math.min(settings.maxOpen, 300));
		target = settings.targetTileX == null || settings.targetTileY == null ? null
			: new TargetRegion(level, settings.targetTileX, settings.targetTileY);
		var root = new ExploreNode(start, [], ClipSimulator.itemUses(), new ExploreTrace());
		score(root);
		seen.set(stateKey(start), true);
		open.push(root);
		shallow.push(root);
	}

	/** The best-scored state, or every third time the shortest one (skipping ones already expanded). **/
	function nextNode():Null<ExploreNode> {
		var first = expansions % 3 == 2 ? shallow : open;
		var second = first == open ? shallow : open;
		for (heap in [first, second]) {
			while (heap.size > 0) {
				var node = heap.pop();
				if (node.expanded) continue;
				node.expanded = true;
				return node;
			}
		}
		return null;
	}

	function hasItemBlocks():Bool {
		for (b in blocks) if (b.type == BlockType.Item || b.type == BlockType.InfiniteItem) return true;
		return false;
	}

	/** The state being expanded and the next of its moves (a step can stop between moves). **/
	var expanding:Null<ExploreNode> = null;
	var moveIndex:Int = 0;

	/**
		Plays moves until `maxRuns` were played or `deadline()` says time is up
		(checked after every move, so the game keeps its frame rate). Returns
		moves played.
	**/
	public function step(maxRuns:Int, ?deadline:Void->Bool):Int {
		var runs = 0;
		while (!done && runs < maxRuns && (deadline == null || runs == 0 || !deadline())) {
			if (expanding == null) {
				if (settings.maxExpansions > 0 && expansions >= settings.maxExpansions) {
					done = true;
					break;
				}
				expanding = nextNode();
				moveIndex = 0;
				if (expanding == null) {
					done = true;
					break;
				}
				expansions++;
				if (onExpand != null) onExpand(expanding);
			}
			var node = expanding;
			if (moveIndex >= moves.length) {
				expanding = null;
				continue;
			}
			var move = moves[moveIndex++];
			if (move.item && node.player.itemId == null) continue;
			runs++;
			tryMove(node, move);
		}
		return runs;
	}

	/**
		Plays one key combination from `node` for up to 8 frames on one copy of
		the player, keeping the states after 1, 3 and 8 frames as children
		(each copied only when it is a state not seen before).
	**/
	function tryMove(node:ExploreNode, move:ExploreMove):Void {
		if (node.script.length + 1 > settings.maxFrames) return;
		simulations++;
		var player = ClipSnapshot.copy(node.player, shared);
		ClipSimulator.setItemUses(node.itemUses);
		var script = node.script.copy();
		var trace = node.trace.copy();
		var last = move.frames - 1;
		for (f in 0...move.frames) {
			if (script.length >= settings.maxFrames) return;
			var input = move.inputAt(f);
			var before = new ExploreFrame(player);
			player.step(input);
			script.push(input);
			trace.record(before, input, player);
			var feet = ClipSimulator.toLevel(player.x, player.y, player.courseRotation);
			// Out of the simulated area, or sent back to a safe spot: a dead end.
			if (!area.containsPixel(feet.x, feet.y)) return;
			if ((Math.abs(player.x - before.x) > 60 || Math.abs(player.y - before.y) > 60) && player.x == player.lastSafeX && player.y == player.lastSafeY) return;
			if (ClipSimulator.feetInSolid(player.level, player) && hitsTarget(player)) {
				keepClip(script, trace, player);
				return;
			}
			if (f != last && move.stops.indexOf(f + 1) < 0) continue;
			var key = stateKey(player);
			if (seen.exists(key)) continue;
			// Forget old states now and then, so a long search stays within memory.
			if (++seenCount > MAX_SEEN) {
				seen.clear();
				seenCount = 0;
			}
			seen.set(key, true);
			// The last stop keeps the working copy; earlier ones need their own.
			var child = new ExploreNode(f == last ? player : ClipSnapshot.copy(player, shared), f == last ? script : script.copy(),
				ClipSimulator.itemUses(), f == last ? trace : trace.copy());
			score(child);
			open.push(child);
			shallow.push(child);
			if (open.size > openLimit) open.dropWorst(Std.int(openLimit * 0.8));
			if (shallow.size > openLimit) shallow.dropWorst(Std.int(openLimit * 0.8));
		}
	}

	function hitsTarget(player:LocalPlayerController):Bool {
		var tx = settings.targetTileX, ty = settings.targetTileY;
		if (tx == null || ty == null) return true;
		for (up in [ClipSimulator.FEET_DEPTH, 15.0]) {
			var p = ClipSimulator.toLevel(player.x, player.y - up, player.courseRotation);
			var cx = ClipSimulator.tileOf(p.x), cy = ClipSimulator.tileOf(p.y);
			if (cx == tx && cy == ty) return true;
			if (settings.wholeMass && target != null && target.depth(cx, cy) >= 0) return true;
		}
		return false;
	}

	/** Checks the script by replaying it from the very start, and keeps it with what made it clip. **/
	function keepClip(script:Array<LocalPlayerInput>, trace:ExploreTrace, player:LocalPlayerController):Void {
		var feet = ClipSimulator.toLevel(player.x, player.y, player.courseRotation);
		var key = ClipSimulator.tileOf(feet.x) + "," + ClipSimulator.tileOf(feet.y - ClipSimulator.FEET_DEPTH) + ":" + trace.mechanics().join("+");
		if (clipKeys.exists(key)) return;
		var full = prefix.concat(script);
		var why = trace.explain();
		if (verify != null) {
			if (!verify(full)) return;
			clipKeys.set(key, true);
			if (firstScript == null) firstScript = full;
			lastWhy = why;
			done = true;
			return;
		}
		var s = settings;
		var attempt = new ClipAttempt(s.startX, s.startY, s.speed, s.accel, s.jump, s.gravity, 1, 0, 0, false,
			full.length + ClipSimulator.GHOST_TAIL_FRAMES);
		attempt.script = full;
		attempt.hats = s.hats;
		attempt.items = s.items;
		attempt.courseRotation = s.courseRotation;
		if (s.targetTileX != null && s.targetTileY != null) {
			var aim = ClipSimulator.layoutTile(s.targetTileX, s.targetTileY, s.courseRotation);
			attempt.targetTileX = aim.x;
			attempt.targetTileY = aim.y;
		}
		attempt.label = why;
		var run = ClipSimulator.run(new ClipArea(blocks, area.minTileX, area.minTileY, area.maxTileX, area.maxTileY), attempt, true);
		// The replay from the start must clip too (it always should: copies replay exactly).
		if (!run.clipped) return;
		clipKeys.set(key, true);
		if (firstScript == null) firstScript = full;
		lastWhy = why;
		clips.push(new ExploredClip(new ClipFinder.FoundClip(attempt, run), why));
		if (clips.length >= settings.maxClips) done = true;
	}

	/** What made the last kept clip happen. **/
	public var lastWhy(default, null):String = "";

	/** Debug hook: every state expanded. **/
	public var onExpand:Null<ExploreNode->Void> = null;

	// ---- Scoring: how much of the body is where the collision code doesn't look ----

	/** Body points sampled (px above the feet) and how much each counts when inside a block. **/
	static final SAMPLE_UP:Array<Float> = [3, 12, 22, 32, 42, 52];
	static final SAMPLE_WEIGHT:Array<Float> = [5, 3, 2, 1.5, 1, 1];
	static final SAMPLE_SIDE:Array<Float> = [-9, 0, 9];

	/**
		Lower is expanded first. With a target: how far the body is from the way
		into the target's block mass (the nearest of its blocks with an open side,
		counting how far that block is from the target through the mass), or,
		once part of the body is inside the mass, how far that part is from the
		target, minus how much of the body is in. Without one: minus how much of
		the body is inside any block. Then minus saved super jump charge and
		swimming next to blocks, plus a little per frame.
	**/
	function score(node:ExploreNode):Void {
		var p = node.player;
		var lv = p.level;
		var inside = 0.0, inRegion = 0.0;
		var deepest = Math.POSITIVE_INFINITY;
		var nearBlocks = 0;
		var region = target;
		for (i in 0...SAMPLE_UP.length) {
			for (side in SAMPLE_SIDE) {
				var pt = ClipSimulator.toLevel(p.x + side, p.y - SAMPLE_UP[i], p.courseRotation);
				var cx = ClipSimulator.tileOf(pt.x), cy = ClipSimulator.tileOf(pt.y);
				if (ClipSimulator.clippable(lv.blockAt(cx, cy), p)) {
					inside += SAMPLE_WEIGHT[i];
					if (region != null) {
						var d = region.depth(cx, cy);
						if (d >= 0) {
							inRegion += SAMPLE_WEIGHT[i];
							// The feet points lead: the clip is the feet going in.
							deepest = Math.min(deepest, d + (i == 0 ? 0 : 0.5));
						}
					}
				} else if (i >= 3 && ClipSimulator.clippable(lv.blockAt(cx, cy - 1), p)) {
					nearBlocks++;
				}
			}
		}
		var s = 0.0;
		// Overlap the collision code will push back out doesn't lead anywhere:
		// the head check going up (or, on land, the 25/30 px checks) inside a
		// block with open space under it bumps the player down when rising.
		if (caught(p)) deepest = Math.POSITIVE_INFINITY;
		if (region != null) {
			if (deepest < Math.POSITIVE_INFINITY) {
				s += deepest * 1.5 - inRegion * 0.5;
			} else {
				var c = ClipSimulator.toLevel(p.x, p.y - 27, p.courseRotation);
				s += region.approach(c.x / ClipSimulator.TILE, c.y / ClipSimulator.TILE) * 2 + 4;
				// Lined up so that moving sideways slides the body into the mass
				// with the wall points (10 px up) clear: only the ways in count.
				var side = sideEntry(p, region);
				if (side >= 0 && side < 3) s -= (3 - side) * 1.0;
			}
		} else {
			s -= inside * 0.8;
		}
		// Latent energy the mechanics can turn into a clip.
		if (p.crouchCharge > 25 && (!p.grounded || p.mode == LocalPlayerController.MODE_WATER)) s -= 3 + p.crouchCharge / 25;
		if (p.mode == LocalPlayerController.MODE_WATER) s -= Math.min(nearBlocks, 3) * 0.6;
		s += node.script.length * 0.012;
		node.score = s;
	}

	/**
		True when a point the collision code checks going up is inside a block
		it would bump the player out of (one with open space under it): the top
		of the head (x, y - 55) always, and on land also 25 and 30 px up.
	**/
	static function caught(p:LocalPlayerController):Bool {
		var lv = p.level;
		var t = ClipSimulator.TILE;
		inline function bumps(up:Float):Bool {
			var pt = ClipSimulator.toLevel(p.x, p.y - up, p.courseRotation);
			var cx = ClipSimulator.tileOf(pt.x), cy = ClipSimulator.tileOf(pt.y);
			if (!ClipSimulator.clippable(lv.blockAt(cx, cy), p)) return false;
			// "Below" along the course's own down.
			var below = ClipSimulator.toLevel(p.x, p.y - up + t, p.courseRotation);
			var bx = ClipSimulator.tileOf(below.x), by = ClipSimulator.tileOf(below.y);
			var under = lv.blockAt(bx, by);
			return under == null || !under.type.isSolid() || p.blockController.isBlockRemoved(under);
		}
		if (bumps(LocalPlayerController.STANDING_HEIGHT)) return true;
		if (p.mode != LocalPlayerController.MODE_WATER && (bumps(30) || bumps(25))) return true;
		return false;
	}

	/**
		Walls only stop the player at the two points 10 px above the feet (and
		only at a block whose near side is open). So moving sideways at this
		height, the first column (within 6 tiles each way) where the body above
		those points would be in the target's mass, with the wall points still
		clear there: its distance in tiles, or -1 when there is none. That is
		the way into a thin platform (head over it, feet under it), a block's
		bottom corner while swimming, or any block the head sits level with.
	**/
	static function sideEntry(p:LocalPlayerController, region:TargetRegion):Float {
		var lv = p.level;
		var best = -1.0;
		var t = ClipSimulator.TILE;
		inline function solidAt(x:Float, up:Float):Bool {
			var pt = ClipSimulator.toLevel(x, p.y - up, p.courseRotation);
			return ClipSimulator.clippable(lv.blockAt(ClipSimulator.tileOf(pt.x), ClipSimulator.tileOf(pt.y)), p);
		}
		inline function inMass(x:Float, up:Float):Bool {
			var pt = ClipSimulator.toLevel(x, p.y - up, p.courseRotation);
			return region.depth(ClipSimulator.tileOf(pt.x), ClipSimulator.tileOf(pt.y)) >= 0;
		}
		for (dir in [1, -1]) {
			var step = 0;
			while (step <= 6 * 3) {
				var x = p.x + dir * (10 + step * 10);
				// The wall points are stopped here (an open-sided block at 10 px up): no way through on this side.
				if (solidAt(x, 10) && !solidAt(x - dir * t, 10)) break;
				var hit = false;
				for (up in [22.0, 32.0, 42.0, 52.0]) if (inMass(x - dir * 10, up) || inMass(x, up)) hit = true;
				if (hit) {
					var d = (step * 10) / t;
					if (best < 0 || d < best) best = d;
					break;
				}
				step++;
			}
		}
		return best;
	}

	/** States closer than this are the same (position to 2 px, speed to about 1 px a frame, mode, charge, item). **/
	static function stateKey(p:LocalPlayerController):String {
		var charge = p.crouchCharge > 25 ? Math.round(p.crouchCharge / 10) : 0;
		return Math.round(p.x / 2) + "," + Math.round(p.y / 2) + "," + Math.round(p.vx) + "," + Math.round(p.vy) + "," + p.mode + ","
			+ (p.grounded ? 1 : 0) + "," + charge + "," + p.itemId + "," + Math.round(ClipSimulator.itemUses() * 10) + "," + p.courseRotation
			+ "," + (p.jumpHeld ? 1 : 0);
	}

	public function progressText(stopped:Bool = false):String {
		var verb = stopped ? "Stopped" : (done ? "Done" : "Exploring");
		return '$verb: ${clips.length} clip${clips.length == 1 ? "" : "s"}, $expansions states, $simulations moves';
	}
}

/** Where a search started from a simulated player (the route planner's spot). **/
class ExploreStart {
	public final player:LocalPlayerController;
	public final prefix:Array<LocalPlayerInput>;
	public final area:ClipArea;
	public final itemUses:Float;
	/** Replays a whole script from the very start; true when it reaches the target. **/
	public final verify:Array<LocalPlayerInput>->Bool;

	public function new(player:LocalPlayerController, prefix:Array<LocalPlayerInput>, area:ClipArea, itemUses:Float,
			verify:Array<LocalPlayerInput>->Bool) {
		this.player = player;
		this.prefix = prefix;
		this.area = area;
		this.itemUses = itemUses;
		this.verify = verify;
	}
}

/**
	The target's block mass: the target and every clippable block joined to it
	(side by side, within 12 tiles), how deep each is from the target through
	the mass, and its blocks with an open side (where the body can get in).
**/
class TargetRegion {
	static inline var RANGE:Int = 12;
	final depthOf:Map<Int, Int> = new Map();
	final entries:Array<{x:Int, y:Int, depth:Int}> = [];

	public function new(level:Level, tx:Int, ty:Int) {
		inline function key(x:Int, y:Int):Int return (x & 0xffff) << 16 | (y & 0xffff);
		inline function solid(x:Int, y:Int):Bool {
			var b = level.blockAt(x, y);
			return b != null && b.type.isSolid() && b.type != BlockType.Mine;
		}
		var queue = [{x: tx, y: ty, depth: 0}];
		depthOf.set(key(tx, ty), 0);
		var i = 0;
		while (i < queue.length) {
			var at = queue[i++];
			var open = false;
			for (d in [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
				var nx = at.x + d[0], ny = at.y + d[1];
				if (!solid(nx, ny)) {
					open = true;
					continue;
				}
				if (Math.abs(nx - tx) > RANGE || Math.abs(ny - ty) > RANGE || depthOf.exists(key(nx, ny))) continue;
				depthOf.set(key(nx, ny), at.depth + 1);
				queue.push({x: nx, y: ny, depth: at.depth + 1});
			}
			if (open) entries.push(at);
		}
	}

	/** Tiles from the target through the mass (-1 = not part of it). **/
	public function depth(x:Int, y:Int):Int {
		var d = depthOf.get((x & 0xffff) << 16 | (y & 0xffff));
		return d == null ? -1 : d;
	}

	/** From a point (in tiles), the distance to the best way in: an open-sided block, plus half its depth. **/
	public function approach(x:Float, y:Float):Float {
		var best = Math.POSITIVE_INFINITY;
		for (e in entries) {
			var dx = x - (e.x + 0.5), dy = y - (e.y + 0.5);
			var d = Math.sqrt(dx * dx + dy * dy) + e.depth * 0.5;
			if (d < best) best = d;
		}
		return best;
	}

	/** Blocks of the mass with an open side, nearest the target first. **/
	public function entryTiles():Array<{x:Int, y:Int, depth:Int}> {
		var list = entries.copy();
		list.sort((a, b) -> a.depth - b.depth);
		return list;
	}
}

/**
	"Any block" for Stage 4: an aimed search per block the body could get
	into, a few at a time, taking turns. Blocks are picked from what the
	collision code leaves open: thin platforms (one block thick, so the body
	can straddle them where only the head top and the wall points look),
	blocks with open space under them (the head and swim checks), then blocks
	with an open side, nearest the player first.
**/
@:access(pr2.gameplay.player.LocalPlayerController)
class ClipHunt {
	/** Aimed searches running at once, and how many states each gets before the next block's turn. **/
	static inline var RUNNING:Int = 3;
	static inline var EXPANSIONS_EACH:Int = 400;
	/** Blocks within this many tiles of the start are tried. **/
	static inline var RADIUS:Int = 10;

	public final settings:ExploreSettings;
	public final clips:Array<ExploredClip> = [];
	public var done(default, null):Bool = false;
	public var blockedStart(default, null):Bool = false;
	public var tried(default, null):Int = 0;
	public var candidates(default, null):Int = 0;
	final blocks:Array<LevelBlock>;
	final queue:Array<{x:Int, y:Int}>;
	final running:Array<ClipExplorer> = [];
	final keys:Map<String, Bool> = new Map();
	var turn:Int = 0;

	public function new(blocks:Array<LevelBlock>, settings:ExploreSettings) {
		this.blocks = blocks;
		this.settings = settings;
		queue = pickBlocks();
		candidates = queue.length;
		fill();
		if (running.length > 0 && running[0].blockedStart) {
			blockedStart = true;
			done = true;
		}
	}

	/** Blocks near the start ranked by how open they leave the body (level tiles). **/
	function pickBlocks():Array<{x:Int, y:Int}> {
		var solid:Map<String, Bool> = new Map();
		var seen = ClipSimulator.layoutFor(blocks, settings.courseRotation);
		for (b in seen) if (!b.isMarker() && b.type.isSolid() && b.type != BlockType.Mine) solid.set(b.x + "," + b.y, true);
		inline function at(x:Int, y:Int):Bool return solid.exists(x + "," + y);
		var sx = ClipSimulator.tileOf(settings.startX), sy = ClipSimulator.tileOf(settings.startY);
		var ranked:Array<{x:Int, y:Int, rank:Float}> = [];
		for (b in seen) {
			if (!solid.exists(b.x + "," + b.y)) continue;
			var dx = b.x - sx, dy = b.y - sy;
			if (Math.abs(dx) > RADIUS || Math.abs(dy) > RADIUS) continue;
			var up = !at(b.x, b.y - 1), down = !at(b.x, b.y + 1), left = !at(b.x - 1, b.y), right = !at(b.x + 1, b.y);
			if (!up && !down && !left && !right) continue;
			var rank = Math.sqrt(dx * dx + dy * dy);
			var side = left || right;
			if (down && side) rank -= 6; // a corner underneath: the end of a platform or the bottom of a wall
			else if (down && !up) rank -= 3; // open underneath (a ceiling)
			else if (side) rank -= 2; // a wall face
			else if (down) rank += 1; // the middle of a one-block platform
			else rank += 8; // only its top is open: a floor (corner clips there are Stage 1.5)
			// The floor the player stands on and anything below: falling into floors is what Stages 1 and 1.5 do.
			if (dy >= 0) rank += 6;
			ranked.push({x: b.x, y: b.y, rank: rank});
		}
		ranked.sort((a, b) -> Reflect.compare(a.rank, b.rank));
		// Back to level tiles (the explorer's target is a level tile).
		return [for (r in ranked) ClipSimulator.layoutTile(r.x, r.y, -settings.courseRotation)];
	}

	function fill():Void {
		while (running.length < RUNNING && queue.length > 0) {
			var tile = queue.shift();
			var s = copySettings(tile.x, tile.y);
			running.push(new ClipExplorer(blocks, s));
			tried++;
		}
		if (running.length == 0) done = true;
	}

	function copySettings(tx:Int, ty:Int):ExploreSettings {
		var t = settings;
		var s = new ExploreSettings(t.startX, t.startY, t.speed, t.accel, t.jump, t.gravity);
		s.hats = t.hats;
		s.items = t.items;
		s.courseRotation = t.courseRotation;
		s.maxFrames = t.maxFrames;
		s.margin = t.margin;
		s.maxOpen = Std.int(t.maxOpen / 2);
		s.maxExpansions = EXPANSIONS_EACH;
		s.wholeMass = true;
		s.maxClips = 3;
		s.targetTileX = tx;
		s.targetTileY = ty;
		return s;
	}

	public function step(maxRuns:Int, ?deadline:Void->Bool):Int {
		var runs = 0;
		while (!done && runs < maxRuns && (deadline == null || runs == 0 || !deadline())) {
			if (running.length == 0) {
				done = true;
				break;
			}
			turn = turn % running.length;
			var explorer = running[turn];
			runs += explorer.step(60, deadline);
			collect(explorer);
			if (explorer.done) {
				running.splice(turn, 1);
				fill();
			} else {
				turn++;
			}
			if (clips.length >= settings.maxClips) done = true;
		}
		return runs;
	}

	function collect(explorer:ClipExplorer):Void {
		for (clip in explorer.clips) {
			var run = clip.found.run;
			var key = ClipSimulator.tileOf(run.x) + "," + ClipSimulator.tileOf(run.y - ClipSimulator.FEET_DEPTH) + ":" + clip.why;
			if (keys.exists(key)) continue;
			keys.set(key, true);
			// Any block counts: no target on the listed clip.
			clip.found.attempt.targetTileX = null;
			clip.found.attempt.targetTileY = null;
			clips.push(clip);
		}
	}

	public function progressText(stopped:Bool = false):String {
		var verb = stopped ? "Stopped" : (done ? "Done" : "Exploring");
		return '$verb: ${clips.length} clip${clips.length == 1 ? "" : "s"}, blocks $tried/$candidates';
	}
}

/** Stage 4 in the panel: an aimed search (target picked) or a hunt over every block near the player. **/
class MechanicsSearch {
	final explorer:Null<ClipExplorer>;
	final hunt:Null<ClipHunt>;

	function new(explorer:Null<ClipExplorer>, hunt:Null<ClipHunt>) {
		this.explorer = explorer;
		this.hunt = hunt;
	}

	public static function aimed(explorer:ClipExplorer):MechanicsSearch return new MechanicsSearch(explorer, null);

	public static function everywhere(hunt:ClipHunt):MechanicsSearch return new MechanicsSearch(null, hunt);

	public function step(maxRuns:Int, ?deadline:Void->Bool):Int return explorer != null ? explorer.step(maxRuns, deadline) : hunt.step(maxRuns, deadline);

	public function done():Bool return explorer != null ? explorer.done : hunt.done;

	public function blockedStart():Bool return explorer != null ? explorer.blockedStart : hunt.blockedStart;

	public function clips():Array<ExploredClip> return explorer != null ? explorer.clips : hunt.clips;

	public function progressText(stopped:Bool = false):String {
		return explorer != null ? explorer.progressText(stopped) : hunt.progressText(stopped);
	}
}

/** One held combination of keys for a few frames. **/
class ExploreMove {
	public final dir:Int;
	public final jump:Bool;
	public final down:Bool;
	/** Item pressed on the first frame (or held throughout, `holdItem`). **/
	public final item:Bool;
	public final holdItem:Bool;
	public final frames:Int;
	/** Frames after which the state is kept as a child. **/
	public final stops:Array<Int> = [1, 3, 8];

	public function new(dir:Int, jump:Bool, down:Bool, item:Bool, holdItem:Bool, frames:Int) {
		this.dir = dir;
		this.jump = jump;
		this.down = down;
		this.item = item;
		this.holdItem = holdItem;
		this.frames = frames;
	}

	public function inputAt(f:Int):LocalPlayerInput {
		return new LocalPlayerInput(dir == -1, dir == 1, jump, down, item && (holdItem || f == 0));
	}

	/**
		Every direction with nothing, jump or down held (jump and down together
		cancel out), and with the item tapped (or held, for the Jet Pack); each
		played for 8 frames, with states kept after 1, 3 and 8.
	**/
	public static function all(withItems:Bool):Array<ExploreMove> {
		var out:Array<ExploreMove> = [];
		for (dir in [0, 1, -1]) for (keys in 0...3) out.push(new ExploreMove(dir, keys == 1, keys == 2, false, false, 8));
		if (withItems) {
			for (dir in [0, 1, -1]) for (jump in [false, true]) out.push(new ExploreMove(dir, jump, false, true, false, 8));
			for (dir in [0, 1, -1]) out.push(new ExploreMove(dir, false, false, true, true, 8));
		}
		return out;
	}
}

/** The player as it was before a frame (for the trace). **/
class ExploreFrame {
	public final x:Float;
	public final y:Float;
	public final mode:String;
	public final charge:Float;
	public final grounded:Bool;
	public final item:Null<Int>;
	public final vy:Float;

	@:access(pr2.gameplay.player.LocalPlayerController)
	public function new(p:LocalPlayerController) {
		x = p.x;
		y = p.y;
		mode = p.mode;
		charge = p.crouchCharge;
		grounded = p.grounded;
		item = p.itemId;
		vy = p.vy;
	}
}

/**
	What happened on the way, for explaining a clip: the item uses, super jump
	launches (and whether the charge was carried through water), water and
	cowboy flight in the last frames, pressing against walls.
**/
class ExploreTrace {
	/** Frame numbers of events, and the event names. **/
	var events:Array<String> = [];
	var frame:Int = 0;
	/** Frames spent swimming in the last 20 frames, and whether the body was inside a block while swimming. **/
	var recentWater:Int = 0;
	var swamIntoBlock:Bool = false;
	var chargedOnGround:Bool = false;
	var chargeCarriedInWater:Bool = false;

	public function new() {}

	public function copy():ExploreTrace {
		var t = new ExploreTrace();
		t.events = events.copy();
		t.frame = frame;
		t.recentWater = recentWater;
		t.swamIntoBlock = swamIntoBlock;
		t.chargedOnGround = chargedOnGround;
		t.chargeCarriedInWater = chargeCarriedInWater;
		return t;
	}

	@:access(pr2.gameplay.player.LocalPlayerController)
	public function record(before:ExploreFrame, input:LocalPlayerInput, p:LocalPlayerController):Void {
		frame++;
		var water = p.mode == LocalPlayerController.MODE_WATER || before.mode == LocalPlayerController.MODE_WATER;
		recentWater = water ? Std.int(Math.min(recentWater + 1, 20)) : Std.int(Math.max(recentWater - 1, 0));
		if (water && ClipSimulator.bodyInSolid(p.level, p)) swamIntoBlock = true;
		if (before.grounded && before.charge > 25) chargedOnGround = true;
		if (water && before.charge > 25) chargeCarriedInWater = true;
		// A super jump launched (the charge spent) while not standing: it was saved.
		if (before.charge > 25 && p.crouchCharge == 0 && !input.down && p.vy < -5) {
			add(before.grounded ? "super jump" : (chargeCarriedInWater ? "saved super jump (charged, carried through water)" : "saved super jump"));
		}
		if (input.item && before.item != null && (p.itemId != before.item || ClipSimulator.itemUses() >= 0)) {
			var name = pr2.gameplay.Items.getNameFromCode(before.item);
			if (before.item == 4 && Math.abs(p.x - before.x) >= 100) add('Teleport ${p.x > before.x ? "right" : "left"} (lines up, only the point 5 px up is checked)');
			else if (before.item == 5 && p.vy < before.vy - 10) add(water ? "Super Jump item while swimming" : "Super Jump item");
			else if (before.item != 4 && before.item != 5) add('$name');
		}
		if (input.left || input.right) {
			var wallSide = input.right ? 1 : -1;
			var wall = ClipSimulator.toLevel(p.x + wallSide * 11, p.y - 10, p.courseRotation);
			if (ClipSimulator.clippable(p.level.blockAt(ClipSimulator.tileOf(wall.x), ClipSimulator.tileOf(wall.y)), p)) pressing = frame;
		}
	}

	/** Last frame the player held into a wall it was touching. **/
	var pressing:Int = -100;

	function add(name:String):Void {
		if (events.length > 0 && events[events.length - 1] == name) return;
		events.push(name);
	}

	/** Short names of the mechanics used (for telling clips apart). **/
	public function mechanics():Array<String> {
		var out = events.copy();
		if (recentWater > 0) out.push(swamIntoBlock ? "swim into block" : "swimming");
		if (frame - pressing <= 6) out.push("against wall");
		return out;
	}

	/** Why the clip happens, from the probe model (see ClipExplorer). **/
	public function explain():String {
		var parts:Array<String> = [];
		for (e in events) parts.push(e);
		if (recentWater > 0) {
			parts.push(swamIntoBlock ? "swims into the block (swimming only checks the top of the head going up)" : "while swimming");
		}
		if (frame - pressing <= 6) parts.push("held against the wall (walls are only checked 10 px above the feet)");
		if (parts.length == 0) parts.push("body pushed into the block past the collision points");
		return parts.join(", ");
	}
}

class ExploreNode {
	public final player:LocalPlayerController;
	public final script:Array<LocalPlayerInput>;
	public final itemUses:Float;
	public final trace:ExploreTrace;
	public var score:Float = 0;
	/** Already expanded (it sits in both queues). **/
	public var expanded:Bool = false;

	public function new(player:LocalPlayerController, script:Array<LocalPlayerInput>, itemUses:Float, trace:ExploreTrace) {
		this.player = player;
		this.script = script;
		this.itemUses = itemUses;
		this.trace = trace;
	}
}

/** Min-heap of nodes by score, that can drop its worst entries. **/
private class NodeHeap {
	var items:Array<ExploreNode> = [];

	final key:ExploreNode->Float;

	public function new(key:ExploreNode->Float) {
		this.key = key;
	}

	public var size(get, never):Int;
	inline function get_size():Int return items.length;

	public function push(node:ExploreNode):Void {
		var i = items.length;
		items.push(node);
		while (i > 0) {
			var parent = (i - 1) >> 1;
			if (key(items[parent]) <= key(items[i])) break;
			swap(i, parent);
			i = parent;
		}
	}

	public function pop():Null<ExploreNode> {
		if (items.length == 0) return null;
		var top = items[0];
		var last = items.pop();
		if (items.length > 0) {
			items[0] = last;
			var i = 0;
			while (true) {
				var l = i * 2 + 1, r = l + 1, m = i;
				if (l < items.length && key(items[l]) < key(items[m])) m = l;
				if (r < items.length && key(items[r]) < key(items[m])) m = r;
				if (m == i) break;
				swap(i, m);
				i = m;
			}
		}
		return top;
	}

	/** Keeps only the best `keep` entries. **/
	public function dropWorst(keep:Int):Void {
		items.sort((a, b) -> Reflect.compare(key(a), key(b)));
		if (items.length > keep) items.resize(keep);
		// A sorted array is a valid heap.
	}

	inline function swap(a:Int, b:Int):Void {
		var t = items[a];
		items[a] = items[b];
		items[b] = t;
	}
}

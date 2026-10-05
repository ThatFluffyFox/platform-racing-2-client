package pr2.tools;

import pr2.gameplay.player.LocalPlayerController;
import pr2.gameplay.player.LocalPlayerInput;
import pr2.level.BlockType;
import pr2.level.Level;
import pr2.level.Level.LevelBlock;
import pr2.level.Level.StatDefaults;
import pr2.level.Level.TilePosition;

/**
	Brute-forces stat and input combinations against an inside corner (a floor
	meeting a full-height wall) and reports every run in which the player's body
	ends up inside a solid tile.

	Runs the real `LocalPlayerController`, so results match in-game physics.
	See `tools/clip_sweep.sh --help` for usage.
**/
class ClipSweep {
	static inline var TILE:Int = 30;
	static inline var COLS:Int = 22;
	static inline var ROWS:Int = 20;
	static inline var FLOOR_ROW:Int = 17;
	static inline var THICKNESS:Int = 3;

	static var speeds:Array<Float> = [80, 90, 100];
	static var accels:Array<Float> = [50, 100];
	static var jumps:Array<Float> = [50, 75, 100];
	static var gravities:Array<Float> = [1];
	static var distances:Array<Float> = [for (i in 150...251) i];
	static var heights:Array<Float> = [0];
	static var jumpFrames:Array<Float> = [0, 1, 2, 3, 4];
	static var holds:Array<Float> = [8, 999];
	static var downModes:Array<Float> = [0, 1];
	static var dirs:Array<Float> = [1];
	static var frames:Int = 120;
	static var randomRuns:Int = 0;
	static var seed:Int = 1;
	static var pick:Int = -1;
	static var maxPrint:Int = 25;
	static var traceRun:Bool = false;

	static var levelCache:Map<String, Level> = new Map();

	public static function main():Void {
		if (!parseArgs(argv())) {
			return;
		}
		var total = 0;
		var clips = 0;
		var printed = 0;
		var byStat:Map<String, Map<String, Int>> = new Map();
		var tally = function(stat:String, value:String):Void {
			var counts = byStat.get(stat);
			if (counts == null) byStat.set(stat, counts = new Map());
			counts.set(value, (counts.exists(value) ? counts.get(value) : 0) + 1);
		};
		var onClip = function(c:Case, r:Result):Void {
			clips++;
			tally("dir", c.dir == 1 ? "right" : "left");
			tally("speed", Std.string(c.speed));
			tally("accel", Std.string(c.accel));
			tally("jump", Std.string(c.jump));
			tally("gravity", Std.string(c.gravity));
			if (c.script == null) {
				tally("hold", Std.string(c.hold));
				tally("down", c.down ? "1" : "0");
			}
			if (printed < maxPrint) {
				printed++;
				out('CLIP frame=${r.frame} x=${r.x} y=${r.y} vx=${fmt(r.vx)} vy=${fmt(r.vy)}  ${c.describe()}');
				out('  reproduce: tools/clip_sweep.sh ${c.args()} --trace');
			}
		};

		if (randomRuns > 0) {
			out('Running ${pick >= 0 ? 1 : randomRuns} random runs (seed $seed)...');
			var rng = new Rng(seed);
			for (index in 0...randomRuns) {
				// Every case is generated so --pick replays exactly the same inputs.
				var c = Case.random(rng, frames);
				c.randomIndex = index;
				c.randomSeed = seed;
				c.randomCount = randomRuns;
				if (pick >= 0 && index != pick) continue;
				total++;
				var r = run(c);
				if (r != null) onClip(c, r);
			}
		} else {
			var planned = dirs.length * gravities.length * speeds.length * accels.length * jumps.length * distances.length * heights.length
				* jumpFrames.length * holds.length * downModes.length;
			out('Running $planned grid runs...');
			for (dir in dirs) for (g in gravities) for (s in speeds) for (a in accels) for (j in jumps)
				for (d in distances) for (h in heights) for (jf in jumpFrames) for (hold in holds) for (down in downModes) {
					var c = new Case(Std.int(dir), g, s, a, j, d, h, Std.int(jf), Std.int(hold), down != 0, frames);
					total++;
					var r = run(c);
					if (r != null) onClip(c, r);
				}
		}
		if (clips > printed) {
			out('... ${clips - printed} more clipping runs not shown (raise --max-print)');
		}
		out('Ran $total runs; $clips clipped into solid blocks.');
		if (clips > 0) {
			out("Clipping runs by value:");
			for (stat in ["dir", "speed", "accel", "jump", "gravity", "hold", "down"]) {
				var counts = byStat.get(stat);
				if (counts == null) continue;
				var keys = [for (k in counts.keys()) k];
				keys.sort((a, b) -> {
					var fa = Std.parseFloat(a), fb = Std.parseFloat(b);
					return Math.isNaN(fa) || Math.isNaN(fb) ? Reflect.compare(a, b) : Reflect.compare(fa, fb);
				});
				out('  $stat: ' + [for (k in keys) '$k=${counts.get(k)}'].join("  "));
			}
		}
	}

	static function run(c:Case):Null<Result> {
		var level = levelFor(c);
		var player = new LocalPlayerController(level);
		var wallFace = c.dir == 1 ? (COLS - THICKNESS) * TILE : THICKNESS * TILE;
		var halfWidth = LocalPlayerController.STANDING_WIDTH / 2;
		// Clears the constructor's grounded state, then one idle frame lets the
		// real collision pass decide it: floor starts stand, mid-air starts fall.
		player.resetPreRacePosition(wallFace - c.dir * (halfWidth + c.distance), FLOOR_ROW * TILE - c.height);
		player.step(new LocalPlayerInput());
		var settledFrames = 0;
		var clip:Null<Result> = null;
		for (f in 0...c.frames) {
			var input = c.inputAt(f, player.grounded);
			player.step(input);
			if (traceRun) {
				out('f=$f in=${inputString(input)} x=${fmt(player.x)} y=${fmt(player.y)} vx=${fmt(player.vx)} vy=${fmt(player.vy)} grounded=${player.grounded} crouch=${player.crouching} bodyInSolid=${bodyInSolid(level, player)}');
			}
			if (clip == null && bodyInSolid(level, player)) {
				clip = new Result(f, player.x, player.y, player.vx, player.vy);
				// --trace keeps going so the frames after the clip are visible.
				if (!traceRun) return clip;
			}
			// Scripted runs are over once the jump is done and the player has
			// stood still against the wall for a while; nothing changes after that.
			settledFrames = player.grounded && Math.abs(player.vx) < 0.5 && Math.abs(player.vy) < 1 ? settledFrames + 1 : 0;
			if (c.script == null && !traceRun && f >= c.jumpFrame + Std.int(Math.min(c.hold, 30)) && settledFrames >= 10) {
				break;
			}
		}
		return clip;
	}

	/** The body midpoint is the same point Flash samples for `bodyTouch`. **/
	static function bodyInSolid(level:Level, player:LocalPlayerController):Bool {
		var tx = Std.int(Math.floor(player.x / TILE));
		var ty = Std.int(Math.floor((player.y - 15) / TILE));
		var block = level.blockAt(tx, ty);
		return block != null && block.type.isSolid();
	}

	/**
		dir=1: floor on the left, wall on the right.
		dir=-1: the mirror image. `run` then places the player's leading edge
		`distance` px from the wall and its feet `height` px above the floor.
	**/
	static function levelFor(c:Case):Level {
		var key = '${c.dir}|${c.gravity}|${c.speed}|${c.accel}|${c.jump}';
		var cached = levelCache.get(key);
		if (cached != null) return cached;
		var blocks:Array<LevelBlock> = [];
		var wallStart = c.dir == 1 ? COLS - THICKNESS : 0;
		for (col in 0...COLS) {
			var inWall = col >= wallStart && col < wallStart + THICKNESS;
			for (row in 0...ROWS) {
				if (inWall || row >= FLOOR_ROW) {
					blocks.push(new LevelBlock(col, row, BlockType.Basic));
				}
			}
		}
		// Constructed standing mid-floor; `run` then moves the player into place.
		var startCol = Std.int(COLS / 2);
		var startRow = FLOOR_ROW - 1;
		var stats = new StatDefaults(c.speed, 0.2 + c.accel / 60, 2 + c.jump / 40);
		// Basic blocks never change, and each run gets its own BlockController,
		// so the level can be shared between runs with the same layout and stats.
		var level = new Level("clip-sweep", "Clip Sweep", COLS, ROWS, TILE, c.gravity, stats, new TilePosition(startCol, startRow),
			new TilePosition(0, 0), blocks);
		levelCache.set(key, level);
		return level;
	}

	// The sweep is compiled to JS and run under Node for speed (see
	// tools/clip_sweep.sh); the eval target is kept working for --interp use.
	static function out(line:String):Void {
		#if js
		js.Syntax.code("console.log({0})", line);
		#else
		Sys.println(line);
		#end
	}

	static function argv():Array<String> {
		#if js
		return js.Syntax.code("process.argv.slice(2)");
		#else
		return Sys.args();
		#end
	}

	static function inputString(i:LocalPlayerInput):String {
		return (i.left ? "L" : "-") + (i.right ? "R" : "-") + (i.jump ? "J" : "-") + (i.down ? "D" : "-");
	}

	static function fmt(v:Float):String {
		return Std.string(Math.round(v * 100) / 100);
	}

	static function parseArgs(args:Array<String>):Bool {
		var i = 0;
		while (i < args.length) {
			var flag = args[i];
			var value = i + 1 < args.length ? args[i + 1] : "";
			switch (flag) {
				case "--speed": speeds = parseList(value);
				case "--accel": accels = parseList(value);
				case "--jump": jumps = parseList(value);
				case "--gravity": gravities = parseList(value);
				case "--distance": distances = parseList(value);
				case "--height": heights = parseList(value);
				case "--jump-frame": jumpFrames = parseList(value);
				case "--hold": holds = parseList(value);
				case "--down": downModes = parseList(value);
				case "--dir": dirs = [for (d in value.split(",")) d == "left" || d == "-1" ? -1.0 : 1.0];
				case "--frames": frames = Std.parseInt(value);
				case "--random": randomRuns = Std.parseInt(value);
				case "--seed": seed = Std.parseInt(value);
				case "--pick": pick = Std.parseInt(value);
				case "--max-print": maxPrint = Std.parseInt(value);
				case "--trace":
					traceRun = true;
					i++;
					continue;
				case "-h" | "--help":
					printHelp();
					return false;
				default:
					out('Unknown option: $flag');
					printHelp();
					return false;
			}
			i += 2;
		}
		return true;
	}

	/** Accepts "80", "50,80,100", or an inclusive range "start:end[:step]". **/
	static function parseList(value:String):Array<Float> {
		var out:Array<Float> = [];
		for (part in value.split(",")) {
			if (part.indexOf(":") >= 0) {
				var bits = part.split(":");
				var start = Std.parseFloat(bits[0]);
				var end = Std.parseFloat(bits[1]);
				var step = bits.length > 2 ? Std.parseFloat(bits[2]) : 1;
				var v = start;
				while (v <= end + 1e-9) {
					out.push(v);
					v += step;
				}
			} else {
				out.push(Std.parseFloat(part));
			}
		}
		return out;
	}

	static function printHelp():Void {
		out("Usage: tools/clip_sweep.sh [options]");
		out("Every option takes a list: 80 | 50,80,100 | 0:100:10 (inclusive range with step).");
		out("  --speed L       speed stat (0-100)            default 80:100:10");
		out("  --accel L       acceleration stat (0-100)     default 50,100");
		out("  --jump L        jump stat (0-100)             default 50:100:25");
		out("  --gravity L     level gravity multiplier      default 1");
		out("  --distance L    px from player edge to wall   default 150:250 (1 px steps)");
		out("  --height L      px of feet above the floor    default 0");
		out("  --jump-frame L  frame jump is first pressed   default 0:4");
		out("  --hold L        frames jump is held           default 8,999");
		out("  --down L        0 = never, 1 = hold down while airborne after the jump  default 0,1");
		out("  --dir L         right,left (which side the wall is on)  default right");
		out("  --frames N      frames simulated per run      default 120");
		out("  --random N      instead of the grid, run N random stat/input sequences");
		out("  --seed N        seed for --random             default 1");
		out("  --pick K        with --random, run only random case #K (as printed by a CLIP)");
		out("  --max-print N   clipping runs to print        default 25");
		out("  --trace         print every frame (use with a single combination)");
		out("The player always holds toward the wall. A run clips when the body point");
		out("(x, y-15) lands inside a solid tile.");
	}
}

private class Case {
	public final dir:Int;
	public final gravity:Float;
	public final speed:Float;
	public final accel:Float;
	public final jump:Float;
	public final distance:Float;
	public final height:Float;
	public final jumpFrame:Int;
	public final hold:Int;
	public final down:Bool;
	public final frames:Int;
	/** Per-frame inputs for --random runs; null for scripted grid runs. **/
	public var script:Null<Array<LocalPlayerInput>> = null;
	public var randomIndex:Int = -1;
	public var randomSeed:Int = 0;
	public var randomCount:Int = 0;

	public function new(dir:Int, gravity:Float, speed:Float, accel:Float, jump:Float, distance:Float, height:Float, jumpFrame:Int, hold:Int,
			down:Bool, frames:Int) {
		this.dir = dir;
		this.gravity = gravity;
		this.speed = speed;
		this.accel = accel;
		this.jump = jump;
		this.distance = distance;
		this.height = height;
		this.jumpFrame = jumpFrame;
		this.hold = hold;
		this.down = down;
		this.frames = frames;
	}

	public function inputAt(frame:Int, grounded:Bool):LocalPlayerInput {
		if (script != null) {
			return script[frame];
		}
		var jumping = frame >= jumpFrame && frame < jumpFrame + hold;
		var fastFall = down && frame >= jumpFrame && !grounded;
		return new LocalPlayerInput(dir == -1, dir == 1, jumping, fastFall);
	}

	public function describe():String {
		var base = 'dir=${dir == 1 ? "right" : "left"} speed=$speed accel=$accel jump=$jump gravity=$gravity dist=$distance height=$height';
		if (script != null) {
			// Run-length encoded, e.g. "Rx12 RJx5 -x3" ("-" = nothing held).
			var runs:Array<String> = [];
			var last = "";
			var count = 0;
			for (i in script) {
				var keys = (i.left ? "L" : "") + (i.right ? "R" : "") + (i.jump ? "J" : "") + (i.down ? "D" : "");
				if (keys == "") keys = "-";
				if (keys == last) {
					count++;
				} else {
					if (count > 0) runs.push('${last}x$count');
					last = keys;
					count = 1;
				}
			}
			if (count > 0) runs.push('${last}x$count');
			return base + ' inputs=' + runs.join(" ");
		}
		return base + ' jumpFrame=$jumpFrame hold=$hold down=${down ? 1 : 0}';
	}

	public function args():String {
		if (script != null) {
			return '--random $randomCount --seed $randomSeed --pick $randomIndex --frames $frames';
		}
		return '--dir ${dir == 1 ? "right" : "left"} --speed $speed --accel $accel --jump $jump --gravity $gravity --distance $distance --height $height'
			+ ' --jump-frame $jumpFrame --hold $hold --down ${down ? 1 : 0} --frames $frames';
	}

	public static function random(rng:Rng, frames:Int):Case {
		var c = new Case(rng.int(2) == 0 ? 1 : -1, [0.5, 1, 1, 1.5, 2][rng.int(5)], rng.int(101), rng.int(101), rng.int(101), rng.int(240),
			rng.int(150), 0, 0, false, frames);
		// Each input bit is held for a random stretch, like a real player would.
		var script:Array<LocalPlayerInput> = [];
		var left = false, right = false, jump = false, down = false;
		for (_ in 0...frames) {
			if (rng.int(8) == 0) left = rng.int(4) == 0;
			if (rng.int(8) == 0) right = rng.int(3) != 0;
			if (rng.int(6) == 0) jump = !jump;
			if (rng.int(10) == 0) down = rng.int(4) == 0;
			if (c.dir == 1 && !left) right = right || rng.int(3) != 0;
			if (c.dir == -1 && !right) left = left || rng.int(3) != 0;
			script.push(new LocalPlayerInput(left, right, jump, down));
		}
		c.script = script;
		return c;
	}
}

private class Result {
	public final frame:Int;
	public final x:Float;
	public final y:Float;
	public final vx:Float;
	public final vy:Float;

	public function new(frame:Int, x:Float, y:Float, vx:Float, vy:Float) {
		this.frame = frame;
		this.x = x;
		this.y = y;
		this.vx = vx;
		this.vy = vy;
	}
}

/** Small deterministic PRNG so --seed reproduces the same random runs. **/
private class Rng {
	var state:Int;

	public function new(seed:Int) {
		state = seed == 0 ? 1 : seed;
	}

	/** xorshift32: only 32-bit shifts/xors, so JS and eval produce identical sequences. **/
	public function int(max:Int):Int {
		state ^= state << 13;
		state ^= state >>> 17;
		state ^= state << 5;
		return (state & 0x7fffffff) % max;
	}
}

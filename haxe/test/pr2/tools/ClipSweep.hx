package pr2.tools;

import pr2.gameplay.debug.ClipSimulator;
import pr2.gameplay.debug.ClipSimulator.ClipArea;
import pr2.gameplay.debug.ClipSimulator.ClipAttempt;
import pr2.gameplay.player.LocalPlayerController;
import pr2.gameplay.player.LocalPlayerInput;
import pr2.level.BlockType;
import pr2.level.Level.LevelBlock;
import pr2.level.LevelDecoder;
import pr2.net.LevelDataClient;

/**
	Brute-forces stat and input combinations against inside corners (a floor
	meeting a wall) and reports every run in which the player's body ends up
	inside a solid tile.

	Without `--levels` it sweeps one built-in corner. With `--levels` it decodes
	saved server levels (see tools/fetch_levels.py), finds every inside corner
	in each, and sweeps each corner. Every run starts from a freshly built
	player and level, so after a clip the next combination starts clean.

	Runs the real `LocalPlayerController`, so results match in-game physics.
	See `tools/clip_sweep.sh --help` for usage.
**/
class ClipSweep {
	static var speeds:Array<Float> = [80, 90, 100];
	static var accels:Array<Float> = [50, 100];
	static var jumps:Array<Float> = [50, 75, 100];
	static var gravities:Array<Float> = [1];
	static var distances:Array<Float> = [for (i in 150...251) i];
	static var heights:Array<Float> = [0];
	static var jumpFrames:Array<Float> = [0, 1, 2, 3, 4];
	static var holds:Array<Float> = [8, 999];
	static var downModes:Array<Float> = [0, 1];
	static var moveStarts:Array<Float> = [0];
	static var turnFrames:Array<Float> = [-1];
	/** 0 = normal jump; 13-50 = super jump charged for that many frames. **/
	static var superCharges:Array<Float> = [0];
	static var dirs:Array<Float> = [1];
	static var frames:Int = 120;
	static var randomRuns:Int = 0;
	static var seed:Int = 1;
	static var pick:Int = -1;
	static var maxPrint:Int = 25;
	static var maxClipsPerCorner:Int = 0;
	static var traceRun:Bool = false;
	static var levelsArg:Null<String> = null;
	static var cornerFilter:Null<String> = null;
	static var explicit:Map<String, Bool> = new Map();

	static var skipped:Int = 0;

	public static function main():Void {
		if (!parseArgs(argv())) {
			return;
		}
		var arenas:Array<Arena>;
		if (levelsArg != null) {
			applyLevelDefaults();
			arenas = loadLevelArenas(levelsArg);
			if (arenas.length == 0) {
				out("No inside corners found in the given levels.");
				return;
			}
		} else {
			arenas = [for (d in dirs) Arena.synthetic(Std.int(d))];
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
		var onClip = function(arena:Arena, c:Case, r:Result):Void {
			clips++;
			arena.clips++;
			tally("dir", c.dir == 1 ? "right" : "left");
			tally("speed", Std.string(c.speed));
			tally("accel", Std.string(c.accel));
			tally("jump", Std.string(c.jump));
			tally("gravity", Std.string(c.gravity));
			if (c.script == null) {
				tally("hold", Std.string(c.hold));
				tally("down", c.down ? "1" : "0");
				tally("super", Std.string(c.superCharge));
				tally("move-start", Std.string(c.moveStart));
				tally("turn", Std.string(c.turnFrame));
			}
			if (printed < maxPrint) {
				printed++;
				var where = arena.source == null ? "" : '${arena.describe()}  ';
				out('CLIP ${where}frame=${r.frame} x=${r.x} y=${r.y} vx=${fmt(r.vx)} vy=${fmt(r.vy)}  ${c.describe()}');
				out('  reproduce: tools/clip_sweep.sh ${arena.args()}${c.args()} --trace');
			}
		};

		if (randomRuns > 0) {
			out('Running ${pick >= 0 ? 1 : randomRuns} random runs (seed $seed) over ${arenas.length} corner(s)...');
			var rng = new Rng(seed);
			for (index in 0...randomRuns) {
				// Every case is generated so --pick replays exactly the same inputs.
				var arena = arenas[rng.int(arenas.length)];
				var c = Case.random(rng, frames, arena);
				c.randomIndex = index;
				c.randomSeed = seed;
				c.randomCount = randomRuns;
				if (pick >= 0 && index != pick) continue;
				total++;
				var r = run(arena, c);
				if (r != null) onClip(arena, c, r);
			}
		} else {
			var perArena = speeds.length * accels.length * jumps.length * distances.length * heights.length * jumpFrames.length * holds.length
				* downModes.length * moveStarts.length * turnFrames.length * superCharges.length * (levelsArg != null && !explicit.exists("gravity") ? 1 : gravities.length);
			out('Running up to $perArena grid runs at each of ${arenas.length} corner(s)...');
			for (arena in arenas) {
				total += sweepArena(arena, onClip);
			}
		}
		if (clips > printed) {
			out('... ${clips - printed} more clipping runs not shown (raise --max-print)');
		}
		if (levelsArg != null) {
			printLevelSummary(arenas);
		}
		var skipNote = skipped > 0 ? ' ($skipped start positions skipped: inside blocks)' : "";
		out('Ran $total runs$skipNote; $clips clipped into solid blocks.');
		if (clips > 0) {
			out("Clipping runs by value:");
			for (stat in ["dir", "speed", "accel", "jump", "gravity", "hold", "down", "super", "move-start", "turn"]) {
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

	/** Every grid combination at one corner. Returns how many runs were made. **/
	static function sweepArena(arena:Arena, onClip:(Arena, Case, Result) -> Void):Int {
		var runs = 0;
		// A level's own gravity is used unless --gravity was given.
		var gravityList = arena.gravity != null && !explicit.exists("gravity") ? [arena.gravity] : gravities;
		for (g in gravityList) for (s in speeds) for (a in accels) for (j in jumps) for (d in distances) for (h in heights)
			for (ms in moveStarts) for (tf in turnFrames) for (sc in superCharges) for (jf in jumpFrames) for (hold in holds) for (down in downModes) {
				// A super jump ignores the normal jump timing: run it once, not once per jump frame/hold.
				if (sc > 0 && (jf != jumpFrames[0] || hold != holds[0])) continue;
				var c = new Case(arena.dir, g, s, a, j, d, h, Std.int(jf), Std.int(hold), down != 0, frames);
				c.moveStart = Std.int(ms);
				c.turnFrame = Std.int(tf);
				c.superCharge = Std.int(sc);
				runs++;
				var r = run(arena, c);
				if (r != null) {
					onClip(arena, c, r);
					if (maxClipsPerCorner > 0 && arena.clips >= maxClipsPerCorner) return runs;
				}
			}
		return runs;
	}

	/** One attempt through the shared core (pr2.gameplay.debug.ClipSimulator). **/
	static function run(arena:Arena, c:Case):Null<Result> {
		var halfWidth = LocalPlayerController.STANDING_WIDTH / 2;
		var startX = arena.wallFace - c.dir * (halfWidth + c.distance);
		var startY = arena.floorY - c.height;
		var attempt = new ClipAttempt(startX, startY, c.speed, c.accel, c.jump, c.gravity, c.dir, c.jumpFrame, c.hold, c.down, c.frames);
		attempt.script = c.script;
		attempt.moveStart = c.moveStart;
		attempt.turnFrame = c.turnFrame;
		attempt.superCharge = c.superCharge;
		var onFrame = traceRun ? function(f:Int, input:LocalPlayerInput, player:LocalPlayerController, inSolid:Bool):Void {
			out('f=$f in=${inputString(input)} x=${fmt(player.x)} y=${fmt(player.y)} vx=${fmt(player.vx)} vy=${fmt(player.vy)} grounded=${player.grounded} crouch=${player.crouching} bodyInSolid=$inSolid');
		} : null;
		var result = ClipSimulator.run(arena.area, attempt, false, onFrame);
		if (result.startBlocked) {
			skipped++;
			return null;
		}
		return result.clipped ? new Result(result.clipFrame, result.x, result.y, result.vx, result.vy) : null;
	}

	// ---- Real levels -------------------------------------------------------

	/**
		The defaults are sized for one corner. With levels there can be hundreds
		of corners, so any grid option not given on the command line uses a
		smaller list that still covers the pixel-exact approach distances.
	**/
	static function applyLevelDefaults():Void {
		if (!explicit.exists("speed")) speeds = [90, 100];
		if (!explicit.exists("accel")) accels = [50, 100];
		if (!explicit.exists("jump")) jumps = [75, 100];
		if (!explicit.exists("jump-frame")) jumpFrames = [0];
		if (!explicit.exists("hold")) holds = [8];
		if (!explicit.exists("down")) downModes = [1];
		if (!explicit.exists("dir")) dirs = [1, -1];
	}

	static function loadLevelArenas(arg:String):Array<Arena> {
		var files:Array<String> = [];
		for (path in arg.split(",")) {
			if (isDirectory(path)) {
				var names = listDirectory(path).filter(n -> StringTools.endsWith(n, ".txt"));
				names.sort(Reflect.compare);
				for (name in names) files.push(path + "/" + name);
			} else {
				files.push(path);
			}
		}
		var filter = parseCornerFilter();
		var arenas:Array<Arena> = [];
		for (file in files) {
			var source:LevelSource;
			try {
				source = LevelSource.load(file);
			} catch (error:Dynamic) {
				out('SKIP $file: ${Std.string(error)}');
				continue;
			}
			var found = 0;
			for (dir in dirs) {
				for (corner in source.findCorners(Std.int(dir))) {
					if (filter != null && (filter.x != corner.x || filter.y != corner.y || filter.dir != corner.dir)) continue;
					arenas.push(Arena.forCorner(source, corner));
					found++;
				}
			}
			source.cornerCount = found;
			out('Level ${source.label()}: $found inside corner(s)');
		}
		return arenas;
	}

	static function parseCornerFilter():Null<Corner> {
		if (cornerFilter == null) return null;
		var parts = cornerFilter.split(",");
		return new Corner(Std.parseInt(parts[0]), Std.parseInt(parts[1]), parts.length > 2 && (parts[2] == "left" || parts[2] == "-1") ? -1 : 1);
	}

	static function printLevelSummary(arenas:Array<Arena>):Void {
		var bySource:Array<LevelSource> = [];
		for (arena in arenas) {
			if (bySource.indexOf(arena.source) < 0) bySource.push(arena.source);
		}
		out("Per level:");
		for (source in bySource) {
			var clippingCorners = [for (a in arenas) if (a.source == source && a.clips > 0) a];
			var runs = 0;
			for (a in clippingCorners) runs += a.clips;
			var where = [for (a in clippingCorners) '${a.corner.x},${a.corner.y},${a.corner.dir == 1 ? "right" : "left"}(${a.clips})'];
			out('  ${source.label()}: ${clippingCorners.length}/${source.cornerCount} corners clip, $runs clipping runs'
				+ (where.length > 0 ? '  at ' + where.join(" ") : ""));
		}
	}

	// ---- Platform helpers --------------------------------------------------

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

	public static function readText(path:String):String {
		#if js
		return js.Syntax.code("require('fs').readFileSync({0}, 'utf8')", path);
		#else
		return sys.io.File.getContent(path);
		#end
	}

	static function isDirectory(path:String):Bool {
		#if js
		return js.Syntax.code("(function (p) { try { return require('fs').statSync(p).isDirectory(); } catch (e) { return false; } })({0})", path);
		#else
		return sys.FileSystem.exists(path) && sys.FileSystem.isDirectory(path);
		#end
	}

	static function listDirectory(path:String):Array<String> {
		#if js
		return js.Syntax.code("require('fs').readdirSync({0})", path);
		#else
		return sys.FileSystem.readDirectory(path);
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
			if (StringTools.startsWith(flag, "--")) explicit.set(flag.substr(2), true);
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
				case "--move-start": moveStarts = parseList(value);
				case "--turn": turnFrames = parseList(value);
				case "--super": superCharges = parseList(value);
				case "--dir": dirs = [for (d in value.split(",")) d == "left" || d == "-1" ? -1.0 : 1.0];
				case "--frames": frames = Std.parseInt(value);
				case "--random": randomRuns = Std.parseInt(value);
				case "--seed": seed = Std.parseInt(value);
				case "--pick": pick = Std.parseInt(value);
				case "--max-print": maxPrint = Std.parseInt(value);
				case "--levels": levelsArg = value;
				case "--corner": cornerFilter = value;
				case "--max-clips-per-corner": maxClipsPerCorner = Std.parseInt(value);
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
		out("Every list option takes 80 | 50,80,100 | 0:100:10 (inclusive range with step).");
		out("Defaults are for the built-in corner; [levels: ...] is the default with --levels.");
		out("  --speed L       speed stat (0-100)            default 80:100:10   [levels: 90,100]");
		out("  --accel L       acceleration stat (0-100)     default 50,100");
		out("  --jump L        jump stat (0-100)             default 50:100:25   [levels: 75,100]");
		out("  --gravity L     gravity multiplier            default 1           [levels: each level's own]");
		out("  --distance L    px from player edge to wall   default 150:250 (1 px steps)");
		out("  --height L      px of feet above the floor    default 0");
		out("  --jump-frame L  frame jump is first pressed   default 0:4         [levels: 0]");
		out("  --hold L        frames jump is held           default 8,999       [levels: 8]");
		out("  --down L        0 = never, 1 = hold down while airborne after the jump  default 0,1  [levels: 1]");
		out("  --dir L         right,left (which side the wall is on)  default right  [levels: right,left]");
		out("  --move-start L  frame the direction starts being held (jump/stand in place first)  default 0");
		out("  --turn L        frame the held direction flips, -1 = never  default -1");
		out("  --super L       0 = normal jump, 13-50 = super jump: hold down that many frames, release  default 0");
		out("  --frames N      frames simulated per run      default 120");
		out("  --levels P      level .txt files or folders (comma-separated), as saved by");
		out("                  tools/fetch_levels.py; sweeps every inside corner in each level");
		out("  --corner X,Y,D  with --levels, only the corner whose air tile is X,Y (D = right/left)");
		out("  --max-clips-per-corner N  move on to the next corner after N clips (default 0 = never)");
		out("  --random N      instead of the grid, run N random stat/input sequences");
		out("  --seed N        seed for --random             default 1");
		out("  --pick K        with --random, run only random case #K (as printed by a CLIP)");
		out("  --max-print N   clipping runs to print        default 25");
		out("  --trace         print every frame (use with a single combination)");
		out("Every run starts from a fresh player and level, so a clip never carries over.");
		out("A run clips when the body point (x, y-15) lands inside a solid tile.");
	}
}

/** An inside corner: the air tile in the crook, and which side the wall is on. **/
private class Corner {
	public final x:Int;
	public final y:Int;
	public final dir:Int;

	public function new(x:Int, y:Int, dir:Int) {
		this.x = x;
		this.y = y;
		this.dir = dir;
	}
}

/** A decoded server level, kept as raw block data so each run can rebuild its own copy. **/
private class LevelSource {
	public final path:String;
	public final id:Int;
	public final title:String;
	public final gravity:Float;
	public var cornerCount:Int = 0;

	public final blocks:Array<LevelBlock>;
	final solid:Map<String, Bool> = new Map();

	function new(path:String, id:Int, title:String, gravity:Float, blocks:Array<LevelBlock>) {
		this.path = path;
		this.id = id;
		this.title = title;
		this.gravity = gravity;
		this.blocks = blocks;
		for (block in blocks) {
			if (!block.isMarker() && block.type.isSolid()) solid.set(key(block.x, block.y), true);
		}
	}

	/** Same steps as GamePage.onLevelData: verify/sanitize, decode blocks, take the level's gravity. **/
	public static function load(path:String):LevelSource {
		var name = path.split("/").pop();
		var digits = ~/^(\d+)/;
		var id = digits.match(name) ? Std.parseInt(digits.matched(1)) : 0;
		var body = StringTools.trim(ClipSweep.readText(path));
		var data = LevelDataClient.parse(body, id, 0);
		if (data.data == "") throw "level has no block data";
		var level = LevelDecoder.decode(data.data);
		return new LevelSource(path, data.levelId != 0 ? data.levelId : id, data.title, data.gravity, level.blocks);
	}

	public function label():String {
		return '$id "$title"';
	}

	public inline function isSolid(x:Int, y:Int):Bool {
		return solid.exists(key(x, y));
	}

	/**
		Air tile with air above it (room to stand), a solid floor below, and a
		solid wall beside it. The wall need not continue below the floor; the
		sweep's physics decides whether a corner can actually be clipped.
	**/
	public function findCorners(dir:Int):Array<Corner> {
		var corners:Array<Corner> = [];
		var seen:Map<String, Bool> = new Map();
		for (block in blocks) {
			if (block.isMarker() || !block.type.isSolid()) continue;
			// Treat every solid block as a potential floor tile under the corner.
			var cx = block.x;
			var cy = block.y - 1;
			var k = key(cx, cy);
			if (seen.exists(k)) continue;
			seen.set(k, true);
			if (!isSolid(cx, cy) && !isSolid(cx, cy - 1) && isSolid(cx + dir, cy)) {
				corners.push(new Corner(cx, cy, dir));
			}
		}
		corners.sort((a, b) -> a.y != b.y ? a.y - b.y : a.x - b.x);
		return corners;
	}

	static inline function key(x:Int, y:Int):String {
		return x + "," + y;
	}
}

/** Where a sweep runs: the built-in corner, or a cropped area around one corner of a real level. **/
private class Arena {
	static inline var TILE:Int = 30;
	/**
		Crop around a level corner: CROP_BACK tiles on the approach side (the
		longest default run-up is about 9 tiles), CROP_PAST beyond the wall face,
		CROP_UP above and CROP_DOWN below.
	**/
	static inline var CROP_BACK:Int = 12;
	static inline var CROP_PAST:Int = 4;
	static inline var CROP_UP:Int = 10;
	static inline var CROP_DOWN:Int = 4;

	public final dir:Int;
	/** Pixel x of the wall's face, and pixel y of the floor's top. **/
	public final wallFace:Float;
	public final floorY:Float;
	public final area:ClipArea;
	public final source:Null<LevelSource>;
	public final corner:Null<Corner>;
	public final gravity:Null<Float>;
	public var clips:Int = 0;

	function new(dir:Int, wallFace:Float, floorY:Float, area:ClipArea, source:Null<LevelSource>, corner:Null<Corner>) {
		this.dir = dir;
		this.wallFace = wallFace;
		this.floorY = floorY;
		this.area = area;
		this.source = source;
		this.corner = corner;
		this.gravity = source == null ? null : source.gravity;
	}

	/** dir=1: floor on the left, wall on the right; dir=-1: the mirror image. **/
	public static function synthetic(dir:Int):Arena {
		var cols = 22, rows = 20, floorRow = 17, thickness = 3;
		var wallStart = dir == 1 ? cols - thickness : 0;
		var blocks:Array<LevelBlock> = [];
		for (col in 0...cols) {
			var inWall = col >= wallStart && col < wallStart + thickness;
			for (row in 0...rows) {
				if (inWall || row >= floorRow) blocks.push(new LevelBlock(col, row, BlockType.Basic));
			}
		}
		return new Arena(dir, (dir == 1 ? wallStart : thickness) * TILE, floorRow * TILE, new ClipArea(blocks, 0, 0, cols - 1, rows - 1), null,
			null);
	}

	public static function forCorner(source:LevelSource, corner:Corner):Arena {
		var minX = corner.dir == 1 ? corner.x - CROP_BACK : corner.x - CROP_PAST;
		var maxX = corner.dir == 1 ? corner.x + CROP_PAST : corner.x + CROP_BACK;
		var wallFace = (corner.dir == 1 ? corner.x + 1 : corner.x) * TILE;
		var area = new ClipArea(source.blocks, minX, corner.y - CROP_UP, maxX, corner.y + CROP_DOWN);
		return new Arena(corner.dir, wallFace, (corner.y + 1) * TILE, area, source, corner);
	}

	public function describe():String {
		return 'level=${source.label()} corner=${corner.x},${corner.y},${dir == 1 ? "right" : "left"}';
	}

	/** Leading command-line arguments that select this arena again. **/
	public function args():String {
		if (source == null) return "";
		return '--levels ${source.path} --corner ${corner.x},${corner.y},${dir == 1 ? "right" : "left"} ';
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
	public var moveStart:Int = 0;
	public var turnFrame:Int = -1;
	public var superCharge:Int = 0;

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
		var moves = (moveStart > 0 ? ' moveStart=$moveStart' : "") + (turnFrame >= 0 ? ' turn=$turnFrame' : "");
		var launch = superCharge > 0 ? 'super=$superCharge' : 'jumpFrame=$jumpFrame hold=$hold';
		return base + '$moves $launch down=${down ? 1 : 0}';
	}

	/** Arguments that replay this case; a random case is replayed by index. **/
	public function args():String {
		if (script != null) {
			return '--random $randomCount --seed $randomSeed --pick $randomIndex --frames $frames';
		}
		return '--dir ${dir == 1 ? "right" : "left"} --speed $speed --accel $accel --jump $jump --gravity $gravity --distance $distance --height $height'
			+ ' --jump-frame $jumpFrame --hold $hold --down ${down ? 1 : 0} --move-start $moveStart --turn $turnFrame --super $superCharge'
			+ ' --frames $frames';
	}

	public static function random(rng:Rng, frames:Int, arena:Arena):Case {
		// Real levels use their own gravity; the built-in corner tries a few.
		var gravity:Float = arena.gravity != null ? arena.gravity : [0.5, 1, 1, 1.5, 2][rng.int(5)];
		var c = new Case(arena.dir, gravity, rng.int(101), rng.int(101), rng.int(101), rng.int(240), rng.int(150), 0, 0, false, frames);
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

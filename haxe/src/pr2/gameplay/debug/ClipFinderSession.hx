package pr2.gameplay.debug;

import openfl.display.DisplayObjectContainer;
import openfl.display.Shape;
import openfl.events.MouseEvent;
import openfl.geom.Point;
import pr2.character.Character;
import pr2.character.LocalCharacter;
import pr2.gameplay.debug.ClipFinder.ClipFinderSettings;
import pr2.gameplay.debug.ClipSimulator.ClipAttempt;
import pr2.gameplay.debug.ClipSimulator.ClipHats;
import pr2.gameplay.Items;
import pr2.level.Level;

/**
	Debug-only Clip Finder, toggled in a race with F9+C+D (see Course).

	Opens a panel with stat ranges that default to the local player's current
	stats, then searches stat/input combinations from where the player is
	standing in a cropped copy of the level, a few attempts per frame so the
	race keeps running. Every attempt starts from a fresh simulated player.
	A translucent ghost of the player replays the selected clip on a loop.

	The search never touches the real player, blocks or network state. Only
	"Replay on me" does: it moves the real player to the clip's start, gives it
	the clip's stats and feeds the clip's inputs instead of the keyboard, then
	restores the player's stats.
**/
class ClipFinderSession {
	/** Simulation time allowed per game frame, so the race keeps its frame rate. **/
	public static inline var FRAME_BUDGET_SECONDS:Float = 0.006;
	/** LocalCharacter.setHats: the moon hat multiplies gravity by 0.85. **/
	static inline var MOON_GRAVITY:Float = 0.85;

	final level:Level;
	final player:LocalCharacter;
	final panelLayer:DisplayObjectContainer;
	final ghostLayer:DisplayObjectContainer;
	final panel:ClipFinderPanel;
	final ghost:ClipGhost;
	var finder:Null<ClipFinder> = null;
	/** Clips from the latest search; kept after Stop so Prev/Next still work. **/
	var clips:Array<ClipFinder.FoundClip> = [];
	var shownClips:Int = 0;
	var selectedClip:Int = -1;
	public var closed(default, null):Bool = false;
	public var onClosed:Null<Void->Void>;

	public function new(level:Level, player:LocalCharacter, panelLayer:DisplayObjectContainer, ghostLayer:DisplayObjectContainer) {
		this.level = level;
		this.player = player;
		this.panelLayer = panelLayer;
		this.ghostLayer = ghostLayer;
		var state = player.stateSnapshot();
		panel = new ClipFinderPanel(state.speedStat, state.accelerationStat, state.jumpStat);
		panel.x = 8;
		panel.y = 4;
		panel.onStart = start;
		panel.onStop = stopSearch;
		panel.onClose = close;
		panel.onShowClip = showClip;
		panel.onReplay = startReplay;
		panel.onTarget = toggleTargetPicking;
		panel.onScan = startScan;
		panel.onRoute = startRoute;
		panelLayer.addChild(panel);
		ghost = new ClipGhost(player);
		ghost.courseRotation = () -> player.controller.courseRotation;
		ghostLayer.addChild(ghost.character);
		var hats = ClipHats.from(player.controller).names();
		if (player.hasHatFlag(Character.MOON)) hats.push("moon");
		panel.setStatus(state.courseRotation != 0 ? "Course is rotated." : (hats.length == 0 ? "Ready." : 'Ready (hats: ${hats.join(", ")})'));
	}

	function start():Void {
		var state = player.stateSnapshot();
		if (state.courseRotation != 0) {
			panel.setStatus("Only works while the course is upright.");
			return;
		}
		var dirs:Array<Int> = [];
		if (panel.rightBox.selected) dirs.push(1);
		if (panel.leftBox.selected) dirs.push(-1);
		if (dirs.length == 0) {
			panel.setStatus("Tick Left and/or Right.");
			return;
		}
		// Same gravity and hat physics as the real player: the moon hat lowers
		// gravity (LocalCharacter.setHats), the other hats are controller flags.
		var gravity = level.gravity * (player.hasHatFlag(Character.MOON) ? MOON_GRAVITY : 1);
		var settings = new ClipFinderSettings(Math.round(state.x), Math.round(state.y), gravity, panel.speedRow.range(),
			panel.accelRow.range(), panel.jumpRow.range());
		settings.hats = ClipHats.from(player.controller);
		settings.dirs = dirs;
		settings.downModes = panel.downBox.selected ? [false, true] : [false];
		settings.normalJumps = panel.normalJumpRow.enabled;
		settings.maxJumpFrame = panel.normalJumpRow.upTo();
		settings.superCharges = panel.superJumpRow.enabled ? [for (c in ClipAttempt.MIN_SUPER_CHARGE...panel.superJumpRow.upTo() + 1) c] : [];
		if (!settings.normalJumps && settings.superCharges.length == 0) {
			panel.setStatus("Tick Normal jump and/or Super jump.");
			return;
		}
		// Delayed move and air turn add to the default (move at once, never turn).
		settings.moveStarts = panel.delayedMoveRow.enabled ? [for (m in 0...panel.delayedMoveRow.upTo() + 1) m] : [0];
		settings.turnFrames = panel.airTurnRow.enabled ? [-1].concat([for (t in 1...panel.airTurnRow.upTo() + 1) t]) : [-1];
		if (panel.anyFrameBox.selected) {
			// Every frame of the run, every super jump charge: far too many to try
			// them all, so attempts are random and the search runs until Stop.
			var last = settings.frames - 1;
			settings.anyFrame = true;
			settings.seed = randomSeed();
			settings.maxJumpFrame = last;
			if (settings.superCharges.length > 0) {
				settings.superCharges = [for (c in ClipAttempt.MIN_SUPER_CHARGE...ClipAttempt.MAX_SUPER_CHARGE + 1) c];
			}
			if (panel.delayedMoveRow.enabled) settings.moveStarts = [for (m in 0...last + 1) m];
			if (panel.airTurnRow.enabled) settings.turnFrames = [-1].concat([for (t in 1...last + 1) t]);
		}
		// "Aim at target": the same search, but only clips into the picked block count.
		if (panel.aimBox.selected) {
			if (targetTileX == null) {
				panel.setStatus("Pick a target block first (Target button).");
				return;
			}
			settings.targetTileX = targetTileX;
			settings.targetTileY = targetTileY;
		}
		stopReplay();
		finder = ClipSimulator.keepRealItem(() -> new ClipFinder(liveBlocks(), settings));
		clips = finder.clips;
		clipPortals = [];
		scanner = null;
		planner = null;
		routeText = null;
		shownClips = 0;
		selectedClip = -1;
		ghost.stop();
		panel.setClipCount(0);
		panel.setRunning(true);
		updateStatus();
	}

	function stopSearch():Void {
		if (planner != null) {
			stopRoute();
			return;
		}
		if (scanner != null) {
			stopScan();
			return;
		}
		if (finder == null) return;
		panel.setRunning(false);
		updateStatus(true);
		finder = null;
	}

	/** Called once per simulation frame by the course. **/
	public function tick():Void {
		if (closed) return;
		// Simulated items share the game's one item-uses store; keep the real player's.
		ClipSimulator.keepRealItem(() -> {
			tickScan();
			tickRoute();
			tickFinder();
			return true;
		});
		ghost.tick();
	}

	function tickFinder():Void {
		var search = finder;
		if (search != null && !search.done) {
			var deadline = haxe.Timer.stamp() + FRAME_BUDGET_SECONDS;
			search.step(1000, () -> haxe.Timer.stamp() > deadline);
			if (search.clips.length != shownClips) {
				shownClips = search.clips.length;
				panel.setClipCount(shownClips);
				// Start the ghost on the first clip; later clips are a Next click away.
				if (selectedClip < 0) showClip(0);
			}
			updateStatus();
			if (search.done) panel.setRunning(false);
		}
	}

	function showClip(index:Int):Void {
		if (index < 0 || index >= clips.length) return;
		stopReplay();
		selectedClip = index;
		var found = clips[index];
		var recorded = found.run.ghost;
		if (recorded != null) ghost.play(recorded);
		var portal = index < clipPortals.length ? clipPortals[index] : null;
		if (routeText != null) {
			panel.setClipInfo(index, 'Route: $routeText');
		} else if (portal != null) {
			panel.setClipInfo(index, 'Corner ${portal.corner.x},${portal.corner.y}: ${portalOutcome(portal)}. ${found.attempt.describe()}.');
		} else {
			panel.setClipInfo(index, '${found.attempt.describe()}, clips on frame ${found.run.clipFrame + 1}. Replaying on a loop.');
		}
	}

	// ---- Level scan ------------------------------------------------------------

	var scanner:Null<ClipScanner> = null;
	var overlay:Null<ClipScanOverlay> = null;
	/** For clips found by the scan, the portal each came from (same index as `clips`). **/
	var clipPortals:Array<Null<ClipScanner.ClipPortal>> = [];
	var drawnPortals:Int = 0;
	var drawnSolid:Int = 0;

	/** "Scan level": every corner in the level, with your stats, nearest first. **/
	function startScan():Void {
		var state = player.stateSnapshot();
		if (state.courseRotation != 0) {
			panel.setStatus("Only works while the course is upright.");
			return;
		}
		stopReplay();
		finder = null;
		planner = null;
		routeText = null;
		var gravity = level.gravity * (player.hasHatFlag(Character.MOON) ? MOON_GRAVITY : 1);
		var settings = new ClipScanner.ClipScanSettings(state.speedStat, state.accelerationStat, state.jumpStat, gravity);
		settings.hats = ClipHats.from(player.controller);
		settings.originX = state.x;
		settings.originY = state.y;
		// Holding a Laser Gun: also try laser recoil clips at each corner.
		settings.laser = player.controller.itemId == Items.LASER_GUN;
		scanner = new ClipScanner(liveBlocks(), settings);
		clips = [];
		clipPortals = [];
		shownClips = 0;
		selectedClip = -1;
		drawnPortals = 0;
		drawnSolid = 0;
		ghost.stop();
		if (overlay == null) overlay = new ClipScanOverlay();
		overlay.redraw([], []);
		ghostLayer.addChild(overlay);
		panel.setClipCount(0);
		panel.setRunning(true);
		updateScanStatus();
	}

	function stopScan():Void {
		if (scanner == null) return;
		panel.setRunning(false);
		updateScanStatus(true);
		scanner = null;
	}

	function tickScan():Void {
		var scan = scanner;
		if (scan == null) return;
		if (!scan.done) {
			var deadline = haxe.Timer.stamp() + FRAME_BUDGET_SECONDS;
			scan.step(1000, () -> haxe.Timer.stamp() > deadline);
		}
		while (clips.length < scan.portals.length) {
			var portal = scan.portals[clips.length];
			clips.push(new ClipFinder.FoundClip(portal.attempt, portal.run));
			clipPortals.push(portal);
		}
		if (clips.length != shownClips) {
			shownClips = clips.length;
			panel.setClipCount(shownClips);
			if (selectedClip < 0) showClip(0);
		}
		if (overlay != null && (scan.portals.length != drawnPortals || scan.solidCorners.length != drawnSolid)) {
			drawnPortals = scan.portals.length;
			drawnSolid = scan.solidCorners.length;
			overlay.redraw(scan.portals, scan.solidCorners);
		}
		updateScanStatus();
		if (scan.done) {
			panel.setRunning(false);
			scanner = null;
		}
	}

	function updateScanStatus(stopped:Bool = false):Void {
		var scan = scanner;
		if (scan == null) return;
		var total = scan.corners.length;
		var found = scan.portals.length;
		if (scan.done) {
			panel.setStatus('Scan done: $found of $total corners clip');
		} else {
			var verb = stopped ? "Stopped at" : "Scanning";
			panel.setStatus('$verb corner ${Std.int(Math.min(scan.cornerIndex + 1, total))}/$total, $found clip');
		}
	}

	static function portalOutcome(portal:ClipScanner.ClipPortal):String {
		var exitX = portal.exitX, exitY = portal.exitY;
		return switch (ClipScanOverlay.kindOf(portal)) {
			case PassesThrough: 'passes through, lands at tile ${ClipSimulator.tileOf(exitX)},${ClipSimulator.tileOf(exitY - 1)}';
			case PopsBack: 'clips in but pops back out on the same side';
			case FallsAway: 'clips in and falls out of the level';
		}
	}

	// ---- Route to target -----------------------------------------------------

	var planner:Null<ClipRoutePlanner> = null;
	/** The shown route's steps, while the clip list holds a route. **/
	var routeText:Null<String> = null;

	/**
		"Route to target": plans moves from where you stand to the target block
		with your stats, clipping through blocks when that is the way there. The
		found route becomes the one clip in the list, so the ghost plays it and
		"Replay on me" runs it on you.
	**/
	function startRoute():Void {
		var state = player.stateSnapshot();
		if (state.courseRotation != 0) {
			panel.setStatus("Only works while the course is upright.");
			return;
		}
		var tx = targetTileX, ty = targetTileY;
		if (tx == null || ty == null) {
			panel.setStatus("Pick a target block first (Target button).");
			return;
		}
		stopReplay();
		finder = null;
		scanner = null;
		var gravity = level.gravity * (player.hasHatFlag(Character.MOON) ? MOON_GRAVITY : 1);
		var settings = new ClipRoutePlanner.RouteSettings(Math.round(state.x), Math.round(state.y), state.speedStat, state.accelerationStat,
			state.jumpStat, gravity, tx, ty);
		settings.hats = ClipHats.from(player.controller);
		settings.items = ClipSimulator.ClipItems.from(player.controller);
		planner = ClipSimulator.keepRealItem(() -> new ClipRoutePlanner(liveBlocks(), settings));
		clips = [];
		clipPortals = [];
		routeText = null;
		shownClips = 0;
		selectedClip = -1;
		ghost.stop();
		panel.setClipCount(0);
		panel.setRunning(true);
		updateRouteStatus();
	}

	function stopRoute():Void {
		if (planner == null) return;
		panel.setRunning(false);
		updateRouteStatus(true);
		planner = null;
	}

	function tickRoute():Void {
		var plan = planner;
		if (plan == null) return;
		if (!plan.done) {
			var deadline = haxe.Timer.stamp() + FRAME_BUDGET_SECONDS;
			plan.step(1000, () -> haxe.Timer.stamp() > deadline);
		}
		updateRouteStatus();
		if (!plan.done) return;
		panel.setRunning(false);
		planner = null;
		var found = plan.foundClip();
		if (found == null) return;
		routeText = plan.describeRoute();
		clips = [found];
		clipPortals = [null];
		shownClips = 1;
		panel.setClipCount(1);
		showClip(0);
	}

	function updateRouteStatus(stopped:Bool = false):Void {
		var plan = planner;
		if (plan == null) return;
		var route = plan.route;
		if (route != null) {
			panel.setStatus('Route found: ${route.steps.length} steps, ${route.clips} clip${route.clips == 1 ? "" : "s"}');
		} else if (plan.done) {
			panel.setStatus('No route found (${plan.spotsExplored} spots tried).');
			// Why the moves ran out, in the info box under the buttons.
			var why = plan.rejectionSummary();
			panel.setInfo('No route: ${plan.spotsExplored} spots, ${plan.simulations} moves tried.' + (why == "" ? "" : ' Moves dropped: $why.'));
		} else {
			panel.setStatus('${stopped ? "Stopped" : "Planning"}: ${plan.spotsExplored} spots, ${plan.simulations} runs');
		}
	}

	function updateStatus(stopped:Bool = false):Void {
		var search = finder;
		if (search == null) return;
		if (search.blockedStart) {
			panel.setStatus("Can't start here: inside a block.");
			return;
		}
		var verb = search.done ? "Done" : (stopped ? "Stopped" : "Testing");
		var clipText = '${search.clipCount} clip${search.clipCount == 1 ? "" : "s"}';
		var tried = search.total > 0 ? '${search.tested}/${search.total}' : '${search.tested} random';
		panel.setStatus('$verb $tried, $clipText');
	}

	// ---- Target block --------------------------------------------------------

	/** Converts a stage (mouse) point to a world point; set by Course. **/
	public var stageToWorld:Null<Float->Float->Point>;

	var targetTileX:Null<Int> = null;
	var targetTileY:Null<Int> = null;
	var picking:Bool = false;
	var targetMarker:Null<Shape> = null;

	/** Button: start picking, cancel picking, or clear the current target. **/
	function toggleTargetPicking():Void {
		if (picking) {
			setPicking(false);
			panel.targetButton.label = "Target: any block";
			panel.setStatus("Target unchanged.");
		} else if (targetTileX != null) {
			setTarget(null, null);
			panel.setStatus("Clips into any block count.");
		} else {
			setPicking(true);
			panel.targetButton.label = "Click a block...";
			panel.setStatus("Click the block to clip into.");
		}
	}

	function setPicking(value:Bool):Void {
		if (picking == value) return;
		picking = value;
		var stage = panelLayer.stage;
		if (stage == null) return;
		if (value) {
			stage.addEventListener(MouseEvent.CLICK, onStageClick);
		} else {
			stage.removeEventListener(MouseEvent.CLICK, onStageClick);
		}
	}

	function onStageClick(event:MouseEvent):Void {
		// Clicks on the panel itself (including the button that started picking) don't pick.
		if (panel.hitTestPoint(event.stageX, event.stageY, false)) return;
		pickAt(event.stageX, event.stageY);
	}

	/** Picks the solid block under a stage point as the target. Returns false if there is none. **/
	public function pickAt(stageX:Float, stageY:Float):Bool {
		if (!picking || stageToWorld == null) return false;
		var world = stageToWorld(stageX, stageY);
		var tx = ClipSimulator.tileOf(world.x);
		var ty = ClipSimulator.tileOf(world.y);
		var block = level.blockAt(tx, ty);
		if (block == null || !block.type.isSolid()) {
			panel.setStatus('No solid block at $tx,$ty. Click a block.');
			return false;
		}
		setPicking(false);
		setTarget(tx, ty);
		// Picking a block means aiming at it; untick "Aim at target" to count every clip again.
		panel.aimBox.selected = true;
		panel.setStatus('Aiming at block $tx,$ty.');
		return true;
	}

	function setTarget(tx:Null<Int>, ty:Null<Int>):Void {
		targetTileX = tx;
		targetTileY = ty;
		if (targetMarker != null && targetMarker.parent != null) targetMarker.parent.removeChild(targetMarker);
		targetMarker = null;
		if (tx == null || ty == null) {
			panel.targetButton.label = "Target: any block";
			panel.aimBox.selected = false;
			return;
		}
		panel.targetButton.label = 'Target $tx,$ty (clear)';
		// Red outline on the chosen block, in world space with the ghost.
		var t = ClipSimulator.TILE;
		var marker = new Shape();
		marker.graphics.lineStyle(3, 0xFF2222, 0.9);
		marker.graphics.drawRect(tx * t, ty * t, t, t);
		ghostLayer.addChild(marker);
		targetMarker = marker;
	}

	/**
		The race's blocks as they are now: mines (and bricks, crumbles...) that
		were already blown up are gone from the live list, and mines placed with
		the mine item are in it. It is copied so a search keeps seeing the level
		as it was when the search started.
	**/
	function liveBlocks():Array<pr2.level.Level.LevelBlock> {
		return level.blocks.copy();
	}

	/** Tests replace this to make "Any frame" searches reproducible. **/
	public static var randomSeed:Void->Int = () -> 1 + Std.random(0x3fffffff);

	// ---- Replay on the real player ----------------------------------------

	/**
		Puts the real player at the clip's start with the clip's stats; the
		course then feeds `replayInput` instead of the keyboard. Set by Course,
		which returns false when the race isn't running (nothing to replay into).
	**/
	public var onBeginReplay:Null<ClipAttempt->Bool>;

	var replay:Null<ClipAttempt> = null;
	var replayFrame:Int = 0;
	var replayLength:Int = 0;
	var savedSpeed:Float = 0;
	var savedAccel:Float = 0;
	var savedJump:Float = 0;

	public var replaying(get, never):Bool;
	inline function get_replaying():Bool return replay != null;

	function startReplay():Void {
		if (replaying) {
			stopReplay();
			return;
		}
		if (selectedClip < 0 || selectedClip >= clips.length) return;
		var found = clips[selectedClip];
		var state = player.stateSnapshot();
		savedSpeed = state.speedStat;
		savedAccel = state.accelerationStat;
		savedJump = state.jumpStat;
		if (onBeginReplay == null || !onBeginReplay(found.attempt)) {
			panel.setStatus("Replay needs the race to be running.");
			return;
		}
		applyStats(found.attempt.speed, found.attempt.accel, found.attempt.jump);
		replay = found.attempt;
		replayFrame = 0;
		// The idle settle frame, then the same frames the ghost recorded.
		replayLength = found.run.ghost == null ? found.attempt.frames + 1 : found.run.ghost.length;
		panel.replayButton.label = "Stop replay";
		// Restart the ghost so it runs alongside the real player. Its first pose is
		// after the settle frame, which the player plays on the next game frame.
		if (found.run.ghost != null) ghost.play(found.run.ghost, 1);
	}

	/**
		The input for this frame while a replay runs, else null (use the keyboard).
		Frame 0 is the idle settle frame the search also starts with.
	**/
	public function replayInput(grounded:Bool):Null<pr2.gameplay.player.LocalPlayerInput> {
		var attempt = replay;
		if (attempt == null || closed) return null;
		if (replayFrame >= replayLength) {
			stopReplay();
			return null;
		}
		var input = replayFrame == 0 ? new pr2.gameplay.player.LocalPlayerInput() : attempt.inputAt(replayFrame - 1, grounded);
		replayFrame++;
		return input;
	}

	function stopReplay():Void {
		if (replay == null) return;
		replay = null;
		applyStats(savedSpeed, savedAccel, savedJump);
		panel.replayButton.label = "Replay on me";
	}

	/** setStats rebuilds speed from the stat, so re-apply the cowboy hat's floor (as the search does). **/
	function applyStats(speed:Float, accel:Float, jump:Float):Void {
		player.controller.setStats(speed, accel, jump);
		if (player.controller.cowboyHatActive) player.controller.ensureCowboyStats();
	}

	public function close():Void {
		if (closed) return;
		stopReplay();
		setPicking(false);
		setTarget(null, null);
		scanner = null;
		planner = null;
		if (overlay != null) overlay.dispose();
		overlay = null;
		closed = true;
		finder = null;
		ghost.dispose();
		panel.dispose();
		if (onClosed != null) onClosed();
		onClosed = null;
	}
}

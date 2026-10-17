package pr2.gameplay.debug;

import openfl.events.Event;
import openfl.ui.Keyboard;
import pr2.character.Character;
import pr2.gameplay.Course;
import pr2.gameplay.LevelConfig;
import pr2.gameplay.debug.ClipFinder.ClipFinderSettings;
import pr2.gameplay.debug.ClipFinder.StatRange;
import pr2.gameplay.debug.ClipSimulator.ClipArea;
import pr2.gameplay.debug.ClipSimulator.ClipAttempt;
import pr2.gameplay.debug.ClipSimulator.ClipHats;
import pr2.gameplay.debug.ClipScanner.ClipScanSettings;
import pr2.gameplay.debug.ClipScanOverlay.PortalKind;
import pr2.level.BlockType;
import pr2.level.Level.LevelBlock;
import pr2.level.LevelDecoder;
import pr2.net.ServerLevelData;

/** Debug Clip Finder: simulation core, search, ghost replay and the F9+C+D panel. */
@:access(pr2.gameplay.Course)
@:access(pr2.level.LevelRenderer)
@:access(pr2.gameplay.debug.ClipFinderSession)
@:access(pr2.gameplay.debug.ClipGhost)
@:access(pr2.gameplay.debug.ClipFinderPanel)
@:access(pr2.gameplay.debug.ClipScanner)
class ClipFinderTest {
	private static var assertions:Int = 0;
	private static var course:Null<Course> = null;

	/** Wall face of the test corner (wall in columns 19-21) and the floor top (row 17). */
	private static inline var WALL_FACE:Float = 570;
	private static inline var FLOOR_Y:Float = 510;
	/** A start 202 px from the wall that clips with speed 90 / accel 50 / jump 75. */
	private static inline var CLIP_START_X:Float = WALL_FACE - 10 - 202;

	public static function main():Void {
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testKnownAttemptClipsThroughCorner", testKnownAttemptClipsThroughCorner);
		if (pr2.DeterministicTestMode.finishSmokeSuite("ClipFinderTest")) return;
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testSlowAttemptLandsInCorner", testSlowAttemptLandsInCorner);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testRecordedRunKeepsTailAfterClip", testRecordedRunKeepsTailAfterClip);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testStartInsideBlockIsReported", testStartInsideBlockIsReported);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testFinderWalksEveryCombination", testFinderWalksEveryCombination);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testHatsChangeSimulatedPhysics", testHatsChangeSimulatedPhysics);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testSuperJumpChargesThenLaunches", testSuperJumpChargesThenLaunches);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testDelayedMoveJumpsInPlaceFirst", testDelayedMoveJumpsInPlaceFirst);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testAirTurnFlipsDirection", testAirTurnFlipsDirection);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testFinderSearchesMoveOptions", testFinderSearchesMoveOptions);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testSuperJumpCanStartOnAnyFrame", testSuperJumpCanStartOnAnyFrame);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testAnyFrameSearchIsRandomAndRunsUntilStopped", testAnyFrameSearchIsRandomAndRunsUntilStopped);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testAreaGrowsToFollowThePlayer", testAreaGrowsToFollowThePlayer);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testAreaUsesWholeLevelForMapEdges", testAreaUsesWholeLevelForMapEdges);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testTargetBlockFiltersClips", testTargetBlockFiltersClips);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testScannerFindsCorners", testScannerFindsCorners);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testScannedClipLandsPastTheWall", testScannedClipLandsPastTheWall);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testScannedClipWithNothingToLandOnFallsAway", testScannedClipWithNothingToLandOnFallsAway);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testScannerMarksCornersItCannotClip", testScannerMarksCornersItCannotClip);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testStatRangeValues", testStatRangeValues);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testGhostLoopsBackToStart", testGhostLoopsBackToStart);
		// The panel tests share one started race; building a Course is fixture
		// setup, not Clip Finder behaviour, so it is kept out of their timing.
		course = raceCourse();
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testComboTogglesPanelInRace", testComboTogglesPanelInRace);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testComboWorksPressedOneAfterAnother", testComboWorksPressedOneAfterAnother);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testChatCommandTogglesClipFinder", testChatCommandTogglesClipFinder);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testPanelSearchUsesPlayerStatsByDefault", testPanelSearchUsesPlayerStatsByDefault);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testReplayDrivesRealPlayerAlongTheClip", testReplayDrivesRealPlayerAlongTheClip);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testPickingTargetBlockInRace", testPickingTargetBlockInRace);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testScanFromPanel", testScanFromPanel);
		course.remove();
		course = null;
		trace('ClipFinderTest passed $assertions assertions');
	}

	private static function testKnownAttemptClipsThroughCorner():Void {
		var run = ClipSimulator.run(cornerArea(), clipAttempt(90));
		assertTrue(run.clipped, "fast landing in the corner clips");
		assertEquals(26, run.clipFrame, "clip frame");
		assertTrue(run.x > WALL_FACE, "body is past the wall face");
		assertTrue(run.y > FLOOR_Y + 10, "feet are more than 10 px into the floor");
		assertTrue(run.vx > 10 && run.vy > 10, "both speeds exceed 10 px/frame on the clip frame");
	}

	private static function testSlowAttemptLandsInCorner():Void {
		var run = ClipSimulator.run(cornerArea(), clipAttempt(50));
		assertEquals(false, run.clipped, "slow approach is caught by the wall");
		assertEquals(false, run.startBlocked, "start was free");
	}

	private static function testRecordedRunKeepsTailAfterClip():Void {
		var run = ClipSimulator.run(cornerArea(), clipAttempt(90), true);
		var ghost = run.ghost;
		assertTrue(ghost != null, "recorded frames");
		// Start pose + frames up to the clip + the tail after it.
		assertEquals(1 + run.clipFrame + 1 + ClipSimulator.GHOST_TAIL_FRAMES, ghost.length, "recording length");
		assertEquals(CLIP_START_X, ghost[0].x, "recording starts at the start position");
		assertEquals(false, ghost[run.clipFrame].inSolid, "frame before the clip is clear");
		assertEquals(true, ghost[run.clipFrame + 1].inSolid, "clip frame is inside the wall");
	}

	private static function testStartInsideBlockIsReported():Void {
		var attempt = new ClipAttempt(WALL_FACE + 45, FLOOR_Y, 90, 50, 75, 1, 1, 0, 8, true, 60);
		var run = ClipSimulator.run(cornerArea(), attempt);
		assertTrue(run.startBlocked, "start inside the wall is refused");
		assertEquals(false, run.clipped, "a refused start is not a clip");
	}

	private static function testFinderWalksEveryCombination():Void {
		var settings = new ClipFinderSettings(CLIP_START_X, FLOOR_Y, 1, new StatRange(89, 91), StatRange.fixed(50), StatRange.fixed(75));
		settings.dirs = [1];
		settings.maxJumpFrame = 0;
		settings.holds = [8];
		settings.downModes = [true];
		var finder = new ClipFinder(cornerBlocks(), settings);
		assertEquals(3, finder.total, "three speeds, one input script");
		finder.step(2);
		assertEquals(2, finder.tested, "step honours maxRuns");
		finder.step(100);
		assertTrue(finder.done, "search finished");
		assertEquals(3, finder.tested, "every combination tried once");
		assertTrue(finder.clipCount >= 1, "speed 90 clips");
		var found = finder.clips[0];
		assertTrue(found.run.ghost != null, "found clips are recorded for the ghost");
		var speeds = [for (clip in finder.clips) clip.attempt.speed];
		assertTrue(speeds.indexOf(90) >= 0, "the known clipping speed is among the clips");
	}

	private static function testHatsChangeSimulatedPhysics():Void {
		var plain = ClipSimulator.run(cornerArea(), clipAttempt(50), true);
		var attempt = clipAttempt(50);
		var hats = new ClipHats();
		hats.cowboy = true;
		attempt.hats = hats;
		var cowboy = ClipSimulator.run(cornerArea(), attempt, true);
		// The cowboy hat raises the speed floor to 12 px/frame, so it covers more ground early.
		assertTrue(cowboy.ghost[10].x > plain.ghost[10].x, 'cowboy hat runs faster (${cowboy.ghost[10].x} vs ${plain.ghost[10].x})');
		assertEquals("cowboy", hats.names().join(","), "hat names for the panel");
	}

	private static function testSuperJumpChargesThenLaunches():Void {
		// Stand still (direction only from frame 999) far from the wall.
		var normal = clipAttempt(50);
		normal.moveStart = 999;
		var superJump = clipAttempt(50);
		superJump.moveStart = 999;
		superJump.superCharge = ClipAttempt.MAX_SUPER_CHARGE;
		var input = superJump.inputAt(0, true);
		assertTrue(input.down && !input.jump && !input.left && !input.right, "charging holds only down");
		assertEquals(false, superJump.inputAt(ClipAttempt.MAX_SUPER_CHARGE, true).down, "down is released to launch");
		var normalRun = ClipSimulator.run(cornerArea(), normal, true);
		var superRun = ClipSimulator.run(cornerArea(), superJump, true);
		assertEquals(CLIP_START_X, superRun.ghost[ClipAttempt.MAX_SUPER_CHARGE].x, "charging stays in place");
		assertTrue(highest(superRun.ghost) < highest(normalRun.ghost) - 60, 'super jump goes much higher (${highest(superRun.ghost)} vs ${highest(normalRun.ghost)})');
	}

	private static function testDelayedMoveJumpsInPlaceFirst():Void {
		var attempt = new ClipAttempt(CLIP_START_X, FLOOR_Y, 90, 50, 75, 1, 1, 0, 8, false, 120);
		attempt.moveStart = 10;
		var run = ClipSimulator.run(cornerArea(), attempt, true);
		// ghost[f + 1] is the pose after frame f.
		assertEquals(CLIP_START_X, run.ghost[10].x, "no sideways movement before the move starts");
		assertTrue(run.ghost[10].y < FLOOR_Y, "already in the air from the jump");
		assertTrue(run.ghost[14].x > CLIP_START_X, "moves right once the direction is held");
	}

	private static function testAirTurnFlipsDirection():Void {
		var attempt = new ClipAttempt(CLIP_START_X, FLOOR_Y, 90, 50, 75, 1, 1, 0, 8, false, 120);
		attempt.turnFrame = 8;
		assertTrue(attempt.inputAt(7, false).right, "holds right before the turn");
		assertTrue(attempt.inputAt(8, false).left, "holds left from the turn");
		var run = ClipSimulator.run(cornerArea(), attempt, true);
		var furthest = 0.0;
		for (frame in run.ghost) furthest = Math.max(furthest, frame.x);
		assertTrue(run.ghost[run.ghost.length - 1].x < furthest - 30, "drifts back left after turning");
		assertEquals(-1, run.ghost[run.ghost.length - 1].facing, "faces left after the turn");
	}

	private static function testFinderSearchesMoveOptions():Void {
		var settings = new ClipFinderSettings(CLIP_START_X, FLOOR_Y, 1, StatRange.fixed(90), StatRange.fixed(50), StatRange.fixed(75));
		settings.dirs = [1];
		settings.downModes = [true];
		settings.normalJumps = false;
		settings.superCharges = [13, 14];
		settings.moveStarts = [0, 5];
		settings.turnFrames = [-1, 3];
		var finder = new ClipFinder(cornerBlocks(), settings);
		assertEquals(8, finder.total, "2 charges x 2 move starts x 2 turn options");
		var seen = [for (i in 0...finder.total) {
			var a = finder.attemptAt(i);
			'${a.superCharge}/${a.moveStart}/${a.turnFrame}';
		}];
		seen.sort(Reflect.compare);
		assertEquals("13/0/-1,13/0/3,13/5/-1,13/5/3,14/0/-1,14/0/3,14/5/-1,14/5/3", seen.join(","), "every combination exactly once");
	}

	private static function testSuperJumpCanStartOnAnyFrame():Void {
		var attempt = clipAttempt(50);
		attempt.superCharge = 13;
		attempt.superStart = 20;
		assertEquals(false, attempt.inputAt(19, true).down, "not charging before the start frame");
		assertEquals(true, attempt.inputAt(20, true).down, "charging from the start frame");
		assertEquals(true, attempt.inputAt(32, true).down, "still charging on the last charge frame");
		assertEquals(false, attempt.inputAt(33, true).down, "released after the charge");
		assertEquals(33, attempt.launchFrame(), "launch frame is start + charge");
	}

	private static function testAnyFrameSearchIsRandomAndRunsUntilStopped():Void {
		// Short runs keep the simulated part of this test quick.
		var settings = anyFrameSettings(7);
		settings.frames = 15;
		var endless = new ClipFinder(cornerBlocks(), settings);
		assertEquals(0, endless.total, "no fixed total");
		endless.step(2);
		assertEquals(false, endless.done, "keeps going until stopped");

		var a = new ClipFinder(cornerBlocks(), anyFrameSettings(7));
		var b = new ClipFinder(cornerBlocks(), anyFrameSettings(7));
		var lateJump = false, lateSuper = false, lateMove = false, turned = false, superJumps = 0;
		for (_ in 0...200) {
			var attempt = a.randomAttempt();
			assertEquals(attempt.describe(), b.randomAttempt().describe(), "same seed, same attempts");
			if (attempt.superCharge > 0) {
				superJumps++;
				lateSuper = lateSuper || attempt.superStart > 50;
				assertTrue(attempt.launchFrame() <= attempt.frames, "a super jump always has room to launch");
			} else {
				lateJump = lateJump || attempt.jumpFrame > 50;
			}
			lateMove = lateMove || attempt.moveStart > 50;
			turned = turned || attempt.turnFrame > 50;
		}
		assertTrue(lateJump && lateSuper && lateMove && turned, "jumps, super jumps, move starts and turns reach late frames");
		assertTrue(superJumps > 50 && superJumps < 150, 'normal and super jumps are both common ($superJumps/200 super)');

		settings = anyFrameSettings(3);
		settings.frames = 15;
		settings.randomAttempts = 3;
		var capped = new ClipFinder(cornerBlocks(), settings);
		capped.step(100);
		assertTrue(capped.done, "a capped random search stops");
		assertEquals(3, capped.tested, "after its attempt count");
	}

	private static function anyFrameSettings(seed:Int):ClipFinderSettings {
		var last = 119;
		var settings = new ClipFinderSettings(CLIP_START_X, FLOOR_Y, 1, new StatRange(80, 100), StatRange.fixed(50), StatRange.fixed(75));
		settings.anyFrame = true;
		settings.seed = seed;
		settings.dirs = [1];
		settings.maxJumpFrame = last;
		settings.superCharges = [for (c in ClipAttempt.MIN_SUPER_CHARGE...ClipAttempt.MAX_SUPER_CHARGE + 1) c];
		settings.moveStarts = [for (m in 0...last + 1) m];
		settings.turnFrames = [-1].concat([for (t in 1...last + 1) t]);
		return settings;
	}

	private static function testReplayDrivesRealPlayerAlongTheClip():Void {
		course.setKey(Keyboard.F9, true);
		course.setKey(Keyboard.C, true);
		course.setKey(Keyboard.D, true);
		var session = course.clipFinder;
		var before = course.localCharacter.stateSnapshot();
		// A recorded run from where the player is: right, jump at once, 30 frames.
		var attempt = new ClipAttempt(Math.round(before.x), Math.round(before.y), 63, 41, 57, course.level.gravity, 1, 0, 8, false, 30);
		var area = ClipArea.around(course.level.blocks, attempt.startX, attempt.startY, ClipFinder.AREA_RADIUS_X, ClipFinder.AREA_UP,
			ClipFinder.AREA_DOWN);
		var run = ClipSimulator.run(area, attempt, true);
		session.clips = [new pr2.gameplay.debug.ClipFinder.FoundClip(attempt, run)];
		session.panel.setClipCount(1);
		session.showClip(0);
		session.startReplay();
		assertTrue(session.replaying, "replay started");
		assertEquals(63.0, course.localCharacter.stateSnapshot().speedStat, "the clip's stats are applied");
		course.setKey(Keyboard.LEFT, true);
		for (frame in 0...run.ghost.length) {
			course.onEnterFrame(new Event(Event.ENTER_FRAME));
			var state = course.localCharacter.stateSnapshot();
			var recorded = run.ghost[frame];
			assertTrue(Math.abs(state.x - recorded.x) < 0.01 && Math.abs(state.y - recorded.y) < 0.01,
				'frame $frame follows the recording: (${state.x}, ${state.y}) vs (${recorded.x}, ${recorded.y})');
		}
		assertTrue(course.localCharacter.stateSnapshot().x > attempt.startX, "the held LEFT key was ignored during the replay");
		course.onEnterFrame(new Event(Event.ENTER_FRAME));
		assertEquals(false, session.replaying, "replay ends after the recording");
		assertEquals(before.speedStat, course.localCharacter.stateSnapshot().speedStat, "the player's own stats come back");
		course.setKey(Keyboard.LEFT, false);
		session.close();
		course.setKey(Keyboard.F9, false);
		course.setKey(Keyboard.C, false);
		course.setKey(Keyboard.D, false);
	}

	private static function testAreaGrowsToFollowThePlayer():Void {
		// A crop far too small to reach the wall: the run must grow it and still clip.
		var area = ClipArea.around(cornerBlocks(), CLIP_START_X, FLOOR_Y, 3, 3, 2);
		assertEquals(false, area.containsPixel(WALL_FACE + 5, FLOOR_Y), "the small crop stops short of the wall");
		var run = ClipSimulator.run(area, clipAttempt(90));
		assertTrue(area.growCount > 0, "the crop grew");
		assertTrue(area.containsPixel(WALL_FACE + 5, FLOOR_Y), "the crop now reaches the wall");
		assertTrue(run.clipped, "the clip is still found");
		assertEquals(26, run.clipFrame, "on the same frame as with the whole level");
		var recorded = ClipSimulator.run(area, clipAttempt(90), true);
		for (frame in recorded.ghost) assertTrue(area.containsPixel(frame.x, frame.y), "every recorded ghost frame is inside the simulated area");
	}

	private static function testAreaUsesWholeLevelForMapEdges():Void {
		var area = ClipArea.around(cornerBlocks(), CLIP_START_X, FLOOR_Y, 3, 3, 2);
		assertEquals(0.0, area.mapMinX, "left edge of the whole level");
		assertEquals(21 * 30.0, area.mapMaxX, "right edge of the whole level, not the crop");
		assertEquals(19 * 30.0, area.mapMaxY, "bottom edge of the whole level, not the crop");
	}

	private static function testTargetBlockFiltersClips():Void {
		// The known clip's body point enters tile 19,16 (the wall's lowest air-level tile).
		var onTarget = clipAttempt(90);
		onTarget.targetTileX = 19;
		onTarget.targetTileY = 16;
		assertTrue(ClipSimulator.run(cornerArea(), onTarget).clipped, "a clip into the target block counts");
		var elsewhere = clipAttempt(90);
		elsewhere.targetTileX = 20;
		elsewhere.targetTileY = 5;
		assertEquals(false, ClipSimulator.run(cornerArea(), elsewhere).clipped, "a clip into another block does not");
	}

	private static function testPickingTargetBlockInRace():Void {
		course.setKey(Keyboard.F9, true);
		course.setKey(Keyboard.C, true);
		course.setKey(Keyboard.D, true);
		var session = course.clipFinder;
		// Treat stage points as world points so the test can click exact tiles.
		session.stageToWorld = (x, y) -> new openfl.geom.Point(x, y);
		session.panel.aimBox.selected = true;
		session.start();
		assertTrue(session.panel.status.text.indexOf("Pick a target block first") == 0, "aiming needs a target");
		session.panel.aimBox.selected = false;
		assertEquals(false, session.pickAt(45, 45), "clicks do nothing until picking starts");
		session.toggleTargetPicking();
		assertTrue(session.picking, "the button starts picking");
		assertEquals(false, session.pickAt(15, 15), "the start marker is not a solid block");
		assertTrue(session.picking, "still picking after a miss");
		assertTrue(session.pickAt(45, 45), "the basic block at tile 1,1 is picked");
		assertEquals(false, session.picking, "picking ends");
		assertEquals("Target 1,1 (clear)", session.panel.targetButton.label, "button shows the target");
		assertTrue(session.targetMarker != null && session.targetMarker.parent == course.characterLayer, "the block is outlined in the level");
		assertTrue(session.panel.aimBox.selected, "picking a block ticks Aim at target");
		session.panel.leftBox.selected = false;
		session.panel.downBox.selected = false;
		session.panel.normalJumpRow.slider.value = 0;
		session.start();
		// Aiming is the normal clip tester, counting only clips into the picked block.
		assertEquals(3, session.finder.total, "the same search as without a target");
		assertEquals(1, session.finder.settings.targetTileX, "only clips into the target count");
		assertEquals(1, session.finder.attemptAt(0).targetTileY, "every attempt carries the target");
		session.stopSearch();
		session.panel.aimBox.selected = false;
		session.start();
		assertEquals(null, session.finder.settings.targetTileX, "unticked: the block stays picked but every clip counts");
		session.stopSearch();
		session.panel.aimBox.selected = true;
		session.toggleTargetPicking();
		assertEquals(false, session.panel.aimBox.selected, "clearing the target unticks Aim at target");
		assertEquals(null, session.targetTileX, "pressing the button again clears the target");
		assertEquals("Target: any block", session.panel.targetButton.label, "button back to any block");
		session.close();
		course.setKey(Keyboard.F9, false);
		course.setKey(Keyboard.C, false);
		course.setKey(Keyboard.D, false);
	}

	private static function testScannerFindsCorners():Void {
		var right = ClipScanner.findCorners(cornerBlocks(), 1);
		assertEquals(1, right.length, "the test level has one corner with the wall on the right");
		assertEquals(18, right[0].x, "its air tile column");
		assertEquals(16, right[0].y, "its air tile row");
		assertEquals(WALL_FACE, right[0].wallFace, "wall face");
		assertEquals(FLOOR_Y, right[0].floorY, "floor top");
		assertEquals(0, ClipScanner.findCorners(cornerBlocks(), -1).length, "and none facing left");
	}

	/** One run-up (202 px) and one launch (a short hop into fast-fall), to keep tests quick. **/
	private static function scanSettings(speed:Float):ClipScanSettings {
		var settings = new ClipScanSettings(speed, 50, 75, 1);
		settings.distances = [202];
		settings.jumpHolds = [8];
		settings.superCharges = [];
		return settings;
	}

	private static function testScannedClipLandsPastTheWall():Void {
		// The test corner, plus a ledge past the wall for a clip to land on.
		var blocks = cornerBlocks();
		for (col in 22...32) blocks.push(new LevelBlock(col, 25, BlockType.Basic));
		var scanner = new ClipScanner(blocks, scanSettings(90));
		assertEquals(1, scanner.corners.length, "the ledge adds no corner facing a wall");
		while (!scanner.done) scanner.step(10);
		assertEquals(1, scanner.portals.length, "the corner clips");
		var portal = scanner.portals[0];
		assertTrue(portal.exitX != null && portal.exitX > WALL_FACE + 90, 'comes to rest past the wall (${portal.exitX})');
		assertEquals(25 * 30.0, portal.exitY, "on the ledge");
		assertEquals(PortalKind.PassesThrough, ClipScanOverlay.kindOf(portal), "a clip through the wall");
		assertTrue(portal.attempt.releaseFrame > portal.run.clipFrame, "keys are released only after landing");
	}

	private static function testScannedClipWithNothingToLandOnFallsAway():Void {
		var scanner = new ClipScanner(cornerBlocks(), scanSettings(90));
		while (!scanner.done) scanner.step(10);
		assertEquals(1, scanner.portals.length, "the corner clips");
		assertEquals(PortalKind.FallsAway, ClipScanOverlay.kindOf(scanner.portals[0]), "falls out (and respawns) with nothing to land on");
	}

	private static function testScannerMarksCornersItCannotClip():Void {
		var scanner = new ClipScanner(cornerBlocks(), scanSettings(50));
		while (!scanner.done) scanner.step(10);
		assertEquals(0, scanner.portals.length, "speed 50 can't clip");
		assertEquals(1, scanner.solidCorners.length, "the corner is marked as not clippable");
	}

	private static function testScanFromPanel():Void {
		course.setKey(Keyboard.F9, true);
		course.setKey(Keyboard.C, true);
		course.setKey(Keyboard.D, true);
		var session = course.clipFinder;
		session.startScan();
		assertTrue(session.scanner != null, "Scan level starts a scan");
		assertTrue(session.overlay != null && session.overlay.parent == course.characterLayer, "the overlay is drawn in the level");
		for (_ in 0...200) {
			if (session.scanner == null) break;
			course.onEnterFrame(new Event(Event.ENTER_FRAME));
		}
		assertEquals(null, session.scanner, "the scan finishes");
		assertTrue(session.panel.status.text.indexOf("Scan done") == 0, 'status reports the result: ${session.panel.status.text}');
		session.close();
		assertTrue(session.overlay == null, "closing removes the overlay");
		course.setKey(Keyboard.F9, false);
		course.setKey(Keyboard.C, false);
		course.setKey(Keyboard.D, false);
	}

	private static function highest(frames:Array<pr2.gameplay.debug.ClipSimulator.GhostFrame>):Float {
		var top = Math.POSITIVE_INFINITY;
		for (frame in frames) top = Math.min(top, frame.y);
		return top;
	}

	private static function testStatRangeValues():Void {
		assertEquals("80,85,90", new StatRange(90, 80, 5).values().join(","), "reversed bounds are sorted");
		assertEquals("77", StatRange.fixed(77).values().join(","), "fixed stat");
	}

	private static function testGhostLoopsBackToStart():Void {
		var run = ClipSimulator.run(cornerArea(), clipAttempt(90), true);
		var ghost = new ClipGhost(new Character());
		ghost.play(run.ghost);
		assertTrue(ghost.character.visible, "ghost shows while playing");
		assertEquals(CLIP_START_X, ghost.character.x, "ghost starts at the start position");
		var sawSolid = false;
		for (_ in 0...run.ghost.length - 1) {
			ghost.tick();
			sawSolid = sawSolid || ghost.inSolid();
		}
		assertTrue(sawSolid, "ghost passes through the wall");
		for (_ in 0...ClipGhost.HOLD_FRAMES) ghost.tick();
		assertTrue(ghost.character.x > WALL_FACE, "ghost holds its last pose");
		ghost.tick();
		assertEquals(CLIP_START_X, ghost.character.x, "then resets to the start and plays again");
		ghost.dispose();
		assertEquals(false, ghost.character.visible, "disposed ghost is hidden");
	}

	private static function testComboTogglesPanelInRace():Void {
		course.setKey(Keyboard.F9, true);
		course.setKey(Keyboard.C, true);
		assertEquals(null, course.clipFinder, "two of the three keys do nothing");
		course.setKey(Keyboard.D, true);
		var session = course.clipFinder;
		assertTrue(session != null, "F9+C+D opens the Clip Finder");
		assertEquals(false, course.input.right, "D (alternate right) does not move the player while F9 is held");
		assertTrue(session.panel.parent == course, "panel is shown over the course");
		assertTrue(session.ghost.character.parent == course.characterLayer, "ghost lives with the characters");
		// Holding the combo does not re-toggle; releasing and pressing again closes.
		course.setKey(Keyboard.D, true);
		assertTrue(course.clipFinder == session, "held combo does not toggle again");
		course.setKey(Keyboard.D, false);
		course.setKey(Keyboard.D, true);
		assertEquals(null, course.clipFinder, "pressing the combo again closes it");
		assertTrue(session.panel.parent == null, "panel removed");
		course.setKey(Keyboard.F9, false);
		course.setKey(Keyboard.C, false);
		course.setKey(Keyboard.D, false);
	}

	private static function testComboWorksPressedOneAfterAnother():Void {
		var now = 100.0;
		Course.clipComboClock = () -> now;
		// Tap each key (press and release) in turn, within a second: opens.
		for (key in [Keyboard.D, Keyboard.F9, Keyboard.C]) {
			course.setKey(key, true);
			course.setKey(key, false);
			now += 0.3;
		}
		assertTrue(course.clipFinder != null, "F9, C and D tapped within a second open the Clip Finder");
		// The same taps spread over more than a second do nothing.
		for (key in [Keyboard.F9, Keyboard.C, Keyboard.D]) {
			course.setKey(key, true);
			course.setKey(key, false);
			now += 0.8;
		}
		assertTrue(course.clipFinder != null, "taps too far apart don't toggle it");
		// Tapped again quickly: closes.
		for (key in [Keyboard.C, Keyboard.D, Keyboard.F9]) {
			course.setKey(key, true);
			course.setKey(key, false);
			now += 0.2;
		}
		assertEquals(null, course.clipFinder, "a second quick combo closes it");
		Course.clipComboClock = haxe.Timer.stamp;
	}

	private static function testChatCommandTogglesClipFinder():Void {
		assertTrue(course.handleRaceChatLine(" /CLIP "), "/clip is handled locally, not sent to chat");
		assertTrue(course.clipFinder != null, "/clip opens the Clip Finder");
		assertTrue(course.handleRaceChatLine("/clipfinder"), "/clipfinder works too");
		assertEquals(null, course.clipFinder, "and closes it again");
	}

	private static function testPanelSearchUsesPlayerStatsByDefault():Void {
		course.setKey(Keyboard.F9, true);
		course.setKey(Keyboard.C, true);
		course.setKey(Keyboard.D, true);
		var session = course.clipFinder;
		var state = course.localCharacter.stateSnapshot();
		var speed = session.panel.speedRow.range();
		assertEquals(Math.round(state.speedStat), Std.int(speed.min), "speed defaults to the player's stat");
		assertEquals(speed.min, speed.max, "no range unless Range is ticked");
		// Keep the search tiny: one direction, jump on frame 0, no fast-fall.
		session.panel.leftBox.selected = false;
		session.panel.downBox.selected = false;
		session.panel.normalJumpRow.slider.value = 0;
		session.start();
		var finder = session.finder;
		assertEquals(3, finder.total, "one stat set x three jump holds");
		assertEquals(Math.round(state.x), Std.int(finder.settings.startX), "search starts where the player stands");
		for (_ in 0...20) {
			if (finder.done) break;
			course.onEnterFrame(new Event(Event.ENTER_FRAME));
		}
		assertTrue(finder.done, "search finishes over a few frames");
		assertTrue(session.panel.status.text.indexOf("Done 3/3") == 0, 'status reports completion: ${session.panel.status.text}');

		// The move options feed the search: super jumps instead of normal ones,
		// moving from frames 0-2, and either no turn or a turn on frame 1.
		var panel = session.panel;
		panel.normalJumpRow.box.selected = false;
		panel.superJumpRow.box.selected = true;
		panel.superJumpRow.slider.value = 14;
		panel.delayedMoveRow.box.selected = true;
		panel.delayedMoveRow.slider.value = 2;
		panel.airTurnRow.box.selected = true;
		panel.airTurnRow.slider.value = 1;
		session.start();
		var settings = session.finder.settings;
		assertEquals("13,14", settings.superCharges.join(","), "super jump charges 13 up to the slider");
		assertEquals("0,1,2", settings.moveStarts.join(","), "delayed move starts include moving at once");
		assertEquals("-1,1", settings.turnFrames.join(","), "air turn keeps the no-turn case");
		assertEquals(12, session.finder.total, "3 move starts x 2 turn options x 2 charges");
		panel.superJumpRow.box.selected = false;
		session.start();
		assertTrue(panel.status.text.indexOf("Tick Normal jump") == 0, "needs at least one kind of jump");

		// "Any frame" ignores the sliders and searches randomly until stopped.
		ClipFinderSession.randomSeed = () -> 5;
		panel.normalJumpRow.box.selected = true;
		panel.anyFrameBox.selected = true;
		session.start();
		settings = session.finder.settings;
		assertTrue(settings.anyFrame, "random timing");
		assertEquals(119, settings.maxJumpFrame, "jumps on any frame of the run");
		assertEquals(120, settings.moveStarts.length, "move starts on any frame");
		assertEquals(120, settings.turnFrames.length, "no turn, or a turn on any frame 1-119");
		assertEquals(0, session.finder.total, "runs until stopped");
		course.onEnterFrame(new Event(Event.ENTER_FRAME));
		assertTrue(panel.status.text.indexOf("random") > 0, 'status counts random attempts: ${panel.status.text}');
		session.stopSearch();
		assertTrue(panel.status.text.indexOf("Stopped") == 0, "Stop ends a random search");
		session.close();
		assertEquals(null, course.clipFinder, "closing the panel clears the session");
		course.setKey(Keyboard.F9, false);
		course.setKey(Keyboard.C, false);
		course.setKey(Keyboard.D, false);
	}

	// ---- helpers -----------------------------------------------------------

	private static function cornerBlocks():Array<LevelBlock> {
		var blocks:Array<LevelBlock> = [];
		for (col in 0...22) for (row in 0...20) {
			if (col >= 19 || row >= 17) blocks.push(new LevelBlock(col, row, BlockType.Basic));
		}
		return blocks;
	}

	private static function cornerArea():ClipArea {
		return new ClipArea(cornerBlocks(), 0, 0, 21, 19);
	}

	/** Run right at the wall, jump at once and hold it 8 frames, then fast-fall. */
	private static function clipAttempt(speed:Float):ClipAttempt {
		return new ClipAttempt(CLIP_START_X, FLOOR_Y, speed, 50, 75, 1, 1, 0, 8, true, 120);
	}

	private static function raceCourse():Course {
		var dataString = "m3`ffffff`0;0;11,1;0;8,0;1;0";
		var vars:Map<String, String> = new Map();
		vars.set("level_id", "99");
		vars.set("title", "Clip Finder Test");
		vars.set("gravity", "1");
		vars.set("max_time", "120");
		vars.set("gameMode", "race");
		vars.set("items", "all");
		vars.set("data", dataString);
		var data = new ServerLevelData(vars, true);
		var course = new Course(LevelDecoder.decode(dataString), data, LevelConfig.fromServerData(data));
		while (!course.levelRenderer.isDrawingComplete()) {
			course.levelRenderer.dispatchEvent(new Event(Event.ENTER_FRAME));
		}
		course.beginRace();
		while (course.countdown != null && course.countdown.parent != null) {
			course.countdown.advance();
		}
		return course;
	}

	private static function assertEquals<T>(expected:T, actual:T, message:String):Void {
		assertions++;
		if (actual != expected) {
			throw '$message: expected $expected, got $actual';
		}
	}

	private static function assertTrue(value:Bool, message:String):Void {
		assertions++;
		if (!value) {
			throw message;
		}
	}
}

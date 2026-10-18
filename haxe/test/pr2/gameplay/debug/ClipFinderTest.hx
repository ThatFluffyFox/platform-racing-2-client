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
import pr2.gameplay.debug.ClipFinderPanel.ScanStage;
import pr2.gameplay.debug.ClipRoutePlanner.RouteSettings;
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
@:access(pr2.gameplay.debug.ClipRoutePlanner)
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
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testPassThroughScanSkipsClipsThatFallAway", testPassThroughScanSkipsClipsThatFallAway);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testPassThroughScanKeepsClipsThatLand", testPassThroughScanKeepsClipsThatLand);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testRouteClipsThroughToSealedFloor", testRouteClipsThroughToSealedFloor);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testRouteReplaysAsAClip", testRouteReplaysAsAClip);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testRouteWalksWhenNoClipIsNeeded", testRouteWalksWhenNoClipIsNeeded);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testMinesAreNotClippableCorners", testMinesAreNotClippableCorners);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testRouteUsesMineKnockback", testRouteUsesMineKnockback);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testMineRouteReplaysExactly", testMineRouteReplaysExactly);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testRouteTurnsTheCourseWithARotateBlock", testRouteTurnsTheCourseWithARotateBlock);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testItemBlockRollsAreRepeatable", testItemBlockRollsAreRepeatable);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testRouteUsesTheHeldItem", testRouteUsesTheHeldItem);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testSwimmingIsASpotWithSwimMoves", testSwimmingIsASpotWithSwimMoves);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testBottomlessPoolStartsInTheWater", testBottomlessPoolStartsInTheWater);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testStandingOnVanishBlockIsNotRest", testStandingOnVanishBlockIsNotRest);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testRouteGoesThroughAVanishWall", testRouteGoesThroughAVanishWall);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testNoRouteSaysWhy", testNoRouteSaysWhy);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testLaserRecoilClipsThroughTheCorner", testLaserRecoilClipsThroughTheCorner);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testRouteUsesLaserRecoilClip", testRouteUsesLaserRecoilClip);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testSimulationsKeepTheRealItemUses", testSimulationsKeepTheRealItemUses);
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
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testRouteFromPanel", testRouteFromPanel);
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

	private static function testPassThroughScanSkipsClipsThatFallAway():Void {
		var settings = scanSettings(90);
		settings.passThroughOnly = true;
		var falls = new ClipScanner(cornerBlocks(), settings);
		while (!falls.done) falls.step(10);
		assertEquals(0, falls.portals.length, "a clip that falls out of the level is not a way through");
		assertEquals(1, falls.solidCorners.length, "so the corner has no way through");
	}

	private static function testPassThroughScanKeepsClipsThatLand():Void {
		var settings = scanSettings(90);
		settings.passThroughOnly = true;
		var blocks = cornerBlocks();
		for (col in 22...32) blocks.push(new LevelBlock(col, 25, BlockType.Basic));
		var lands = new ClipScanner(blocks, settings);
		while (!lands.done) lands.step(10);
		assertEquals(1, lands.portals.length, "a clip that lands past the wall is");
		assertTrue(lands.portals[0].passesThrough, "and passes through");
	}

	/**
		Upper floor (rows 17-19) with the test wall (cols 19-21), and a lower
		floor (row 24) sealed off by side walls: only a clip gets down there.
	**/
	private static function sealedFloorBlocks():Array<LevelBlock> {
		var blocks:Array<LevelBlock> = [];
		for (col in 0...36) for (row in 17...20) blocks.push(new LevelBlock(col, row, BlockType.Basic));
		for (col in 0...36) blocks.push(new LevelBlock(col, 24, BlockType.Basic));
		for (row in 0...24) {
			blocks.push(new LevelBlock(0, row, BlockType.Basic));
			blocks.push(new LevelBlock(35, row, BlockType.Basic));
		}
		for (col in 19...22) for (row in 0...17) blocks.push(new LevelBlock(col, row, BlockType.Basic));
		return blocks;
	}

	/** Recipe scans narrowed to the known run-up, to keep tests quick. **/
	private static function routeSettings(startX:Float, targetX:Int, targetY:Int):RouteSettings {
		var settings = new RouteSettings(startX, FLOOR_Y, 90, 50, 75, 1, targetX, targetY);
		settings.recipeDistances = [202];
		settings.recipeJumpHolds = [8];
		settings.recipeSuperCharges = [];
		return settings;
	}

	private static function testRouteClipsThroughToSealedFloor():Void {
		var settings = routeSettings(CLIP_START_X - 15, 23, 24);
		// Clip moves only: the walks and jumps are covered by the next test.
		settings.normalMoves = false;
		var planner = new ClipRoutePlanner(sealedFloorBlocks(), settings);
		while (!planner.done) planner.step(50);
		var route = planner.route;
		assertTrue(route != null, 'a route is found (${planner.spotsExplored} spots, ${planner.simulations} runs)');
		assertEquals(1, route.clips, "it clips once");
		assertTrue(route.steps[route.steps.length - 1].indexOf("clip through the wall at 19,16") == 0, 'the clip gets there: ${route.steps}');
		assertEquals(route.reachFrame + 1, route.script.length, "the script ends on the frame the block is reached");
		sealedRoutePlanner = planner;
	}

	/** The route planned by the test above. **/
	private static var sealedRoutePlanner:Null<ClipRoutePlanner> = null;

	private static function testRouteReplaysAsAClip():Void {
		var planner = sealedRoutePlanner;
		var route = planner.route;
		var found = planner.foundClip();
		assertEquals(route.script, found.attempt.script, "as a clip, the route's script is the attempt's inputs");
		// ghost[0] is the start and ghost[i] the pose after frame i - 1; the recording stops when the block is reached.
		assertEquals(route.reachFrame + 2, found.run.ghost.length, "replaying the script reaches the block on the same frame");
		assertTrue(found.run.clipFrame >= 0, "and the recording goes through a block");
		var last = found.run.ghost[found.run.ghost.length - 1];
		assertTrue(last.y > 24 * 30 - 2, 'the ghost ends on the lower floor (${last.x}, ${last.y})');
	}

	private static function testRouteWalksWhenNoClipIsNeeded():Void {
		var planner = new ClipRoutePlanner(sealedFloorBlocks(), routeSettings(CLIP_START_X, 15, 17));
		while (!planner.done) planner.step(50);
		var route = planner.route;
		assertTrue(route != null, "a route to a floor block nearby");
		assertEquals(0, route.clips, "needs no clip");
		assertTrue(route.steps[0].indexOf("walk right") == 0, 'walks there: ${route.steps}');
	}

	private static function testMinesAreNotClippableCorners():Void {
		var blocks = cornerBlocks();
		// The floor tile in the crook and the wall tile beside it become mines.
		for (block in blocks.copy()) if (block.y == 16 && block.x == 19) blocks.remove(block);
		blocks.push(new LevelBlock(19, 16, BlockType.Mine));
		assertEquals(0, ClipScanner.findCorners(blocks, 1).length, "a mine wall blows up instead of letting you clip in");
		var floorMine = cornerBlocks();
		for (block in floorMine.copy()) if (block.y == 17 && block.x == 18) floorMine.remove(block);
		floorMine.push(new LevelBlock(18, 17, BlockType.Mine));
		assertEquals(0, ClipScanner.findCorners(floorMine, 1).length, "nor does a corner standing on a mine");
	}

	/** A floor (rows 17-19) walled in at cols 0 and 40, a mine on the floor at col 14 and a ledge at row 9 (cols 18-25). **/
	private static function mineLedgeBlocks():Array<LevelBlock> {
		var blocks:Array<LevelBlock> = [];
		for (col in 0...41) for (row in 17...20) blocks.push(new LevelBlock(col, row, BlockType.Basic));
		for (row in 0...17) {
			blocks.push(new LevelBlock(0, row, BlockType.Basic));
			blocks.push(new LevelBlock(40, row, BlockType.Basic));
		}
		blocks.push(new LevelBlock(14, 16, BlockType.Mine));
		for (col in 18...26) blocks.push(new LevelBlock(col, 9, BlockType.Basic));
		return blocks;
	}

	private static function testRouteUsesMineKnockback():Void {
		// Jump 25 can't get up 8 tiles; the mine's blast can.
		// Start between the mine (col 14) and the ledge: walking back at the mine blasts the player up and right.
		var settings = new RouteSettings(500, FLOOR_Y, 90, 50, 25, 1, 21, 9);
		// Mine moves only (no walks, jumps or clips), so the blast is what gets there.
		settings.normalMoves = false;
		settings.clipWallRange = -1;
		var planner = new ClipRoutePlanner(mineLedgeBlocks(), settings);
		while (!planner.done) planner.step(50);
		var route = planner.route;
		assertTrue(route != null, 'a route is found (${planner.spotsExplored} spots, ${planner.simulations} runs)');
		var last = route.steps[route.steps.length - 1];
		assertTrue(last.indexOf("mine at 14,16") == 0 && last.indexOf("(hits a mine)") > 0, 'the blast gets there: ${route.steps}');
		assertEquals(0, route.clips, "without a clip");
		mineRoutePlanner = planner;
	}

	/** The route planned by the test above. **/
	private static var mineRoutePlanner:Null<ClipRoutePlanner> = null;

	private static function testMineRouteReplaysExactly():Void {
		var planner = mineRoutePlanner;
		var route = planner.route;
		var found = planner.foundClip();
		assertEquals(route.reachFrame + 2, found.run.ghost.length, "replaying reaches the ledge on the same frame");
		// Touching the block counts, from below too: the head (55 px above the feet) reaches the ledge's underside.
		var highest = highest(found.run.ghost);
		assertTrue(highest - 55 <= 10 * 30 + 1, 'the knockback lifts the player up to the ledge (feet at y=$highest)');
		assertTrue(highest < FLOOR_Y - 120, 'far higher than a jump-25 jump would (feet at y=$highest)');
	}

	/** A closed room: floor row 17, ceiling at `top`, walls at col 0 and `width - 1`. **/
	private static function boxRoom(width:Int, top:Int):Array<LevelBlock> {
		var blocks:Array<LevelBlock> = [];
		for (c in 0...width) {
			blocks.push(new LevelBlock(c, 17, BlockType.Basic));
			blocks.push(new LevelBlock(c, top, BlockType.Basic));
		}
		for (r in top + 1...17) {
			blocks.push(new LevelBlock(0, r, BlockType.Basic));
			blocks.push(new LevelBlock(width - 1, r, BlockType.Basic));
		}
		return blocks;
	}

	/** Route settings for the small rooms (stats 50/50/50, no clip scans). **/
	private static function roomRoute(startX:Float, startY:Float, targetX:Int, targetY:Int):RouteSettings {
		var settings = new RouteSettings(startX, startY, 50, 50, 50, 1, targetX, targetY);
		settings.clipWallRange = -1;
		return settings;
	}

	private static function testRouteTurnsTheCourseWithARotateBlock():Void {
		// A rotate block just over the start: any jump turns the course, and the
		// player falls toward the right wall, which is now the floor.
		var blocks = boxRoom(9, 8);
		blocks.push(new LevelBlock(3, 14, BlockType.RotateRight));
		var planner = new ClipRoutePlanner(blocks, roomRoute(105, FLOOR_Y, 8, 12));
		while (!planner.done) planner.step(50);
		var route = planner.route;
		assertTrue(route != null, 'a route is found (${planner.spotsExplored} spots, ${planner.simulations} runs, ${planner.rejectionSummary()})');
		assertTrue(route.steps[0].indexOf("(turns the course)") > 0, 'by turning the course: ${route.steps}');
		var ghost = planner.foundClip().run.ghost;
		assertEquals(route.reachFrame + 2, ghost.length, "the route replays to the same frame");
		assertEquals(90, ghost[ghost.length - 1].rotation, "the ghost ends on the turned course");
		var biggest = 0.0;
		for (i in 1...ghost.length) biggest = Math.max(biggest, Math.abs(ghost[i].x - ghost[i - 1].x) + Math.abs(ghost[i].y - ghost[i - 1].y));
		assertTrue(biggest < 40, 'the ghost moves smoothly in level space through the turn (largest step $biggest px)');
	}

	private static function testItemBlockRollsAreRepeatable():Void {
		var blocks = boxRoom(9, 8);
		// An item block with any item, right over the start.
		blocks.push(new LevelBlock(3, 14, BlockType.Item));
		var planner = new ClipRoutePlanner(blocks, roomRoute(105, FLOOR_Y, 8, 9));
		var jump = [for (_ in 0...20) new pr2.gameplay.player.LocalPlayerInput(false, false, true, false)];
		var first = planner.simulate(jump, 0, false);
		var second = planner.simulate(jump, 0, false);
		assertTrue(first.restItem != null, "hitting the item block gives an item");
		assertEquals(first.restItem, second.restItem, "and the same one every time the script is replayed");
		assertTrue(first.effects().indexOf("gets ") >= 0, 'the step says so: "${first.effects()}"');
	}

	private static function testRouteUsesTheHeldItem():Void {
		var settings = roomRoute(225, FLOOR_Y, 8, 8);
		// The player holds a jetpack; with plain moves off, only item moves are tried.
		settings.items = new ClipSimulator.ClipItems(6);
		settings.normalMoves = false;
		var planner = new ClipRoutePlanner(boxRoom(9, 0), settings);
		while (!planner.done) planner.step(50);
		var route = planner.route;
		assertTrue(route != null, 'a route is found (${planner.simulations} runs, ${planner.rejectionSummary()})');
		assertTrue(route.steps[0].indexOf("Jet Pack") > 0, 'using the jetpack: ${route.steps}');
	}

	private static function testSwimmingIsASpotWithSwimMoves():Void {
		// A pool 14 tiles deep: the player doesn't have to sink to the bottom first.
		var blocks = boxRoom(9, 0);
		for (c in 1...8) for (r in 3...17) blocks.push(new LevelBlock(c, r, BlockType.Water));
		var settings = roomRoute(105, 150, 8, 1);
		settings.normalMoves = false;
		var planner = new ClipRoutePlanner(blocks, settings);
		var start = planner.open[0];
		assertTrue(start.inWater, "the start is a spot in the water");
		assertTrue(start.tileY < 16, 'swimming counts as a spot before reaching the bottom (row ${start.tileY})');
		assertTrue(planner.movesFrom(start).filter(m -> m.name.indexOf("swim up") == 0).length > 0, "so swim moves are tried");
		while (!planner.done) planner.step(50);
		assertTrue(planner.route != null && planner.route.steps[0].indexOf("swim") == 0, 'and swimming reaches the top corner: ${planner.route == null ? [] : planner.route.steps}');
	}

	private static function testBottomlessPoolStartsInTheWater():Void {
		// Water with nothing under it (like razor blade's start): sinking out of the
		// bottom drops the player off the map and back into the water, forever.
		var blocks:Array<LevelBlock> = [];
		for (c in 0...12) for (r in 15...18) blocks.push(new LevelBlock(c, r, c < 6 ? BlockType.Water : BlockType.Basic));
		var planner = new ClipRoutePlanner(blocks, roomRoute(75, 14 * 30, 9, 14));
		var start = planner.open[0];
		assertTrue(start.inWater, 'the start is a spot in the water (${start.key})');
		assertTrue(start.tileY >= 15 && start.tileY <= 17, 'inside the pool, not below the level (row ${start.tileY})');
		while (!planner.done) planner.step(50);
		assertTrue(planner.route != null, 'and the block beside the pool is reached (${planner.rejectionSummary()})');
	}

	private static function testStandingOnVanishBlockIsNotRest():Void {
		// The start stands on a vanish block over a pit; the floor below is row 20.
		var blocks = boxRoom(12, 8).filter(b -> !(b.y == 17 && b.x > 0 && b.x < 11));
		blocks.push(new LevelBlock(3, 17, BlockType.Vanish));
		for (c in 0...12) blocks.push(new LevelBlock(c, 20, BlockType.Basic));
		for (r in 17...20) {
			blocks.push(new LevelBlock(0, r, BlockType.Basic));
			blocks.push(new LevelBlock(11, r, BlockType.Basic));
		}
		var planner = new ClipRoutePlanner(blocks, roomRoute(105, FLOOR_Y, 9, 9));
		assertEquals(19, planner.open[0].tileY, "the vanish block fades and drops the player to the floor below");
	}

	private static function testRouteGoesThroughAVanishWall():Void {
		// Two rooms split by a wall whose bottom two tiles are vanish blocks.
		var blocks = boxRoom(12, 8);
		for (r in 9...17) blocks.push(new LevelBlock(6, r, r >= 15 ? BlockType.Vanish : BlockType.Basic));
		var planner = new ClipRoutePlanner(blocks, roomRoute(105, FLOOR_Y, 9, 17));
		var vanishMoves = planner.movesFrom(planner.open[0]).filter(m -> m.name.indexOf("vanish block") == 0);
		assertEquals(0, vanishMoves.length, "no vanish moves far from the wall");
		while (!planner.done) planner.step(50);
		assertTrue(planner.route != null, 'the right room is reached through the vanish blocks (${planner.rejectionSummary()})');
	}

	private static function testNoRouteSaysWhy():Void {
		// The target is outside a closed box: nothing reaches it.
		var settings = roomRoute(105, FLOOR_Y, 20, 16);
		settings.normalMoves = false;
		settings.items = new ClipSimulator.ClipItems(6);
		// One spot's jetpack moves are enough to have dropped some.
		settings.maxSpots = 1;
		var planner = new ClipRoutePlanner(boxRoom(9, 8), settings);
		while (!planner.done) planner.step(50);
		assertEquals(null, planner.route, "no route");
		assertTrue(planner.rejectionSummary().length > 0, 'and the planner says why moves were dropped: ${planner.rejectionSummary()}');
	}

	/** Laser recoil only, narrowed to the frames around the landing (stats 50/50/50 land on frame 38). **/
	private static function laserScan():ClipScanSettings {
		var settings = new ClipScanSettings(50, 50, 50, 1);
		settings.distances = [];
		settings.laser = true;
		settings.laserGaps = [0];
		settings.laserHolds = [8];
		settings.laserFireFrames = [35, 36, 37, 38];
		return settings;
	}

	private static function testLaserRecoilClipsThroughTheCorner():Void {
		// Speed 50 can't clip this corner by running at it; the laser's recoil can.
		var scanner = new ClipScanner(sealedFloorBlocks(), laserScan(), new pr2.gameplay.debug.ClipScanner.ClipCorner(18, 16, 1));
		while (!scanner.done) scanner.step(10);
		assertEquals(1, scanner.portals.length, "jump against the wall, turn away and fire as you land: a clip");
		var portal = scanner.portals[0];
		assertTrue(portal.attempt.describe().indexOf("laser recoil") >= 0, 'described as a laser recoil clip: ${portal.attempt.describe()}');
		assertTrue(portal.passesThrough, 'and it comes out below (${portal.exitX}, ${portal.exitY})');
		var noLaser = laserScan();
		noLaser.laser = false;
		noLaser.distances = [202];
		noLaser.jumpHolds = [8];
		noLaser.superCharges = [];
		var plain = new ClipScanner(sealedFloorBlocks(), noLaser, new pr2.gameplay.debug.ClipScanner.ClipCorner(18, 16, 1));
		while (!plain.done) plain.step(10);
		assertEquals(0, plain.portals.length, "without the laser, speed 50 doesn't clip it");
	}

	private static function testRouteUsesLaserRecoilClip():Void {
		var settings = new RouteSettings(300, FLOOR_Y, 50, 50, 50, 1, 20, 24);
		settings.items = new ClipSimulator.ClipItems(1);
		settings.normalMoves = false;
		settings.recipeDistances = [];
		settings.recipeLaserGaps = [0];
		settings.recipeLaserHolds = [8];
		settings.recipeLaserFireFrames = [35, 36, 37, 38];
		var planner = new ClipRoutePlanner(sealedFloorBlocks(), settings);
		while (!planner.done) planner.step(50);
		var route = planner.route;
		assertTrue(route != null, 'a route is found (${planner.simulations} runs, ${planner.rejectionSummary()})');
		assertTrue(route.steps[route.steps.length - 1].indexOf("(laser recoil)") > 0, 'through the floor with the laser: ${route.steps}');
		assertEquals(route.reachFrame + 2, planner.foundClip().run.ghost.length, "and it replays to the same frame");
	}

	private static function testSimulationsKeepTheRealItemUses():Void {
		// Item uses live in one global store; simulated items must not change the real player's.
		ClipSimulator.setItemUses(2);
		ClipSimulator.keepRealItem(() -> {
			var settings = roomRoute(225, FLOOR_Y, 8, 8);
			settings.items = new ClipSimulator.ClipItems(6);
			settings.normalMoves = false;
			var planner = new ClipRoutePlanner(boxRoom(9, 0), settings);
			while (!planner.done) planner.step(50);
			return planner.route;
		});
		assertEquals(2.0, ClipSimulator.itemUses(), "the real item's uses are put back");
	}

	private static function testRouteFromPanel():Void {
		course.setKey(Keyboard.F9, true);
		course.setKey(Keyboard.C, true);
		course.setKey(Keyboard.D, true);
		var session = course.clipFinder;
		var menu = session.panel.scanSelect;
		menu.selectFromUser(1);
		assertEquals(-1, menu.selectedIndex, "the menu goes back to its title after a pick");
		assertEquals("Scan level...", menu.labelField.text, "which reads Scan level");
		assertTrue(session.planner == null, "Stage 2 needs a target");
		assertTrue(session.panel.status.text.indexOf("Pick a target") == 0, 'asks for one: ${session.panel.status.text}');
		// The block under the player's feet: already touching it.
		var state = course.localCharacter.stateSnapshot();
		session.setTarget(ClipSimulator.tileOf(state.x), ClipSimulator.tileOf(state.y));
		menu.selectFromUser(1);
		assertTrue(session.planner != null, "Stage 2 (route to target) starts planning");
		assertTrue(session.scanner == null, "and not the map scan");
		assertTrue(!menu.enabled, "the menu is locked while it runs");
		for (_ in 0...200) {
			if (session.planner == null) break;
			course.onEnterFrame(new Event(Event.ENTER_FRAME));
		}
		assertEquals(null, session.planner, "planning finishes");
		assertTrue(session.panel.status.text.indexOf("Route found") == 0, 'status reports the route: ${session.panel.status.text}');
		assertEquals(1, session.clips.length, "the route is the one clip shown");
		assertTrue(session.panel.replayButton.enabled, "and can be replayed on the player");
		assertTrue(session.panel.clipInfo.text.indexOf("Route:") >= 0, 'its steps are listed: ${session.panel.clipInfo.text}');
		session.close();
		course.setKey(Keyboard.F9, false);
		course.setKey(Keyboard.C, false);
		course.setKey(Keyboard.D, false);
	}

	private static function testScanFromPanel():Void {
		course.setKey(Keyboard.F9, true);
		course.setKey(Keyboard.C, true);
		course.setKey(Keyboard.D, true);
		var session = course.clipFinder;
		var menu = session.panel.scanSelect;
		assertEquals(2, menu.length, "the Scan level menu has the two stages");
		assertEquals(ScanStage.MapScan, menu.itemAt(0), "stage 1 is the map scan");
		assertEquals(ScanStage.RouteToTarget, menu.itemAt(1), "stage 2 is the route to the target");
		menu.selectFromUser(0);
		assertTrue(session.scanner != null, "Stage 1 starts the map scan");
		assertTrue(session.planner == null, "and not a route");
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

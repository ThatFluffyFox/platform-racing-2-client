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
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testStatRangeValues", testStatRangeValues);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testGhostLoopsBackToStart", testGhostLoopsBackToStart);
		// The panel tests share one started race; building a Course is fixture
		// setup, not Clip Finder behaviour, so it is kept out of their timing.
		course = raceCourse();
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testComboTogglesPanelInRace", testComboTogglesPanelInRace);
		pr2.DeterministicTestMode.runTest("ClipFinderTest.testPanelSearchUsesPlayerStatsByDefault", testPanelSearchUsesPlayerStatsByDefault);
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
		session.panel.jumpWindowSlider.value = 0;
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

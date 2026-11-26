package pr2.effects;

import openfl.events.Event;
import pr2.runtime.FrameClock;
import pr2.runtime.FrameRateDiagnostics;
import pr2.runtime.FrameRateSettings;

/** Characterizes the native replacement for the authored mine placement clip. */
class MineAppearTest {
	private static var assertions = 0;

	public static function main():Void {
		pr2.DeterministicTestMode.runTest("MineAppearTest.testAuthoredAnimationLifecycle", function():Void {
		assertAuthoredMineAsset();
		var completions = 0;
		var effect = new MineAppear(125, 75, 30, 0, 0, function():Void completions++, false);
		assertEquals(125.0, effect.x, "native effect keeps world x");
		assertEquals(75.0, effect.y, "native effect keeps world y");
		assertEquals(30.0, effect.rotation, "native effect keeps authored rotation");
		assertNear(0, effect.animation.bitmap.alpha, "frame one begins transparent like MineAppearAnimation");
		assertNear(4.29489135742188, effect.animation.bitmap.scaleX, "frame one keeps authored expansion scale");

		advance(effect, 16);
		assertEquals(16, effect.animation.playback.currentFrame, "native sequence reaches authored frame 17 after 16 ticks");
		assertNear(1.82369995117188, effect.animation.bitmap.scaleX, "midpoint frame keeps authored mine scale");
		assertNear(-26.6, effect.animation.bitmap.x, "midpoint frame keeps authored mine x");
		assertNear(1, effect.animation.bitmap.alpha, "midpoint mine is fully visible");

		advance(effect, 16);
		assertEquals(32, effect.animation.playback.currentFrame, "native sequence reaches final authored frame");
		assertNear(1, effect.animation.bitmap.scaleX, "final frame restores authored mine scale");
		assertNear(-14.55, effect.animation.bitmap.x, "final frame keeps authored mine registration");
		assertNear(1, effect.animation.bitmap.transform.colorTransform.redMultiplier, "final frame removes white transition tint");

		advance(effect, 5);
		assertEquals(0, completions, "final frame holds until Flash's 38-frame removal");
		assertNear(1, effect.animation.bitmap.scaleX, "held final frame keeps authored mine scale");
		advance(effect, 1);
		assertEquals(1, completions, "completion fires once after exactly 38 frames");
		assertEquals(null, effect.animation, "completion tears down the native animation");
		effect.remove(true);
		assertEquals(1, completions, "explicit removal cannot replay completion");
		});
		pr2.DeterministicTestMode.runTest("MineAppearTest.testEffectLifetimeMatchesAtBothPresentationRates", testEffectLifetimeMatchesAtBothPresentationRates);

		trace('MineAppearTest passed $assertions assertions');
	}

	private static function testEffectLifetimeMatchesAtBothPresentationRates():Void {
		var baseline = runEffectCadence(false);
		var smooth = runEffectCadence(true);
		assertEquals("38:38:1:true", baseline, "30 FPS mine effect completes after 38 authoritative frames");
		assertEquals("38:75:1:true", smooth,
			"60 FPS mine effect keeps its 38-frame lifetime and ignores presentation-only frames");
	}

	private static function runEffectCadence(smooth:Bool):String {
		var clock = new FrameClock(FrameRateSettings.fromQuery(smooth ? "?smooth60=1" : null, true),
			new FrameRateDiagnostics(function():Float return 0));
		@:privateAccess FrameClock.setCurrentForTests(clock);
		var completions = 0;
		var effect = new MineAppear(0, 0, 0, 0, 0, function():Void completions++, false);
		while (effect.animation != null) {
			clock.advanceFrame();
			effect.dispatchEvent(new Event(Event.ENTER_FRAME));
		}
		@:privateAccess FrameClock.setCurrentForTests(null);
		return '${clock.simulationFrameNumber}:${clock.stageFrameNumber}:$completions:${effect.animation == null}';
	}

	private static function advance(effect:MineAppear, frames:Int):Void {
		for (_ in 0...frames) effect.dispatchEvent(new Event(Event.ENTER_FRAME));
	}
	private static function assertAuthoredMineAsset():Void {
		#if sys
		var bytes = sys.io.File.getBytes("assets/bitmaps/mine.jpg");
		assertEquals(0xFF, bytes.get(0), "native mine uses the original XFL JPEG payload");
		assertEquals(0xD8, bytes.get(1), "native mine asset remains a JPEG");
		assertEquals(true, bytes.length > 100, "native mine payload is non-empty visual source");
		#end
	}
	private static function assertEquals(expected:Dynamic, actual:Dynamic, message:String):Void {
		assertions++;
		if (expected != actual) throw '$message: expected $expected, got $actual';
	}
	private static function assertNear(expected:Float, actual:Float, message:String):Void {
		assertions++;
		if (Math.abs(expected - actual) > .0001) throw '$message: expected $expected, got $actual';
	}
}

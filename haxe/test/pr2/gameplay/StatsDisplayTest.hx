package pr2.gameplay;

class StatsDisplayTest {
	private static var assertions:Int = 0;

	public static function main():Void {
		pr2.DeterministicTestMode.runTest("StatsDisplayTest.testStatsAndHoverContent", testStatsAndHoverContent);
		if (pr2.DeterministicTestMode.finishSmokeSuite("StatsDisplayTest")) return;
		trace('StatsDisplayTest passed $assertions assertions');
	}

	private static function testStatsAndHoverContent():Void {
		var display = new StatsDisplay();
		assertEquals("assets/svg/effects/stats_display_01.svg", StatsDisplay.BACKGROUND_ASSET,
			"stats display uses the exact authored XFL background and dividers");
		assertEquals(true, display.exactBackground.width > 0,
			"authored stats display art renders");
		assertEquals(true, display.backgroundPanel.scale9Grid != null,
			"stats background preserves the SquareBG scale grid");
		assertNear(-0.5, field(display, "speedBox").x, 0.001, "speed field starts at the SWF bounds (placement 2.4, gutter -2.9)");
		assertNear(1.75, field(display, "speedBox").y, 0.001, "stat fields start 2px above their placement, at the SWF bounds");
		assertNear(19.5, field(display, "speedBox").width, 0.001, "speed field uses the SWF field width");
		assertNear(19.7, field(display, "accelBox").width, 0.001, "acceleration field uses the SWF field width");
		assertNear(19.3, field(display, "jumpBox").width, 0.001, "jump field uses the SWF field width");
		assertEquals("Speed: 0\nAcceleration: 0\nJumping: 0", display.hoverContent(), "default stats render zeroes");

		display.setStats(42, 17, 88);
		assertEquals("42", display.statText(field(display, "speedBox")), "speed box text set");
		assertEquals("17", display.statText(field(display, "accelBox")), "accel box text set");
		assertEquals("88", display.statText(field(display, "jumpBox")), "jump box text set");
		assertEquals("Speed: 42\nAcceleration: 17\nJumping: 88", display.hoverContent(), "hover content mirrors Flash StatsDisplay");

		display.remove();
	}

	private static function field(display:StatsDisplay, name:String):Null<openfl.text.TextField> {
		return pr2.lobby.LobbyArt.text(display, name);
	}

	private static function assertEquals(expected:Dynamic, actual:Dynamic, message:String):Void {
		assertions++;
		if (expected != actual) {
			throw '$message: expected $expected, got $actual';
		}
	}

	private static function assertNear(expected:Float, actual:Float, tolerance:Float, message:String):Void {
		assertions++;
		if (Math.abs(expected - actual) > tolerance) throw '$message: expected $expected +/- $tolerance, got $actual';
	}
}

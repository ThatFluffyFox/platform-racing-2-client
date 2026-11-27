package pr2.lobby;

import openfl.text.TextField;
import pr2.lobby.account.StatsSelect;
import pr2.ui.controls.GameSlider;
import pr2.util.TestDisplayUtil as DisplayUtil;

class PointsRemainingTest {
	private static var assertions:Int = 0;

	public static function main():Void {
		var stats = new StatsSelect(150, 40, 50, 30);
		var graphic = @:privateAccess stats.pointsGraphic();
		var label = Std.downcast(DisplayUtil.findByName(graphic, "label"), TextField);
		var value = Std.downcast(DisplayUtil.findByName(graphic, "textBox"), TextField);
		assertNotNull(label, "authored points label exists");
		assertNotNull(value, "authored points value exists");
		assertEquals("Points Remaining:", label.text, "points label keeps authored copy");
		assertClose(0.0, label.x, "points label matches the SWF field box for its XFL X");
		assertClose(0.0, label.y, "points label matches the SWF field box for its XFL Y");
		assertClose((128 + 4) * 0.999557495117188, label.width, "points label is widened so DejaVu Sans Bold keeps the colon");
		assertClose(18.55, label.height, "points label matches the SWF field box for its XFL height");
		assertClose(0.999557495117188, label.scaleX, "points label keeps XFL horizontal scale");
		assertClose(128.05, value.x, "points value matches the SWF field box for its XFL X");
		assertClose(0.0, value.y, "points value matches the SWF field box for its XFL Y");
		assertClose((37.85 + 4) * 1.00167846679688, value.width, "points value keeps transformed authored width");
		assertClose(18.5, value.height, "points value matches the SWF field box for its XFL height");
		assertClose(1.00167846679688, value.scaleX, "points value keeps XFL horizontal scale");
		assertEquals("30", value.text, "remaining total is rendered immediately");
		stats.setStats(50, 50, 50);
		assertEquals("0", value.text, "remaining total updates at exhaustion");
		stats.setStats(200, 0, 0);
		assertEquals("50`0`0", stats.getInfoStr(), "authored sliders clamp values to 50");
		assertEquals("100", value.text, "clamped values update remaining points");
		var speed = @:privateAccess stats.speedSlider;
		var nameBox = Std.downcast(DisplayUtil.findByName(speed, "nameBox"), TextField);
		var statBox = Std.downcast(DisplayUtil.findByName(speed, "textBox"), TextField);
		var slider = Std.downcast(DisplayUtil.findByName(speed, "slider"), GameSlider);
		var dec = DisplayUtil.findByName(speed, "decBtn");
		var inc = DisplayUtil.findByName(speed, "incBtn");
		assertClose(-0.15, nameBox.x, "stat name matches the SWF field box for its XFL X");
		assertClose(0.0, nameBox.y, "stat name matches the SWF field box for its XFL Y");
		assertClose(91.0, statBox.x, "stat value matches the SWF field box for its XFL X");
		assertClose(0.0, statBox.y, "stat value matches the SWF field box for its XFL Y");
		assertClose(20, slider.y, "stat slider keeps XFL Y");
		// Flash applies the 1.5625 XFL instance scale as a width change (80 * 1.5625),
		// keeping the SliderThumb its authored width instead of stretching it.
		assertClose(125, slider.controlWidth, "stat slider widens to the authored track width");
		assertClose(1, slider.scaleX, "stat slider keeps unit scale so the thumb is not smeared");
		assertClose(22, slider.controlHeight, "stat slider keeps XFL height");
		assertClose(-1, dec.transform.matrix.a, "decrement arrow keeps XFL horizontal inversion");
		assertClose(-1, dec.transform.matrix.d, "decrement arrow keeps XFL vertical inversion");
		assertClose(-8.7, dec.transform.matrix.tx, "decrement arrow keeps XFL X");
		assertClose(23, dec.transform.matrix.ty, "decrement arrow keeps XFL Y");
		assertClose(133.3, inc.x, "increment arrow keeps XFL X");
		assertClose(7, inc.y, "increment arrow keeps XFL Y");
		stats.remove();
		trace('PointsRemainingTest passed $assertions assertions');
	}

	private static function assertNotNull(value:Dynamic, message:String):Void {
		assertions++;
		if (value == null) throw message;
	}

	private static function assertEquals(expected:Dynamic, actual:Dynamic, message:String):Void {
		assertions++;
		if (expected != actual) throw '$message: expected $expected, got $actual';
	}

	private static function assertClose(expected:Float, actual:Float, message:String):Void {
		assertions++;
		if (Math.abs(expected - actual) > 0.000001) throw '$message: expected $expected, got $actual';
	}
}

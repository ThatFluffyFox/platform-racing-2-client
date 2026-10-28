package pr2.runtime;

/**
	Turns off kerning for canvas text, as Flash text fields render it.

	Flash's TextFormat.kerning defaults to false, so PR2's text was never
	kerned. Browsers kern canvas text by default, which pulled pairs such as
	"Te", "Va" and "y," closer than Flash drew them (up to about 2px per label
	with DejaVu Sans). OpenFL measures and draws text on canvas contexts and
	resets their state whenever it resizes a text canvas, so the setting is
	reapplied each time a context's font is set.
**/
final class Html5TextKerning {
	public static function install():Void {
		#if (js && html5)
		js.Syntax.code("(function () {
			var proto = window.CanvasRenderingContext2D && CanvasRenderingContext2D.prototype;
			if (!proto || !('fontKerning' in proto) || proto.__pr2NoKerning) return;
			var font = Object.getOwnPropertyDescriptor(proto, 'font');
			if (!font || !font.set) return;
			Object.defineProperty(proto, 'font', {
				configurable: true,
				enumerable: font.enumerable,
				get: font.get,
				set: function (value) {
					font.set.call(this, value);
					this.fontKerning = 'none';
				}
			});
			proto.__pr2NoKerning = true;
		})()");
		#end
	}
}

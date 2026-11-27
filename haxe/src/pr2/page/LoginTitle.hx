package pr2.page;

import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.filters.GlowFilter;
import openfl.geom.Matrix;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import pr2.runtime.FontResolver;

/**
	The "Platform Racing 2" logo on the login page.

	In the published SWF's LoginPageGraphic this is a Gwibble text field with a
	white glow of blur 5, strength 2, quality 3 (the XFL lists blur 6, but the
	compiled glow Flash drew is 5). Geometry mirrors the field: tx/ty 81.4/92.4,
	box 386.8 wide, size 43, centered, lineSpacing -3.

	On HTML5, OpenFL draws filtered objects into a cache sized for the 550x400
	stage and stretches it to the window, which blurs the logo. Flash drew the
	glow at the output resolution, so here the text and glow are drawn into a
	bitmap at the stage's on-screen scale and shown at 1:1 device pixels, with
	Flash's glow computed directly (`applyFlashGlow`). The bitmap is redrawn
	when the window's scale changes.
**/
@:access(openfl.display.Stage)
class LoginTitle extends Sprite {
	// The authored field is 386.8 wide at x 81.4. The text is centred, so it is
	// widened by 20 on each side (same centre): Gwibble's "G" in "Racing" ran
	// past the authored right edge here and was clipped.
	private static inline var TEXT_X:Float = 81.4 - 20;
	private static inline var TEXT_Y:Float = 92.4;
	private static inline var TEXT_WIDTH:Float = 386.8 + 40;
	private static inline var TEXT_HEIGHT:Float = 120;
	private static inline var GLOW_BLUR:Float = 5;
	// Room for the glow around the text box, in stage pixels.
	private static inline var GLOW_PAD:Float = 8;
	private static inline var GLOW_STRENGTH:Float = 2;
	private static inline var GLOW_QUALITY:Int = 3;
	private static inline var GLOW_COLOR:Int = 0xFFFFFF;

	private final text:TextField;
	#if (js && html5)
	private var bitmap:Null<Bitmap>;
	private var renderedScale:Float = -1;
	#end

	public function new() {
		super();
		name = "loginTitle";
		mouseEnabled = false;
		mouseChildren = false;
		text = createText();
		#if (js && html5)
		addEventListener(Event.ADDED_TO_STAGE, refresh);
		addEventListener(Event.ENTER_FRAME, refresh);
		#else
		text.x = TEXT_X;
		text.y = TEXT_Y;
		text.filters = [new GlowFilter(GLOW_COLOR, 1, GLOW_BLUR, GLOW_BLUR, GLOW_STRENGTH, GLOW_QUALITY)];
		addChild(text);
		#end
	}

	public function dispose():Void {
		#if (js && html5)
		removeEventListener(Event.ADDED_TO_STAGE, refresh);
		removeEventListener(Event.ENTER_FRAME, refresh);
		if (bitmap != null) {
			if (bitmap.bitmapData != null) bitmap.bitmapData.dispose();
			removeChild(bitmap);
			bitmap = null;
		}
		#end
	}

	#if (js && html5)
	private function refresh(_:Null<Event>):Void {
		var scale = outputScale();
		if (Math.abs(scale - renderedScale) < 0.001) return;
		renderedScale = scale;

		var pad = GLOW_PAD;
		var width = Math.ceil((TEXT_WIDTH + pad * 2) * scale);
		var height = Math.ceil((TEXT_HEIGHT + pad * 2) * scale);
		var data = new BitmapData(width, height, true, 0);
		var matrix = new Matrix(scale, 0, 0, scale, pad * scale, pad * scale);
		data.draw(text, matrix, null, null, null, true);
		applyFlashGlow(data, GLOW_BLUR * scale, GLOW_STRENGTH, GLOW_QUALITY, GLOW_COLOR);

		if (bitmap == null) {
			bitmap = new Bitmap();
			addChild(bitmap);
		} else if (bitmap.bitmapData != null) {
			bitmap.bitmapData.dispose();
		}
		bitmap.bitmapData = data;
		bitmap.smoothing = true;
		bitmap.scaleX = bitmap.scaleY = 1 / scale;
		bitmap.x = TEXT_X - pad;
		bitmap.y = TEXT_Y - pad;
	}

	/**
		Flash's outer GlowFilter on `data` in place: the source alpha is blurred
		by `quality` box-blur passes `blur` pixels wide in each direction, scaled
		by `strength` and clamped, coloured `color`, and composited under the
		source. Lime's software GlowFilter uses a different, longer-tailed kernel
		and ignores strength, which drew a wider, softer halo than Flash.
	**/
	public static function applyFlashGlow(data:BitmapData, blur:Float, strength:Float, quality:Int, color:Int):Void {
		var width = data.width;
		var height = data.height;
		var pixels = data.getVector(data.rect);
		var count = width * height;
		var alpha = new haxe.ds.Vector<Float>(count);
		for (index in 0...count) alpha[index] = ((pixels[index] >>> 24) & 0xFF) / 255;
		pr2.runtime.AlphaBlur.blurAlpha(alpha, width, height, blur, quality);
		var glowRed = (color >> 16) & 0xFF;
		var glowGreen = (color >> 8) & 0xFF;
		var glowBlue = color & 0xFF;
		for (index in 0...count) {
			var glow = alpha[index] * strength;
			if (glow > 1) glow = 1;
			var pixel = pixels[index];
			var sourceAlpha = ((pixel >>> 24) & 0xFF) / 255;
			var outAlpha = sourceAlpha + glow * (1 - sourceAlpha);
			if (outAlpha <= 0) {
				pixels[index] = 0;
				continue;
			}
			var glowWeight = glow * (1 - sourceAlpha);
			var red = (((pixel >> 16) & 0xFF) * sourceAlpha + glowRed * glowWeight) / outAlpha;
			var green = (((pixel >> 8) & 0xFF) * sourceAlpha + glowGreen * glowWeight) / outAlpha;
			var blue = ((pixel & 0xFF) * sourceAlpha + glowBlue * glowWeight) / outAlpha;
			pixels[index] = (Math.round(outAlpha * 255) << 24) | (Math.round(red) << 16) | (Math.round(green) << 8) | Math.round(blue);
		}
		data.setVector(data.rect, pixels);
	}

	/** Device pixels per stage pixel. **/
	private function outputScale():Float {
		var scale = 1.0;
		if (stage != null) {
			var display = stage.__displayMatrix;
			scale = Math.sqrt(Math.abs(display.a * display.d - display.b * display.c));
		}
		// Keep the bitmap reasonable on very large displays.
		return Math.max(1, Math.min(scale, 8));
	}
	#end

	private static function createText():TextField {
		var text = new TextField();
		var format = new TextFormat(FontResolver.resolve("Gwibble"), 43, 0x000000, false, false, false, null, null, TextFormatAlign.CENTER, 0, 0, 0, -3);
		text.defaultTextFormat = format;
		text.embedFonts = true;
		text.width = TEXT_WIDTH;
		text.height = TEXT_HEIGHT;
		text.autoSize = TextFieldAutoSize.NONE;
		text.selectable = false;
		text.mouseEnabled = false;
		text.multiline = true;
		text.wordWrap = false;
		text.text = "Platform Racing\n-- 2 --";
		text.setTextFormat(format);
		return text;
	}
}

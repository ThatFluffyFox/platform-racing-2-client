package pr2.page;

import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.filters.GlowFilter;
import openfl.geom.ColorTransform;
import openfl.geom.Matrix;
import openfl.geom.Point;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import pr2.runtime.FontResolver;

/**
	The "Platform Racing 2" logo on the login page.

	In the XFL LoginPage symbol (Layer 7) this is live Gwibble text with a
	white glow (blur 6, strength 2, quality 3). Geometry mirrors the
	DOMStaticText: tx/ty 81.4/92.4, box 386.8 wide, size 43, centered,
	lineSpacing -3.

	On HTML5, OpenFL draws filtered objects into a cache sized for the 550x400
	stage and stretches it to the window, which blurs the logo. Flash drew the
	glow at the output resolution, so here the text and glow are drawn into a
	bitmap at the stage's on-screen scale and shown at 1:1 device pixels. The
	bitmap is redrawn when the window's scale changes.
**/
@:access(openfl.display.Stage)
class LoginTitle extends Sprite {
	private static inline var TEXT_X:Float = 81.4;
	private static inline var TEXT_Y:Float = 92.4;
	private static inline var TEXT_WIDTH:Float = 386.8;
	private static inline var TEXT_HEIGHT:Float = 120;
	private static inline var GLOW_BLUR:Float = 6;
	// Room for the glow around the text box, in stage pixels.
	private static inline var GLOW_PAD:Float = 8;
	private static inline var GLOW_STRENGTH:Float = 2;

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
		text.filters = [new GlowFilter(0xFFFFFF, 1, GLOW_BLUR, GLOW_BLUR, 2, 3)];
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

		// Glow first (OpenFL's GlowFilter output holds only the glow), then the
		// text drawn over it, as Flash composites an outer glow.
		data.draw(text, matrix, null, null, null, true);
		var blur = GLOW_BLUR * scale;
		data.applyFilter(data, data.rect, new Point(0, 0), new GlowFilter(0xFFFFFF, 1, blur, blur, 1, 3));
		// Lime's software blur ignores strength; Flash multiplies the glow's
		// alpha by it (clamped), which gives the logo its solid white rim.
		data.colorTransform(data.rect, new ColorTransform(1, 1, 1, GLOW_STRENGTH));
		data.draw(text, matrix, null, null, null, true);

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

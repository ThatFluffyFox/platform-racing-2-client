package pr2.ui;

import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.DisplayObject;
import openfl.display.PixelSnapping;
import openfl.display.Shape;
import openfl.events.Event;
import openfl.filters.DropShadowFilter;
import openfl.geom.Matrix;
import openfl.geom.Rectangle;
import pr2.assets.NativeAssetIds.StaticSvg;
import pr2.runtime.SvgAsset;

/**
	Flash `UI/ShadowBG`: the 272x191 panel (90% white, 4px rounded top corners)
	under a 9-slice grid, over a knocked-out DropShadowFilter of the same
	rectangle (black 60%, blur 3, 2px down, 2 passes).

	OpenFL never drew a filter on a 9-slice shape, so every popup built on
	ShadowBG lost its shadow. On HTML5 the shadow is a baked bitmap placed
	directly beneath the panel in its parent while the panel is on stage. Like a
	Flash filter it is sized in screen pixels (the blur does not grow or shrink
	with the panel's scale), and it is left out of the parent's bounds and hit
	tests, as Flash measures a filtered object without its filter. Other targets
	render the filter on the shape itself.
**/
class ShadowBgShape extends Shape {
	public static inline var NATURAL_WIDTH:Float = 272;
	public static inline var NATURAL_HEIGHT:Float = 191;

	#if (js && html5)
	private var shadow:Null<ShadowBitmap>;
	#end

	public function new() {
		super();
		graphics.copyFrom(SvgAsset.create(StaticSvg.QuantityPanel).graphics);
		scale9Grid = new Rectangle(4.65, 6.65, 262.95, 180.05);
		#if (js && html5)
		addEventListener(Event.ADDED_TO_STAGE, addedToStage);
		addEventListener(Event.REMOVED_FROM_STAGE, removedFromStage);
		#else
		filters = [new DropShadowFilter(2, 90, 0x000000, 0.6, 3, 3, 1, 2, false, false)];
		#end
	}

	#if (js && html5)
	private function addedToStage(_:Event):Void {
		addEventListener(Event.ENTER_FRAME, sync);
		sync(null);
	}

	private function removedFromStage(_:Event):Void {
		removeEventListener(Event.ENTER_FRAME, sync);
		if (shadow != null) {
			shadow.dispose();
			shadow = null;
		}
	}

	/** Keeps the shadow under the panel, at its on-screen size. **/
	private function sync(_:Null<Event>):Void {
		var holder = parent;
		if (holder == null || stage == null) return;
		if (shadow == null) {
			shadow = new ShadowBitmap();
		}
		if (shadow.parent != holder || holder.getChildIndex(shadow) != holder.getChildIndex(this) - 1) {
			if (shadow.parent != null) shadow.parent.removeChild(shadow);
			holder.addChildAt(shadow, holder.getChildIndex(this));
		}
		shadow.visible = visible;
		shadow.alpha = alpha;
		// The panel's rectangle in stage pixels; Flash filters work at that scale.
		var toStage = holder.transform.concatenatedMatrix;
		var topLeft = toStage.transformPoint(new openfl.geom.Point(x, y));
		var bottomRight = toStage.transformPoint(new openfl.geom.Point(x + NATURAL_WIDTH * scaleX, y + NATURAL_HEIGHT * scaleY));
		var stageRect = new Rectangle(Math.min(topLeft.x, bottomRight.x), Math.min(topLeft.y, bottomRight.y),
			Math.abs(bottomRight.x - topLeft.x), Math.abs(bottomRight.y - topLeft.y));
		shadow.update(stageRect, deviceScale(), holder);
	}

	private function deviceScale():Float {
		@:privateAccess var display = stage.__displayMatrix;
		var scale = Math.sqrt(Math.abs(display.a * display.d - display.b * display.c));
		return Math.max(1, Math.min(scale, 4));
	}
	#end
}

#if (js && html5)
/** The baked shadow: not part of its parent's bounds and never hit. **/
private class ShadowBitmap extends Bitmap {
	private static inline var BLUR:Float = 3;
	private static inline var DISTANCE:Float = 2;
	private static inline var STRENGTH_ALPHA:Float = 0.6;
	private static inline var PASSES:Int = 2;
	// The two-pass blur reaches BLUR px past the edge; the shadow sits DISTANCE down.
	private static inline var PAD:Float = 4;

	private var bakedWidth:Float = -1;
	private var bakedHeight:Float = -1;
	private var bakedDensity:Float = -1;

	public function new() {
		super(null, PixelSnapping.NEVER, true);
	}

	public function update(stageRect:Rectangle, density:Float, holder:DisplayObject):Void {
		if (Math.abs(stageRect.width - bakedWidth) > 0.01 || Math.abs(stageRect.height - bakedHeight) > 0.01
			|| Math.abs(density - bakedDensity) > 0.001) {
			bake(stageRect.width, stageRect.height, density);
		}
		// Place the bitmap's stage-pixel rectangle in the holder's coordinates.
		var matrix = new Matrix(1 / density, 0, 0, 1 / density, stageRect.x - PAD, stageRect.y - PAD);
		var toLocal = holder.transform.concatenatedMatrix.clone();
		toLocal.invert();
		matrix.concat(toLocal);
		transform.matrix = matrix;
	}

	/**
		The blurred rectangle factors into a horizontal and a vertical profile, so
		the two-pass box blur runs on two short lines instead of every pixel. The
		knockout keeps only what lies outside the panel.
	**/
	private function bake(width:Float, height:Float, density:Float):Void {
		bakedWidth = width;
		bakedHeight = height;
		bakedDensity = density;
		if (bitmapData != null) bitmapData.dispose();
		var pixelWidth = Std.int(Math.max(1, Math.ceil((width + PAD * 2) * density)));
		var pixelHeight = Std.int(Math.max(1, Math.ceil((height + PAD * 2) * density)));
		var shadowX = profile(pixelWidth, PAD, PAD + width, density);
		var shadowY = profile(pixelHeight, PAD + DISTANCE, PAD + DISTANCE + height, density);
		var panelX = coverage(pixelWidth, PAD, PAD + width, density);
		var panelY = coverage(pixelHeight, PAD, PAD + height, density);
		var pixels = new openfl.Vector<UInt>(pixelWidth * pixelHeight);
		for (row in 0...pixelHeight) {
			for (column in 0...pixelWidth) {
				var alpha = STRENGTH_ALPHA * shadowX[column] * shadowY[row] * (1 - panelX[column] * panelY[row]);
				pixels[row * pixelWidth + column] = Std.int(Math.round(alpha * 255)) << 24;
			}
		}
		var data = new BitmapData(pixelWidth, pixelHeight, true, 0);
		data.setVector(data.rect, pixels);
		bitmapData = data;
		smoothing = true;
	}

	/** Pixel coverage of [start, end) (in unscaled units) along a line. **/
	private static function coverage(length:Int, start:Float, end:Float, density:Float):haxe.ds.Vector<Float> {
		var line = new haxe.ds.Vector<Float>(length);
		var from = start * density;
		var to = end * density;
		for (index in 0...length) {
			var overlap = Math.min(index + 1, to) - Math.max(index, from);
			line[index] = overlap <= 0 ? 0 : (overlap >= 1 ? 1 : overlap);
		}
		return line;
	}

	/** The interval's coverage after Flash's two-pass BLUR-pixel box blur. **/
	private static function profile(length:Int, start:Float, end:Float, density:Float):haxe.ds.Vector<Float> {
		var line = coverage(length, start, end, density);
		var scratch = new haxe.ds.Vector<Float>(length);
		for (_ in 0...PASSES) {
			pr2.runtime.AlphaBlur.boxBlur(line, scratch, length, 1, BLUR * density, true);
			for (index in 0...length) line[index] = scratch[index];
		}
		return line;
	}

	public function dispose():Void {
		if (parent != null) parent.removeChild(this);
		if (bitmapData != null) {
			bitmapData.dispose();
			bitmapData = null;
		}
	}

	@:noCompletion override private function __getBounds(rect:Rectangle, matrix:Matrix):Void {}

	@:noCompletion override private function __getRenderBounds(rect:Rectangle, matrix:Matrix):Void {
		super.__getBounds(rect, matrix);
	}

	@:noCompletion override private function __hitTest(x:Float, y:Float, shapeFlag:Bool, stack:Array<DisplayObject>, interactiveOnly:Bool,
			hitObject:DisplayObject):Bool {
		return false;
	}
}
#end

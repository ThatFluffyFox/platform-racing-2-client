package pr2.lobby.account;

import openfl.display.BitmapData;
import openfl.display.Bitmap;
import openfl.display.DisplayObject;
import openfl.display.Sprite;
import openfl.display.Stage;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.geom.Matrix;
import openfl.geom.Point;
import pr2.assets.NativeAssetIds.StaticSvg;
import pr2.assets.NativeAssets;
import pr2.ui.CustomCursor;

/**
	Port of `com.jiggmin.ColorPicker.CursorEyedropper`.
**/
class CursorEyedropper extends CustomCursor {
	public var color:Int = -1;

	private var exclusions:Array<DisplayObject> = [];
	private var cursorContainer:Null<BitmapData>;
	private var sampleSource:Null<DisplayObject>;

	public function new(?sampleSource:DisplayObject) {
		super();
		visible = false;
		applyCursorGraphic(makeCursorGraphic());
		this.sampleSource = sampleSource;
		ensureBitmap();
	}

	private function makeCursorGraphic():DisplayObject {
		// Keep the linkage root separate from Symbol 1303. CustomCursor centers the
		// root, while the authored child retains this registration transform.
		var root = new Sprite();
		root.name = "eyedropperRoot";
		var art = new Sprite();
		art.name = "eyedropperArt";
		art.addChild(NativeAssets.svg(StaticSvg.EyedropperBack));
		art.addChild(NativeAssets.svg(StaticSvg.EyedropperFront));
		art.scaleX = art.scaleY = 0.681365966796875;
		art.x = 6.4;
		art.y = -8.4;
		root.addChild(art);
		return root;
	}

	override public function init():Void {
		super.init();
		visible = false;
		// Presentation-rate by design: sample the latest pointer/display state.
		addEventListener(Event.ENTER_FRAME, maybeUpdate);
	}

	override public function pause():Void {
		super.pause();
		removeEventListener(Event.ENTER_FRAME, maybeUpdate);
	}

	public function addExclusion(d:DisplayObject):Void {
		exclusions.push(d);
	}

	override public function remove():Void {
		showMouse();
		super.remove();
		if (cursorContainer != null) {
			cursorContainer.dispose();
			cursorContainer = null;
		}
		exclusions = [];
		sampleSource = null;
	}

	private function maybeUpdate(_:Event):Void {
		if (!pr2.runtime.FrameClock.shouldRunBrowserFrame()) return;
		var me = getMouse();
		var targetObj = me != null ? Std.downcast(me.target, DisplayObject) : null;
		if (targetObj == null && sampleSource != null) {
			targetObj = sampleSource;
		}
		if (targetObj == null) {
			return;
		}
		var useEyedropper = true;
		while (targetObj.parent != null) {
			if (isExcluded(targetObj)) {
				useEyedropper = false;
				break;
			}
			targetObj = targetObj.parent;
		}
		if (useEyedropper) {
			if (!visible) {
				visible = true;
				hideMouse();
				drawEyedropper();
			}
			#if html5
			// Sampling the Stage draws the display list. Doing that every frame
			// (Flash read an already-cached BitmapData) stalls the editor while the
			// picker is open, so the Stage is sampled once, on click, below.
			if (Std.isOfType(currentSampleSource(), Stage)) {
				return;
			}
			#end
			updateColor();
			dispatchEvent(new Event(Event.CHANGE));
		} else if (visible) {
			visible = false;
			showMouse();
			color = -1;
			dispatchEvent(new Event(Event.CHANGE));
		}
	}

	override function mouseDownHandler(e:MouseEvent):Void {
		if (visible) {
			e.stopImmediatePropagation();
			var editor = pr2.levelEditor.LevelEditor.editor;
			var layer = e.shiftKey && editor != null ? editor.eyedropperLayer() : null;
			if (layer != null) {
				// Level Editor: Shift picks from the layer being edited only, not the
				// screen. An empty spot on that layer picks nothing.
				var sampled = sampleLayerPixel(layer, CustomCursor.eventStagePoint(e));
				if (sampled != null) {
					color = sampled;
					dispatchEvent(new Event(Event.COMPLETE));
				}
				super.mouseDownHandler(e);
				return;
			}
			#if html5
			var sourceStage = Std.downcast(currentSampleSource(), Stage);
			if (sourceStage != null) {
				color = sampleStagePixel(sourceStage, CustomCursor.eventStagePoint(e));
				dispatchEvent(new Event(Event.COMPLETE));
				super.mouseDownHandler(e);
				return;
			}
			#end
			drawEyedropper();
			updateColor();
			dispatchEvent(new Event(Event.COMPLETE));
		}
		super.mouseDownHandler(e);
	}

	private function drawEyedropper():Void {
		if (!visible) {
			return;
		}
		var source = currentSampleSource();
		if (source == null) {
			return;
		}
		#if html5
		// The browser already has the completed game frame in its canvas. Drawing
		// the Stage into BitmapData makes OpenFL walk the editor's full 60,000px
		// display tree and can stall indefinitely on art-heavy levels.
		if (Std.isOfType(source, Stage)) {
			return;
		}
		#end
		ensureBitmap();
		visible = false;
		cursorContainer.fillRect(cursorContainer.rect, 0);
		var bitmap = Std.downcast(source, Bitmap);
		if (bitmap != null && bitmap.bitmapData != null) {
			cursorContainer.copyPixels(bitmap.bitmapData, bitmap.bitmapData.rect, new Point());
		} else {
			var matrix = new Matrix();
			if (!Std.isOfType(source, Stage)) {
				var bounds = source.getBounds(source);
				if (bounds.left != 0 || bounds.top != 0) {
					matrix.translate(-bounds.left, -bounds.top);
				}
			}
			// Flash captures exactly stageWidth x stageHeight. The editor's stage
			// bounds include its 60,000px world, so an unclipped HTML5 draw can try
			// to allocate a world-sized intermediate canvas and appear to freeze.
			cursorContainer.draw(source, matrix, null, null, cursorContainer.rect);
		}
		visible = true;
	}

	private static function sampleLayerPixel(layer:DisplayObject, stagePoint:Point):Null<Int> {
		var pixel = new BitmapData(1, 1, true, 0);
		var matrix = layer.transform.concatenatedMatrix.clone();
		matrix.translate(-Math.floor(stagePoint.x), -Math.floor(stagePoint.y));
		pixel.draw(layer, matrix, null, null, new openfl.geom.Rectangle(0, 0, 1, 1));
		var argb = pixel.getPixel32(0, 0);
		pixel.dispose();
		if ((argb >>> 24) == 0) return null;
		return argb & 0xFFFFFF;
	}

	private function isExcluded(d:DisplayObject):Bool {
		return exclusions.indexOf(d) != -1;
	}

	private function updateColor():Void {
		var me = getMouse();
		if (me == null) {
			color = -1;
			return;
		}
		var source = currentSampleSource();
		if (source == null) {
			color = -1;
			return;
		}
		#if html5
		var sourceStage = Std.downcast(source, Stage);
		if (sourceStage != null) {
			color = sampleStagePixel(sourceStage, CustomCursor.eventStagePoint(me));
			return;
		}
		#end
		if (cursorContainer == null) {
			color = -1;
			return;
		}
		var stagePoint = CustomCursor.eventStagePoint(me);
		var localPoint = source.stage == null ? stagePoint : source.globalToLocal(stagePoint);
		var px = clamp(Math.floor(localPoint.x), 0, cursorContainer.width - 1);
		var py = clamp(Math.floor(localPoint.y), 0, cursorContainer.height - 1);
		color = cursorContainer.getPixel(px, py);
	}

	#if html5
	/**
		Read the clicked pixel from the screen as Flash's eyedropper did, with the
		eyedropper itself hidden. WebGL clears the canvas once the browser has
		shown a frame, so reading it from an input handler gave black or nothing
		depending on browser timing. Render a fresh frame first, then read the
		pixel in the same moment. Drawing the stage into a BitmapData instead uses
		OpenFL's canvas renderer, which draws tinted character art in the wrong
		colours.
	**/
	private function sampleStagePixel(sourceStage:Stage, stagePoint:Point):Int {
		var wasVisible = visible;
		visible = false;
		var sampled = -1;
		try {
			var window = sourceStage.window;
			var gl:Dynamic = window == null ? null : window.context.webgl;
			if (gl != null) {
				@:privateAccess {
					sourceStage.__renderDirty = true;
					sourceStage.__render(window.context);
				}
				var display:Matrix = @:privateAccess sourceStage.__displayMatrix;
				var point = display.transformPoint(stagePoint);
				var width:Int = gl.drawingBufferWidth;
				var height:Int = gl.drawingBufferHeight;
				var px = clamp(Math.floor(point.x), 0, width - 1);
				var py = clamp(Math.floor(point.y), 0, height - 1);
				var pixels = new js.lib.Uint8Array(4);
				gl.readPixels(px, height - 1 - py, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
				sampled = (pixels[0] << 16) | (pixels[1] << 8) | pixels[2];
			}
		} catch (_:Dynamic) {}
		visible = wasVisible;
		return sampled;
	}
	#end

	private function ensureBitmap():Void {
		var source = currentSampleSource();
		var width = 1;
		var height = 1;
		var sourceStage = Std.downcast(source, Stage);
		if (sourceStage != null) {
			width = Std.int(Math.max(1, sourceStage.stageWidth));
			height = Std.int(Math.max(1, sourceStage.stageHeight));
		} else if (source != null) {
			var bounds = source.getBounds(source);
			width = Std.int(Math.max(1, Math.ceil(bounds.width)));
			height = Std.int(Math.max(1, Math.ceil(bounds.height)));
		}
		if (cursorContainer == null || cursorContainer.width != width || cursorContainer.height != height) {
			if (cursorContainer != null) {
				cursorContainer.dispose();
			}
			cursorContainer = new BitmapData(width, height, false, 0);
		}
	}

	public function captureWidthForTests():Int {
		return cursorContainer == null ? 0 : cursorContainer.width;
	}

	public function captureHeightForTests():Int {
		return cursorContainer == null ? 0 : cursorContainer.height;
	}

	private function currentSampleSource():Null<DisplayObject> {
		if (sampleSource != null) {
			return sampleSource;
		}
		return currentStage();
	}

	private static function clamp(value:Float, minimum:Int, maximum:Int):Int {
		return Std.int(Math.max(minimum, Math.min(maximum, value)));
	}
}

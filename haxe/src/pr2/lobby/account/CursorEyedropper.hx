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
	#if html5
	/** Flash's cursorContainer: the frame captured when the eyedropper appears. */
	private var frameCapture:Null<js.lib.Uint8Array>;
	private var frameCaptureWidth:Int = 0;
	private var frameCaptureHeight:Int = 0;
	#end

	public function new(?sampleSource:DisplayObject) {
		super();
		visible = false;
		// Flash adds CursorEyedropperGraphic with addChild, not applyCursorGraphic,
		// so it is not centred: Symbol 1304's registration puts the dropper's tip
		// on the pointer, where the colour is read. Centring it drew the tip up and
		// to the left of the sampled point.
		var graphic = makeCursorGraphic();
		var interactive = Std.downcast(graphic, openfl.display.InteractiveObject);
		if (interactive != null) interactive.mouseEnabled = false;
		addChild(graphic);
		this.sampleSource = sampleSource;
		ensureBitmap();
	}

	private function makeCursorGraphic():DisplayObject {
		// CursorEyedropperGraphic (Symbol 1304) holds Symbol 1303 under this
		// registration transform.
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
		#if html5
		frameCapture = null;
		#end
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
		// Like Flash, capture the screen once when the eyedropper appears; hover
		// previews then read from that capture.
		var captureStage = Std.downcast(source, Stage);
		if (captureStage != null) {
			captureFrame(captureStage);
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
			color = capturedPixel(sourceStage, CustomCursor.eventStagePoint(me));
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
		var sampled = -1;
		withFreshFrame(sourceStage, function(gl:Dynamic, width:Int, height:Int):Void {
			var pixel = bufferPixel(sourceStage, stagePoint, width, height);
			var pixels = new js.lib.Uint8Array(4);
			gl.readPixels(pixel.x, height - 1 - pixel.y, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
			sampled = (pixels[0] << 16) | (pixels[1] << 8) | pixels[2];
		});
		return sampled;
	}

	private function captureFrame(sourceStage:Stage):Void {
		frameCapture = null;
		withFreshFrame(sourceStage, function(gl:Dynamic, width:Int, height:Int):Void {
			var pixels = new js.lib.Uint8Array(width * height * 4);
			gl.readPixels(0, 0, width, height, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
			frameCapture = pixels;
			frameCaptureWidth = width;
			frameCaptureHeight = height;
		});
	}

	private function capturedPixel(sourceStage:Stage, stagePoint:Point):Int {
		if (frameCapture == null) return -1;
		var pixel = bufferPixel(sourceStage, stagePoint, frameCaptureWidth, frameCaptureHeight);
		var index = ((frameCaptureHeight - 1 - pixel.y) * frameCaptureWidth + pixel.x) * 4;
		return (frameCapture[index] << 16) | (frameCapture[index + 1] << 8) | frameCapture[index + 2];
	}

	/** Render a frame with the eyedropper hidden and read it before the browser clears it. */
	private function withFreshFrame(sourceStage:Stage, read:(Dynamic, Int, Int) -> Void):Void {
		var wasVisible = visible;
		visible = false;
		try {
			var window = sourceStage.window;
			var gl:Dynamic = window == null ? null : window.context.webgl;
			if (gl != null) {
				@:privateAccess {
					sourceStage.__renderDirty = true;
					sourceStage.__render(window.context);
				}
				read(gl, gl.drawingBufferWidth, gl.drawingBufferHeight);
			}
		} catch (_:Dynamic) {}
		visible = wasVisible;
	}

	/** The drawing-buffer pixel under a stage point, through the renderer's display matrix. */
	private static function bufferPixel(sourceStage:Stage, stagePoint:Point, width:Int, height:Int):{x:Int, y:Int} {
		var display:Matrix = @:privateAccess sourceStage.__displayMatrix;
		var point = display.transformPoint(stagePoint);
		return {x: clamp(Math.floor(point.x), 0, width - 1), y: clamp(Math.floor(point.y), 0, height - 1)};
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

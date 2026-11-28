package pr2.ui.controls;

import openfl.events.Event;
import openfl.events.KeyboardEvent;
import openfl.events.MouseEvent;
import openfl.display.Sprite;
import openfl.geom.Point;
import openfl.ui.Keyboard;
import pr2.runtime.SvgAsset;

class GameSlider extends NativeControl {
	// Flash's fl.controls.Slider anchors both the SliderThumb skin (13px) and the
	// SliderTrack skin (3px) to the component's top-left origin. The port had
	// centred the track inside the thumb (track.y = (13-3)/2), which pushed the
	// bar exactly 5px below where Flash renders it while the thumb stayed correct.
	private static inline var TRACK_HEIGHT:Float = 4;

	public var minimum(default, null):Float;
	public var maximum(default, null):Float;
	public var step(default, null):Float;
	public var value(default, set):Float;
	public var onChange:Null<Float->Void>;
	public var onRelease:Null<Void->Void>;
	private final track:Sprite;
	private final thumb:Sprite;
	private var dragging:Bool = false;
	private var thumbHovered:Bool = false;
	private var thumbPressed:Bool = false;
	private var reversed:Bool = false;

	public function new(minimum:Float = 0, maximum:Float = 10, value:Float = 0, step:Float = 1, ?skin:ControlSkin) {
		if (maximum < minimum || step <= 0) throw "Invalid slider range";
		super(100, 22, skin == null ? new SliderControlSkin() : skin);
		this.minimum = minimum;
		this.maximum = maximum;
		this.step = step;
		graphics.clear();
		track = new Sprite();
		track.mouseEnabled = false;
		track.mouseChildren = false;
		addChild(track);
		thumb = new Sprite();
		thumb.mouseChildren = false;
		addChild(thumb);
		thumb.addEventListener(MouseEvent.ROLL_OVER, thumbOver);
		thumb.addEventListener(MouseEvent.ROLL_OUT, thumbOut);
		thumb.addEventListener(MouseEvent.MOUSE_DOWN, thumbDown);
		drawTrack();
		this.value = value;
		addEventListener(KeyboardEvent.KEY_DOWN, adjustFromKey);
		addEventListener(MouseEvent.MOUSE_DOWN, beginDrag);
		addEventListener(MouseEvent.CLICK, selectFromMouse);
	}

	public function setValueFromUser(next:Float):Void {
		if (!enabled || disposed) return;
		var before = value;
		value = next;
		if (value != before) { if (onChange != null) onChange(value); dispatchEvent(new Event(Event.CHANGE)); }
	}

	public function setReversed(value:Bool):Void {
		reversed = value;
		drawThumb();
	}

	override public function setSize(width:Float, height:Float):Void { super.setSize(width, height); graphics.clear(); drawTrack(); drawThumb(); }
	override public function enabledChanged(value:Bool):Void {
		graphics.clear();
		if (!value) {
			thumbHovered = false;
			thumbPressed = false;
		}
		drawTrack();
		drawThumb();
	}
	override public function dispose():Void {
		removeEventListener(KeyboardEvent.KEY_DOWN, adjustFromKey);
		removeEventListener(MouseEvent.MOUSE_DOWN, beginDrag);
		removeEventListener(MouseEvent.CLICK, selectFromMouse);
		thumb.removeEventListener(MouseEvent.ROLL_OVER, thumbOver);
		thumb.removeEventListener(MouseEvent.ROLL_OUT, thumbOut);
		thumb.removeEventListener(MouseEvent.MOUSE_DOWN, thumbDown);
		removeStageDragListeners();
		onChange = null;
		onRelease = null;
		super.dispose();
	}
	private function set_value(next:Float):Float {
		var clamped = Math.max(minimum, Math.min(maximum, next));
		value = minimum + Math.round((clamped - minimum) / step) * step;
		redraw();
		if (thumb != null) drawThumb();
		return value;
	}
	private function selectFromMouse(event:MouseEvent):Void setValueFromPosition(pointerLocalX(event));
	private function beginDrag(event:MouseEvent):Void {
		if (!enabled || stage == null) return;
		dragging = true;
		setValueFromPosition(pointerLocalX(event));
		stage.addEventListener(MouseEvent.MOUSE_MOVE, drag);
		stage.addEventListener(MouseEvent.MOUSE_UP, endDrag);
	}
	private function drag(event:MouseEvent):Void {
		if (!dragging) return;
		setValueFromPosition(pointerLocalX(event));
	}
	private function pointerLocalX(event:MouseEvent):Float return globalToLocal(new Point(event.stageX, event.stageY)).x;
	private function endDrag(_:MouseEvent):Void {
		if (!dragging) return;
		dragging = false;
		thumbPressed = false;
		drawThumb();
		removeStageDragListeners();
		if (onRelease != null) onRelease();
	}
	private function removeStageDragListeners():Void {
		if (stage == null) return;
		stage.removeEventListener(MouseEvent.MOUSE_MOVE, drag);
		stage.removeEventListener(MouseEvent.MOUSE_UP, endDrag);
	}
	private function setValueFromPosition(localX:Float):Void {
		// fl.controls.Slider.calculateValue maps the track's full width.
		var ratio = Math.max(0, Math.min(1, localX / Math.max(1, controlWidth)));
		if (reversed) ratio = 1 - ratio;
		setValueFromUser(minimum + (maximum - minimum) * ratio);
	}
	private function drawThumb():Void {
		if (thumb == null) return;
		var ratio = maximum == minimum ? 0 : (value - minimum) / (maximum - minimum);
		if (reversed) ratio = 1 - ratio;
		while (thumb.numChildren > 0) thumb.removeChildAt(0);
		var path = !enabled ? "assets/svg/ui/slider_thumb_disabled.svg" : (thumbPressed ? "assets/svg/ui/slider_thumb_down.svg" : (thumbHovered ?
			"assets/svg/ui/slider_thumb_over.svg" : "assets/svg/ui/slider_thumb_up.svg"));
		thumb.addChild(SvgAsset.create(path));
		// fl.controls.Slider.positionThumb: the centred SliderThumb skin runs
		// from x 0 to the full component width.
		thumb.x = ratio * controlWidth;
		thumb.y = 0;
	}

	/**
		SliderTrack_skin / SliderTrack_disabledSkin, drawn directly: four 1px bands
		on an 80x3 skin, stretched through Flash's 9-slice grid (x 2.25..78) to the
		component width and 4px tall (configUI's track.setSize(80, 4)). OpenFL's
		scale9Grid ignores the parent's scale, so inside a scaled owner (the
		level-editor test's 0.66 stats picker) the old scale9 shape shrank a second
		time and the track ended well short of the thumb's range.
	**/
	private function drawTrack():Void {
		if (track == null) return;
		while (track.numChildren > 0) track.removeChildAt(0);
		var g = track.graphics;
		g.clear();
		var stretch = controlWidth - 80;
		var middle = (78 - 2.25 + stretch) / (78 - 2.25);
		inline function mx(x:Float):Float return x <= 2.25 ? x : (x >= 78 ? x + stretch : 2.25 + (x - 2.25) * middle);
		var sy = TRACK_HEIGHT / 3;
		function band(color:Int, x0:Float, y0:Float, x1:Float, y1:Float):Void {
			g.beginFill(color);
			g.drawRect(mx(x0), y0 * sy, mx(x1) - mx(x0), (y1 - y0) * sy);
			g.endFill();
		}
		// Band colours in SWF draw order: corner pixels, lower band, top edge, highlight.
		var corner = enabled ? 0x8C9295 : 0xBBBBBB;
		var lower = enabled ? 0xAEB2B4 : 0xCCCCCC;
		var edge = enabled ? 0x575E62 : 0x999999;
		band(corner, 1, 2, 2, 3);
		band(corner, 0, 1, 1, 2);
		band(corner, 79, 1, 80, 2);
		band(corner, 78, 2, 79, 3);
		band(lower, 2, 2, 78, 3);
		if (enabled) {
			band(edge, 1, 0, 79, 1);
			band(0xEBEBEB, 1, 1, 79, 2);
		} else {
			band(0xEBEBEB, 1, 1, 79, 2);
			band(edge, 1, 0, 79, 1);
		}
		track.y = 0;
	}

	private function thumbOver(_:MouseEvent):Void { if (enabled) { thumbHovered = true; drawThumb(); } }
	private function thumbOut(_:MouseEvent):Void { if (!thumbPressed) { thumbHovered = false; drawThumb(); } }
	private function thumbDown(_:MouseEvent):Void { if (enabled) { thumbPressed = true; drawThumb(); } }

	@:noCompletion public function thumbAssetForTests():String return !enabled ? "slider_thumb_disabled" : (thumbPressed ? "slider_thumb_down" :
		(thumbHovered ? "slider_thumb_over" : "slider_thumb_up"));
	@:noCompletion public function trackAssetForTests():String return enabled ? "slider_track_up" : "slider_track_disabled";

	@:noCompletion public function setValueFromPositionForTests(localX:Float):Void setValueFromPosition(localX);
	@:noCompletion public function thumbLocalXForTests():Float return thumb.x;
	private function adjustFromKey(event:KeyboardEvent):Void {
		if (event.keyCode == Keyboard.LEFT || event.keyCode == Keyboard.DOWN) setValueFromUser(value - step);
		if (event.keyCode == Keyboard.RIGHT || event.keyCode == Keyboard.UP) setValueFromUser(value + step);
		if (event.keyCode == Keyboard.HOME) setValueFromUser(minimum);
		if (event.keyCode == Keyboard.END) setValueFromUser(maximum);
	}
}

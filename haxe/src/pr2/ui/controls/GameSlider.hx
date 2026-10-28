package pr2.ui.controls;

import openfl.events.Event;
import openfl.events.KeyboardEvent;
import openfl.events.MouseEvent;
import openfl.display.Sprite;
import openfl.geom.Point;
import openfl.geom.Rectangle;
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
		// fl.controls.Slider maps the full track width to the value range.
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
		// fl.controls.Slider.positionThumb: thumb.x = ratio * width. The
		// SliderThumb skin is centred on its origin, so the thumb's centre sits
		// over the track's ends at the minimum and maximum.
		thumb.x = ratio * controlWidth;
		thumb.y = 0;
	}

	private function drawTrack():Void {
		if (track == null) return;
		while (track.numChildren > 0) track.removeChildAt(0);
		var art = SvgAsset.create(enabled ? "assets/svg/ui/slider_track_up.svg" : "assets/svg/ui/slider_track_disabled.svg");
		art.scale9Grid = new Rectangle(2.25, 0, 75.75, 3);
		art.width = controlWidth;
		// fl.controls.Slider sizes its track button to 4px tall (configUI's
		// track.setSize(80, 4)). The skin's vertical grid (-1..3.95) spans all
		// three 1px bands, so each band stretches to 1.33px.
		art.height = TRACK_HEIGHT;
		track.addChild(art);
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

package pr2.ui.controls;

import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.FocusEvent;
import openfl.events.KeyboardEvent;
import openfl.events.MouseEvent;
import openfl.geom.Rectangle;
import pr2.assets.NativeAssetIds.StaticSvg;
import pr2.assets.NativeAssets;

class NativeControl extends Sprite {
	public static inline var KEYBOARD_ACTIVATE:String = "nativeControlKeyboardActivate";
	private static final FOCUS_GRID = new Rectangle(4, 2, 74, 18);

	// Flash's fl.managers.FocusManager only paints focus rectangles while
	// showFocusIndicator is true: Tab traversal turns it on, pointer input turns
	// it off. Without that gate every click leaves a blue outline behind.
	public static var showFocusIndicator:Bool = false;
	/**
		True for controls that stand in for a Flash SimpleButton rather than an
		fl.controls component: Flash draws no component focus skin for those, only
		the Flash Player's yellow stage focus rectangle (KeyboardFocusManager).
	**/
	public var flashSimpleButton:Bool = false;

	public var enabled(get, set):Bool;
	public var focused(default, set):Bool = false;
	/** Whether this control's focus was keyboard-driven, so it paints the outline. */
	public var focusVisible(default, null):Bool = false;
	public var disposed(default, null):Bool = false;
	public var controlWidth(default, null):Float;
	public var controlHeight(default, null):Float;
	public var skin:ControlSkin;

	private var _enabled:Bool = true;
	private final focusIndicator:Sprite;
	public var hovered(default, null):Bool = false;
	public var pressed(default, null):Bool = false;

	public function new(width:Float, height:Float, ?skin:ControlSkin) {
		super();
		controlWidth = width;
		controlHeight = height;
		this.skin = skin == null ? new DefaultControlSkin() : skin;
		tabEnabled = true;
		buttonMode = true;
		focusIndicator = new Sprite();
		focusIndicator.mouseEnabled = false;
		focusIndicator.mouseChildren = false;
		addChild(focusIndicator);
		addEventListener(MouseEvent.ROLL_OVER, onRollOver);
		addEventListener(MouseEvent.ROLL_OUT, onRollOut);
		addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
		addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
		addEventListener(FocusEvent.FOCUS_IN, onFocusIn);
		addEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
		addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
		redraw();
		refreshFocusIndicator();
	}

	public function setSize(width:Float, height:Float):Void {
		controlWidth = width;
		controlHeight = height;
		redraw();
		refreshFocusIndicator();
	}

	public function focus():Void {
		if (!enabled || disposed) return;
		focused = true;
		if (stage != null && stage.focus != this) stage.focus = this;
		redraw();
		refreshFocusIndicator();
	}

	public function blur():Void {
		focused = false;
		pressed = false;
		if (stage != null && stage.focus == this) stage.focus = null;
		redraw();
		refreshFocusIndicator();
	}

	public function dispose():Void {
		if (disposed) return;
		disposed = true;
		removeEventListener(MouseEvent.ROLL_OVER, onRollOver);
		removeEventListener(MouseEvent.ROLL_OUT, onRollOut);
		removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
		removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
		removeEventListener(FocusEvent.FOCUS_IN, onFocusIn);
		removeEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
		removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
		focused = false;
		refreshFocusIndicator();
		tabEnabled = false;
		mouseEnabled = false;
		mouseChildren = false;
	}

	public function activate():Void {}

	/** Drops the focus outline without dropping focus itself, for pointer input. */
	public function hideFocusIndicator():Void {
		if (!focusVisible) return;
		focusVisible = false;
		redraw();
		refreshFocusIndicator();
	}

	public function state():ControlState {
		if (!enabled) return Disabled;
		if (pressed) return Pressed;
		if (focused && focusVisible) return Focused;
		if (hovered) return Hovered;
		return Normal;
	}

	public function redraw():Void {
		skin.draw(graphics, controlWidth, controlHeight, state());
	}

	private function set_focused(value:Bool):Bool {
		focusVisible = value && showFocusIndicator;
		return focused = value;
	}

	private function get_enabled():Bool return _enabled;

	private function set_enabled(value:Bool):Bool {
		_enabled = value;
		if (!value) {
			hovered = false;
			pressed = false;
		}
		mouseEnabled = value && !disposed;
		mouseChildren = value && !disposed;
		tabEnabled = value && !disposed;
		buttonMode = value && !disposed;
		enabledChanged(value);
		if (!value) blur(); else {
			redraw();
			refreshFocusIndicator();
		}
		return value;
	}

	public function enabledChanged(value:Bool):Void {}

	private function onRollOver(_):Void { if (enabled) { hovered = true; redraw(); refreshFocusIndicator(); } }
	private function onRollOut(_):Void { hovered = false; pressed = false; redraw(); refreshFocusIndicator(); }
	private function onMouseDown(_):Void { if (enabled) { showFocusIndicator = false; pressed = true; focus(); redraw(); refreshFocusIndicator(); } }
	private function onMouseUp(_):Void { if (enabled) { pressed = false; redraw(); refreshFocusIndicator(); } }
	private function onFocusIn(_):Void {
		focused = true;
		redraw();
		refreshFocusIndicator();
	}

	private function onFocusOut(_):Void {
		// Stage.focus dispatches FOCUS_OUT before it finishes assigning the next
		// target. Calling blur() here would set Stage.focus back to null in the
		// middle of that transition and can leave Tab stuck on this control.
		focused = false;
		pressed = false;
		redraw();
		refreshFocusIndicator();
	}
	private function onKeyDown(event:KeyboardEvent):Void {
		if (!enabled) return;
		if (event.keyCode == 13 || event.keyCode == 32) {
			activate();
			dispatchEvent(new Event(KEYBOARD_ACTIVATE));
		}
	}

	@:noCompletion public function refreshFocusIndicator():Void {
		if (focusIndicator.parent != this) addChild(focusIndicator);
		setChildIndex(focusIndicator, numChildren - 1);
		while (focusIndicator.numChildren > 0) focusIndicator.removeChildAt(0);
		var art = NativeAssets.svg(StaticSvg.FocusRect);
		art.scale9Grid = FOCUS_GRID;
		art.width = controlWidth;
		art.height = controlHeight;
		focusIndicator.addChild(art);
		focusIndicator.visible = focused && focusVisible && enabled && !disposed && !flashSimpleButton;
	}
}

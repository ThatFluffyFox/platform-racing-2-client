package pr2.gameplay;

import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import pr2.assets.NativeAssetIds.FontAsset;
import pr2.assets.NativeAssets;
import pr2.gameplay.player.LocalPlayerInput;

/**
	Race input viewer, toggled with the `/ihud` chat command: shows the keys
	driving the local player each frame (the keyboard, or the Clip Finder's
	"Replay on me" inputs while a replay plays). Left, Down and Right sit in one
	row with Space beside Right, and Up above Down. It sits in the bottom right
	corner, above the mute button.
**/
class InputViewer extends Sprite {
	/** On or off for the whole session (every race). **/
	public static var enabled(default, null):Bool = false;

	public static inline var KEY:Float = 16;
	public static inline var GAP:Float = 2;
	public static inline var SPACE_WIDTH:Float = 34;
	/** Right and bottom edges on the 550x400 stage: just above the mute button (504, 380). **/
	public static inline var RIGHT:Float = 546;
	public static inline var BOTTOM:Float = 376;

	final keys:Array<KeyCap> = [];
	final left:KeyCap;
	final down:KeyCap;
	final right:KeyCap;
	final up:KeyCap;
	final space:KeyCap;

	public static function toggle():Bool {
		enabled = !enabled;
		return enabled;
	}

	public static function setEnabled(value:Bool):Void enabled = value;

	public function new() {
		super();
		mouseEnabled = false;
		mouseChildren = false;
		var row = KEY + GAP;
		left = add("Left", Arrow.Left, 0, row, KEY);
		down = add("Down", Arrow.Down, KEY + GAP, row, KEY);
		right = add("Right", Arrow.Right, 2 * (KEY + GAP), row, KEY);
		space = add("Space", Arrow.None, 3 * (KEY + GAP), row, SPACE_WIDTH);
		up = add("Up", Arrow.Up, KEY + GAP, 0, KEY);
		x = RIGHT - totalWidth;
		y = BOTTOM - totalHeight;
	}

	public static var totalWidth(get, never):Float;
	static inline function get_totalWidth():Float return 3 * (KEY + GAP) + SPACE_WIDTH;
	public static var totalHeight(get, never):Float;
	static inline function get_totalHeight():Float return 2 * KEY + GAP;

	/** Lights the keys held in `input` (jump is Up, item is Space). **/
	public function show(input:LocalPlayerInput):Void {
		left.setPressed(input.left);
		right.setPressed(input.right);
		down.setPressed(input.down);
		up.setPressed(input.jump);
		space.setPressed(input.item);
	}

	/** Names of the keys lit right now ("Left", "Down", "Right", "Space", "Up"). **/
	public function pressedKeys():Array<String> return [for (k in keys) if (k.pressed) k.keyName];

	/** Where a key sits in the viewer (for tests): x, y, width. **/
	public function keyBox(name:String):Null<{x:Float, y:Float, width:Float}> {
		for (k in keys) if (k.keyName == name) return {x: k.x, y: k.y, width: k.keyWidth};
		return null;
	}

	function add(name:String, arrow:Arrow, kx:Float, ky:Float, width:Float):KeyCap {
		var key = new KeyCap(name, arrow, width);
		key.x = kx;
		key.y = ky;
		keys.push(key);
		addChild(key);
		return key;
	}
}

private enum Arrow {
	None;
	Up;
	Down;
	Left;
	Right;
}

private class KeyCap extends Sprite {
	static inline var IDLE_FILL:Int = 0x202020;
	static inline var PRESSED_FILL:Int = 0xF2F2F2;
	static inline var IDLE_INK:Int = 0xDDDDDD;
	static inline var PRESSED_INK:Int = 0x111111;

	public final keyName:String;
	public final keyWidth:Float;
	public var pressed(default, null):Bool = false;

	final arrow:Arrow;
	final face:Shape = new Shape();
	final label:Null<TextField>;
	final idleFormat:Null<TextFormat>;
	final pressedFormat:Null<TextFormat>;

	public function new(name:String, arrow:Arrow, width:Float) {
		super();
		keyName = name;
		this.arrow = arrow;
		keyWidth = width;
		addChild(face);
		if (arrow == None) {
			var font = NativeAssets.font(FontAsset.Interface);
			idleFormat = new TextFormat(font, 9, IDLE_INK, true, null, null, null, null, TextFormatAlign.CENTER);
			pressedFormat = new TextFormat(font, 9, PRESSED_INK, true, null, null, null, null, TextFormatAlign.CENTER);
			var field = new TextField();
			field.selectable = false;
			field.mouseEnabled = false;
			field.width = width;
			field.height = InputViewer.KEY + 2;
			field.y = 1;
			field.defaultTextFormat = idleFormat;
			field.text = name;
			addChild(field);
			label = field;
		} else {
			label = null;
			idleFormat = null;
			pressedFormat = null;
		}
		draw();
	}

	public function setPressed(value:Bool):Void {
		if (value == pressed) return;
		pressed = value;
		draw();
	}

	function draw():Void {
		var g = face.graphics;
		g.clear();
		g.lineStyle(1, 0x000000, 0.9);
		g.beginFill(pressed ? PRESSED_FILL : IDLE_FILL, pressed ? 0.95 : 0.55);
		g.drawRoundRect(0, 0, keyWidth, InputViewer.KEY, 5, 5);
		g.endFill();
		var ink = pressed ? PRESSED_INK : IDLE_INK;
		var cx = keyWidth / 2, cy = InputViewer.KEY / 2, r = 4.0;
		g.lineStyle();
		switch (arrow) {
			case None:
			case Up:
				triangle(g, ink, cx, cy - r, cx + r, cy + r * 0.7, cx - r, cy + r * 0.7);
			case Down:
				triangle(g, ink, cx, cy + r, cx + r, cy - r * 0.7, cx - r, cy - r * 0.7);
			case Left:
				triangle(g, ink, cx - r, cy, cx + r * 0.7, cy - r, cx + r * 0.7, cy + r);
			case Right:
				triangle(g, ink, cx + r, cy, cx - r * 0.7, cy - r, cx - r * 0.7, cy + r);
		}
		if (label != null) label.setTextFormat(pressed ? pressedFormat : idleFormat);
	}

	static function triangle(g:openfl.display.Graphics, color:Int, x1:Float, y1:Float, x2:Float, y2:Float, x3:Float, y3:Float):Void {
		g.beginFill(color, 1);
		g.moveTo(x1, y1);
		g.lineTo(x2, y2);
		g.lineTo(x3, y3);
		g.lineTo(x1, y1);
		g.endFill();
	}
}

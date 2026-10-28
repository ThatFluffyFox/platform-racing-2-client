package pr2.lobby.account;

import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import pr2.assets.NativeAssetIds.FontAsset;
import pr2.assets.NativeAssetIds.StaticSvg;
import pr2.assets.NativeAssets;
import pr2.ui.ArrowButtons;

/**
	Port of Flash `player_profile.PartSelector`: a part stepper (`ArrowButtons`)
	plus a primary colour picker and an epic (second) colour picker that only shows
	for epic parts. Re-dispatches `Event.CHANGE` whenever the part or a colour
	changes. `partArray`/`epicArray` describe which ids are owned and which are epic
	(`"*"` meaning every id is epic).
**/
class PartSelector extends Sprite {
	public var partArray:Array<String>;
	public var epicArray:Array<String>;
	public final infoButton:Sprite;

	private var arrows:ArrowButtons;
	private var cp:ColorPicker;
	private var cp2:ColorPicker;
	private var epicMask:Sprite;
	private var epicOverlay:Sprite;
	private var color:Int = 0;
	private var color2:Int = -1;
	private var value:Int = 0;

	public function new(parts:Array<String>, selected:Int, col:Int, epics:Array<String>, ecol:Int = -1) {
		super();
		this.value = selected;
		this.color = col;
		this.color2 = ecol;
		this.partArray = parts;
		this.epicArray = epics;

		cp = new ColorPicker();
		cp.width = cp.height = 20;
		cp.setColor(color);
		cp.x = 120;
		cp.addEventListener(Event.CHANGE, onColorChange);
		addChild(cp);

		cp2 = new ColorPicker();
		cp2.width = cp2.height = 20;
		cp2.setColor(color2 < 0 ? 0 : color2);
		cp2.x = 120;
		cp2.addEventListener(Event.CHANGE, onColorChange);
		addChild(cp2);

		epicMask = makeTriangleMask(cp.width, cp.height);
		epicMask.x = cp2.x;
		epicMask.y = cp2.y;
		addChild(epicMask);
		cp2.mask = epicMask;

		epicOverlay = makeDiagonalLine(Std.int(cp.width - 6), Std.int(cp.height - 6));
		epicOverlay.x = cp2.x + 3;
		epicOverlay.y = cp2.y + 3;
		addChild(epicOverlay);

		var values = [for (p in parts) Std.parseInt(p) == null ? 0 : Std.parseInt(p)];
		arrows = new ArrowButtons(values, selected);
		arrows.addEventListener(Event.CHANGE, onArrowChange);
		addChild(arrows);

		infoButton = new PartInfoButton();
		infoButton.x = cp.x + 27.5;
		infoButton.y = cp.y + 3;
		addChild(infoButton);

		cpEpicCheck();
	}

	public function getColor():Int {
		return color;
	}

	public function getColorCP2():Int {
		return cp2.getColor();
	}

	public function getColor2():Int {
		return isPartEpic() ? color2 : -1;
	}

	public function getValue():Int {
		return value;
	}

	public function setValue(newVal:Int):Void {
		value = newVal;
		cpEpicCheck();
		arrows.setValue(value);
	}

	public function setColors(newColor:Int, newColor2:Int):Void {
		cp.setColor(newColor);
		cp2.setColor(newColor2 == -1 ? color2 : newColor2);
		color = newColor;
		color2 = newColor2 == -1 ? color2 : newColor2;
		cpEpicCheck();
	}

	public function randomize():Void {
		var newVal = partArray.length == 0 ? value : Std.parseInt(partArray[Std.int(Math.floor(Math.random() * partArray.length))]);
		if (newVal == null) {
			newVal = value;
		}
		setColors(Std.int(Math.random() * 0xFFFFFF), Std.int(Math.random() * 0xFFFFFF));
		setValue(newVal);
	}

	public function isPartEpic(?val:Int):Bool {
		return CustomizationRules.epic(epicArray, val == null ? value : val);
	}

	private function onColorChange(_:Event):Void {
		color = cp.getColor();
		color2 = cp2.getColor();
		dispatchEvent(new Event(Event.CHANGE));
	}

	private function onArrowChange(_:Event):Void {
		value = arrows.value;
		cpEpicCheck();
		dispatchEvent(new Event(Event.CHANGE));
	}

	private function cpEpicCheck():Void {
		var epic = isPartEpic();
		cp2.visible = epic;
		epicOverlay.visible = epic;
	}

	private function makeDiagonalLine(w:Int, h:Int):Sprite {
		var s = new Sprite();
		s.graphics.lineStyle(1, 0);
		s.graphics.moveTo(0, h);
		s.graphics.lineTo(w, 0);
		s.alpha = 0.5;
		s.mouseEnabled = false;
		s.mouseChildren = false;
		return s;
	}

	private function makeTriangleMask(w:Float, h:Float):Sprite {
		var s = new Sprite();
		s.graphics.beginFill(0);
		s.graphics.moveTo(0, h);
		s.graphics.lineTo(w, h);
		s.graphics.lineTo(w, 0);
		s.graphics.lineTo(0, h);
		s.graphics.endFill();
		s.mouseEnabled = false;
		s.mouseChildren = false;
		return s;
	}

	public function remove():Void {
		cast(infoButton, PartInfoButton).dispose();
		cp.removeEventListener(Event.CHANGE, onColorChange);
		cp.remove();
		cp2.removeEventListener(Event.CHANGE, onColorChange);
		cp2.remove();
		arrows.removeEventListener(Event.CHANGE, onArrowChange);
		arrows.remove();
		if (parent != null) {
			parent.removeChild(this);
		}
	}
}

/**
	XFL `Buttons/Symbol 1213` (`InfoButton`): a grey circle with a "?" that
	turns yellow on hover. Flash sizes the instance to 15 x 20.3, which draws
	the 10px circle at 1.2 x 1.29.
**/
private class PartInfoButton extends Sprite {
	private static inline var ART_SCALE_X:Float = 1.2;
	private static inline var ART_SCALE_Y:Float = 1.29;

	private final art = new Sprite();
	private var over = false;
	private var down = false;

	public function new() {
		super();
		buttonMode = useHandCursor = true;
		mouseChildren = false;
		// Hit area of the authored button's hit frame.
		graphics.beginFill(0x000000, 0);
		graphics.drawRect(0, 0, 15, 20);
		graphics.endFill();
		art.scaleX = ART_SCALE_X;
		art.scaleY = ART_SCALE_Y;
		addChild(art);
		addEventListener(MouseEvent.MOUSE_OVER, onOver);
		addEventListener(MouseEvent.MOUSE_OUT, onOut);
		addEventListener(MouseEvent.MOUSE_DOWN, onDown);
		addEventListener(MouseEvent.MOUSE_UP, onUp);
		redraw();
	}

	public function dispose():Void {
		removeEventListener(MouseEvent.MOUSE_OVER, onOver);
		removeEventListener(MouseEvent.MOUSE_OUT, onOut);
		removeEventListener(MouseEvent.MOUSE_DOWN, onDown);
		removeEventListener(MouseEvent.MOUSE_UP, onUp);
	}

	private function onOver(_:MouseEvent):Void {
		over = true;
		redraw();
	}

	private function onOut(_:MouseEvent):Void {
		over = down = false;
		redraw();
	}

	private function onDown(_:MouseEvent):Void {
		down = true;
		redraw();
	}

	private function onUp(_:MouseEvent):Void {
		down = false;
		redraw();
	}

	private function redraw():Void {
		art.removeChildren();
		art.addChild(NativeAssets.svg(down ? StaticSvg.LevelItemInfoDown : over ? StaticSvg.LevelItemInfoOver : StaticSvg.LevelItemInfoUp));
		// openfl-svg does not render the authored SVG <text>; restore the "?".
		// Symbol 1213's static text: 12px Verdana in a 6.7 x 14.55 block at
		// left 46.65, under the matrix (0.9065, 0.7314, tx -40.2, ty -0.2).
		var holder = new Sprite();
		holder.mouseEnabled = false;
		holder.mouseChildren = false;
		holder.scaleX = 0.906539916992188;
		holder.scaleY = 0.731430053710938;
		holder.x = -40.2 + 46.65 * holder.scaleX;
		holder.y = -0.2;
		var question = new TextField();
		question.selectable = false;
		question.defaultTextFormat = new TextFormat(NativeAssets.font(FontAsset.Interface), 12, over || down ? 0xFFFF00 : 0x000000, false, null, null,
			null, null, TextFormatAlign.CENTER);
		question.text = "?";
		// Static text has no 2px TextField gutter.
		question.x = -2;
		// Verdana's ascent (1.005 em) sets the baseline 0.92px below DejaVu's
		// (0.928 em) at 12px.
		question.y = -2 + (1.005 - 0.928) * 12;
		question.width = 6.7 + 4;
		question.height = 14.55 + 4;
		holder.addChild(question);
		art.addChild(holder);
	}
}

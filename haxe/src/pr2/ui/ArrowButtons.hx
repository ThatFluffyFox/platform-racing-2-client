package pr2.ui;

import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.filters.BlurFilter;
import openfl.geom.ColorTransform;
import pr2.assets.NativeAssetIds.StaticSvg;
import pr2.assets.NativeAssets;
import pr2.ui.controls.AuthoredArrowButton;

/**
	Port of Flash `ui.ArrowButtons`: a left/right stepper over a fixed array of
	values. Clicking wraps around the array ends and dispatches `Event.CHANGE`
	carrying the newly selected `value`.
**/
class ArrowButtons extends Sprite {
	public var value:Int = 0;

	private var leftButton:AuthoredArrowButton;
	private var rightButton:AuthoredArrowButton;
	private var array:Array<Int>;
	private var index:Int = 0;

	public function new(values:Array<Int>, val:Int) {
		super();
		this.array = values;
		leftButton = new AuthoredArrowButton(false, clickLeft);
		rightButton = new AuthoredArrowButton(true, clickRight);
		leftButton.name = "left";
		rightButton.name = "right";
		rightButton.x = 100;
		addChild(shadow(false, 0));
		addChild(shadow(true, 100));
		addChild(leftButton);
		addChild(rightButton);
		setValue(val);
	}

	/**
		XFL `ArrowButtonsGraphic` gives both arrows a DropShadowFilter (distance 3,
		angle 90, blur 2, strength 0.25). The shadow is a separate blurred copy so
		the arrow itself is not drawn through OpenFL's low-resolution filter cache.
	**/
	private static function shadow(pointsRight:Bool, x:Float):Shape {
		var art = NativeAssets.svg(StaticSvg.ArrowButtonUp);
		art.transform.colorTransform = new ColorTransform(0, 0, 0, 0.25);
		art.filters = [new BlurFilter(2, 2, 1)];
		art.scaleX = pointsRight ? 1 : -1;
		art.x = pointsRight ? x : x + 10;
		art.y = 3;
		return art;
	}

	private function clickLeft():Void {
		index--;
		wrapCheck();
	}

	private function clickRight():Void {
		index++;
		wrapCheck();
	}

	private function wrapCheck():Void {
		var lastKey = array.length - 1;
		index = index < 0 ? lastKey : (index > lastKey ? 0 : index);
		value = array.length > 0 ? array[index] : value;
		dispatchEvent(new Event(Event.CHANGE));
	}

	public function setValue(val:Int):Void {
		var pos = array.indexOf(val);
		if (pos == -1) {
			pos = 0;
		} else {
			value = val;
			index = pos;
		}
		dispatchEvent(new Event(Event.CHANGE));
	}

	public function remove():Void {
		leftButton.dispose();
		rightButton.dispose();
		if (parent != null) {
			parent.removeChild(this);
		}
	}
}

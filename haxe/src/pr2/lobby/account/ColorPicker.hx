package pr2.lobby.account;

import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.display.DisplayObjectContainer;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.geom.ColorTransform;
import openfl.geom.Point;
import pr2.app.AppStage;

/**
	Colour picker for the part selectors. A 20x20 swatch shows the current colour;
	clicking it opens the Flash HSV popup, live previews popup changes, records
	the committed colour in the shared recent-colours strip, and dispatches the
	Flash `Event.CHANGE` / `Event.OPEN` / `Event.CLOSE` sequence.
**/
class ColorPicker extends Sprite {
	public static inline var RIGHT:String = "right";
	public static inline var LEFT:String = "left";
	public static final recentColors:Array<Int> = [
		0x888888, 0x555555, 0x888888, 0x555555, 0x888888, 0x555555,
		0x888888, 0x555555, 0x888888, 0x555555, 0x888888, 0x555555
	];

	private static inline var COLOR_WELL:Float = 36;

	public var direction:String = RIGHT;

	private var color:Int = 0x0000FF;
	private var swatch:Sprite;
	private var popup:Null<ColorPickerSurface>;

	public function new() {
		super();
		swatch = new Sprite();
		swatch.scaleX = swatch.scaleY = 0.833328247070312;
		addChild(swatch);
		var skin = createSkin();
		skin.name = "swatchSkin";
		addChild(skin);
		buttonMode = true;
		useHandCursor = true;
		mouseChildren = false;
		drawSwatch();
		addEventListener(MouseEvent.CLICK, onSwatchClick);
	}

	/**
		`ColorPicker_overSkin` as `ColorPickerGraphic` shows it: the 22px skin at
		1.3636x (30px) through its 9-slice grid (3..14 x 3..16). The corners keep
		their native size, so the 1px bevel rings and the dropdown triangle stay
		thin; only the middle bands stretch. Geometry is the skin's SVG export.
	**/
	private static function createSkin():Shape {
		var skin = new Shape();
		var g = skin.graphics;
		inline function mx(x:Float):Float return x <= 3 ? x : (x >= 14 ? x + 8 : 3 + (x - 3) * 19 / 11);
		inline function my(y:Float):Float return y <= 3 ? y : (y >= 16 ? y + 8 : 3 + (y - 3) * 21 / 13);
		function rect(color:Int, x0:Float, y0:Float, x1:Float, y1:Float):Void {
			g.beginFill(color);
			g.drawRect(mx(x0), my(y0), mx(x1) - mx(x0), my(y1) - my(y0));
			g.endFill();
		}
		// Light bevel ring and the dropdown corner.
		rect(0xE5E6E7, 1, 1, 21, 2);
		rect(0xE5E6E7, 1, 2, 2, 21);
		rect(0xE5E6E7, 20, 2, 21, 21);
		rect(0xE5E6E7, 2, 20, 20, 21);
		rect(0xE5E6E7, 14, 16, 20, 20);
		// White highlights.
		rect(0xFFFFFF, 0, 0, 21, 1);
		rect(0xFFFFFF, 0, 1, 1, 21);
		rect(0xFFFFFF, 2, 19, 14, 20);
		rect(0xFFFFFF, 19, 2, 20, 16);
		// Grey shadows.
		rect(0x9A9B9D, 2, 2, 19, 3);
		rect(0x9A9B9D, 2, 3, 3, 19);
		rect(0x9A9B9D, 21, 0, 22, 22);
		rect(0x9A9B9D, 0, 21, 21, 22);
		// Dropdown triangle.
		g.beginFill(0x000000);
		g.moveTo(mx(15.45), my(17.55));
		g.lineTo(mx(19.45), my(17.55));
		g.lineTo(mx(17.45), my(19.55));
		g.lineTo(mx(15.45), my(17.55));
		g.endFill();
		return skin;
	}

	public function getColor():Int {
		return color;
	}

	public function setColor(c:Int):Void {
		if (color != c) {
			color = c;
			drawSwatch();
			dispatchEvent(new Event(Event.CHANGE));
		}
	}

	private function drawSwatch():Void {
		swatch.graphics.clear();
		swatch.transform.colorTransform = new ColorTransform();
		swatch.graphics.beginFill(color & 0xFFFFFF);
		swatch.graphics.drawRect(0, 0, COLOR_WELL, COLOR_WELL);
		swatch.graphics.endFill();
	}

	private function onSwatchClick(_:MouseEvent):Void {
		if (popup != null) {
			closePopup();
			return;
		}
		openPopup();
	}

	private function openPopup():Void {
		var popupParent:DisplayObjectContainer = AppStage.stage != null ? AppStage.stage : this;
		popup = pr2.app.ScreenFactory.advancedColor(color);
		popup.addEventListener(Event.CHANGE, onPopupChange);
		popup.addEventListener(Event.CLOSE, closePopup);
		var origin = localToGlobal(new Point(0, 0));
		if (!popup.fullViewport) {
			var px = direction == RIGHT ? origin.x + this.width + 5 : origin.x - popup.width - 5;
			popup.x = Math.round(px);
			popup.y = Math.round(origin.y);
		}
		popupParent.addChild(popup);
		popup.init();
		popup.addExclusion(this);
		if (AppStage.stage != null) {
			AppStage.stage.addEventListener(MouseEvent.MOUSE_DOWN, onStageDown);
		}
		dispatchEvent(new Event(Event.OPEN));
	}

	private static function recordRecent(c:Int):Void {
		if (recentColors.indexOf(c) == -1) {
			recentColors.unshift(c);
			recentColors.pop();
		}
	}

	private function onStageDown(e:MouseEvent):Void {
		if (popup != null && !popup.hitTestPoint(e.stageX, e.stageY, true) && !hitTestPoint(e.stageX, e.stageY, true)) {
			closePopup();
		}
	}

	private function onPopupChange(_:Event):Void {
		if (popup != null) {
			setColor(popup.getColor());
		}
	}

	private function closePopup(?_:Event):Void {
		if (popup == null) {
			return;
		}
		var closing = popup;
		setColor(closing.getColor());
		closing.removeEventListener(Event.CHANGE, onPopupChange);
		closing.removeEventListener(Event.CLOSE, closePopup);
		if (AppStage.stage != null) {
			AppStage.stage.removeEventListener(MouseEvent.MOUSE_DOWN, onStageDown);
		}
		closing.remove();
		popup = null;
		recordRecent(color);
		dispatchEvent(new Event(Event.CLOSE));
	}

	public function remove():Void {
		removeEventListener(MouseEvent.CLICK, onSwatchClick);
		closePopup();
		if (parent != null) {
			parent.removeChild(this);
		}
	}
}

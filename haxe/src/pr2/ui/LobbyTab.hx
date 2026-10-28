package pr2.ui;

import openfl.display.CapsStyle;
import openfl.display.GradientType;
import openfl.display.JointStyle;
import openfl.display.LineScaleMode;
import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.geom.Matrix;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;
import pr2.assets.NativeAssetIds.FontAsset;
import pr2.assets.NativeAssetIds.StaticSvg;
import pr2.assets.NativeAssets;

/**
	Port of Flash `ui.LobbyTab`.

	Each tab is the `LobbyTabGraphic` art: a `textBox` dynamic text laid over a
	`bg` clip whose timeline has `up` / `over` / `selected` label frames. The tab
	sizes itself to its text (`bg.width = textBox.width + 10`), reports clicks to
	its `TabsHolder`, and on hover both highlights and asks the holder to bring it
	to the front so its label is never clipped by neighbours.
**/
class LobbyTab extends Sprite {
	private var bg:Sprite;
	private var bgScaleX:Float = 0;
	private var base:Null<Shape>;
	private var selectedOverlay:Null<Shape>;
	private var textBox:TextField;
	private var tabsHolder:Null<TabsHolder>;
	private var tabFunction:Void->Void;

	public function new(tabFn:Void->Void, tabText:String) {
		super();
		this.tabFunction = tabFn;

		bg = new Sprite();
		bg.name = "bg";
		addChild(bg);
		textBox = new TextField();
		textBox.name = "textBox";
		textBox.x = 5;
		textBox.y = 2;
		textBox.height = 14.55;
		textBox.selectable = false;
		textBox.mouseEnabled = false;
		textBox.defaultTextFormat = new TextFormat(NativeAssets.font(FontAsset.Interface), 12, 0);
		textBox.autoSize = TextFieldAutoSize.LEFT;
		textBox.text = tabText;
		addChild(textBox);
		setState(StaticSvg.LobbyTabUp, false);
		activate();
	}

	@:allow(pr2.ui.TabsHolder)
	private function setTabsHolder(h:TabsHolder):Void {
		this.tabsHolder = h;
	}

	private function onClick(_:MouseEvent):Void {
		select();
	}

	private function onHover(_:MouseEvent):Void {
		setState(StaticSvg.LobbyTabOver, false);
		if (tabsHolder != null) {
			tabsHolder.moveToFront(this);
		}
	}

	private function onHoverOut(_:MouseEvent):Void {
		setState(StaticSvg.LobbyTabUp, false);
	}

	public function select():Void {
		if (tabsHolder != null) {
			tabsHolder.selectTab(this);
		}
		tabFunction();
		deactivate();
		setState(null, true);
	}

	public function activate():Void {
		deactivate();
		addEventListener(MouseEvent.CLICK, onClick);
		addEventListener(MouseEvent.MOUSE_OVER, onHover);
		addEventListener(MouseEvent.MOUSE_OUT, onHoverOut);
	}

	private function deactivate():Void {
		setState(StaticSvg.LobbyTabUp, false);
		removeEventListener(MouseEvent.CLICK, onClick);
		removeEventListener(MouseEvent.MOUSE_OVER, onHover);
		removeEventListener(MouseEvent.MOUSE_OUT, onHoverOut);
	}

	public function remove():Void {
		deactivate();
		base = null;
		selectedOverlay = null;
		tabsHolder = null;
		if (parent != null) {
			parent.removeChild(this);
		}
	}

	private function setState(asset:Null<StaticSvg>, selected:Bool):Void {
		if (base != null) bg.removeChild(base);
		if (selectedOverlay != null) bg.removeChild(selectedOverlay);
		// The `selected` frame shows only Graphics/Symbol 1223, not the up/over art.
		base = selected ? selectedArt() : NativeAssets.svg(asset);
		bg.addChild(base);
		if (selected) {
			selectedOverlay = NativeAssets.svg(StaticSvg.LobbyTabSelectedOverlay);
			bg.addChild(selectedOverlay);
		} else selectedOverlay = null;
		// Flash sets `bg.width = textBox.width + 10` once, in the constructor's
		// up frame, and the stretch then carries over to the over and selected
		// frames. The selected art's 3px outline makes its bounds wider, so
		// refitting each frame (as before) shrank the selected tab.
		if (bgScaleX == 0) {
			bg.width = textBox.width + 10;
			bgScaleX = bg.scaleX;
		} else {
			bg.scaleX = bgScaleX;
		}
	}

	/**
		Layers 3 and 2 of XFL `Graphics/Symbol 1223` (the 50x19 selected tab):
		a half-transparent 3px dark outline, then the white-green-white gradient
		with its 1px green (#3CFF62) outline. The white sparkle (layer 1) is the
		LobbyTabSelectedOverlay SVG drawn on top. Like Flash, the clip is then
		stretched to the label width.
	**/
	private static function selectedArt():Shape {
		var art = new Shape();
		var g = art.graphics;
		g.lineStyle(3, 0x000000, 0.501960784313725, true, LineScaleMode.NORMAL, CapsStyle.ROUND, JointStyle.ROUND);
		g.moveTo(50, 14);
		g.lineTo(50, 6);
		g.lineTo(49.85, 4.45);
		g.curveTo(49.15, 1, 45, 1);
		g.lineTo(5, 1);
		g.curveTo(0.85, 1, 0.15, 4.45);
		g.lineTo(0, 5.15);
		g.lineTo(0, 6);
		g.lineTo(0, 14);

		g.lineStyle();
		var gradient = new Matrix();
		gradient.createGradientBox(50, 18.3, Math.PI / 2, 0, 0.6);
		g.beginGradientFill(GradientType.LINEAR, [0xFFFFFF, 0xC4FEBC, 0xFFFFFF, 0xFFFFFF], [1, 1, 1, 0], [0, 126, 210, 233], gradient);
		g.moveTo(49.05, 14.5);
		g.lineTo(49.05, 4.45);
		g.curveTo(48.75, 0, 44.2, 0);
		g.lineTo(5.75, 0);
		g.curveTo(1.25, 0, 1, 4.45);
		g.lineTo(0.95, 5);
		g.lineTo(0.95, 19);
		g.lineTo(49.05, 19);
		g.lineTo(49.05, 14.5);
		g.endFill();

		g.lineStyle(1, 0x3CFF62, 1, true, LineScaleMode.NORMAL, CapsStyle.ROUND, JointStyle.ROUND);
		g.moveTo(49.05, 14.5);
		g.lineTo(49.05, 4.45);
		g.curveTo(48.75, 0, 44.2, 0);
		g.lineTo(5.75, 0);
		g.curveTo(1.25, 0, 1, 4.45);
		g.lineTo(0.95, 5);
		g.lineTo(0.95, 14.5);
		return art;
	}

}

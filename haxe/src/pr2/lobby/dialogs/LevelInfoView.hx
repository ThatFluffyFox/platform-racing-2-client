package pr2.lobby.dialogs;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import pr2.assets.NativeAssetIds.FontAsset;
import pr2.assets.NativeAssetIds.StaticSvg;
import pr2.assets.NativeAssets;
import pr2.ui.controls.GameButton;
import pr2.ui.controls.NativeControl;
import pr2.ui.RatingSelect.RatingStarMeter;
import pr2.ui.view.NativeView;
import pr2.ui.view.LoadingView;
import pr2.ui.FlashTextBox;

/** Native level-details card with explicit hover and action targets. */
class LevelInfoView extends NativeView {
	public final levelInfo:Sprite;
	public final loading:LoadingView;
	public final playButton:GameButton;

	public function new() {
		super();
		var panel = NativeAssets.svg(StaticSvg.QuantityPanel);
		panel.x = -175;
		panel.y = -137.5;
		panel.scaleX = 1.2867431640625;
		panel.scaleY = 1.43986511230469;
		addChild(panel);

		levelInfo = new Sprite();
		levelInfo.name = "levelInfo";
		levelInfo.x = -1.5;
		levelInfo.y = -2.75;
		addChild(levelInfo);
		field(levelInfo, "title", -152.05, -118.8, 307.95, 14.55, 12, true, TextFormatAlign.CENTER);
		field(levelInfo, "author", -157.05, -100.25, 318.95, 14.5, 10, false, TextFormatAlign.CENTER, false, 0x666666);
		field(levelInfo, "note", 22.55, -72.4, 140, 120.65, 8, false, TextFormatAlign.CENTER, true, 0x666666);

		label(levelInfo, "Version:", -162.55, -59.8, 91);
		field(levelInfo, "version", -64.1, -59.8, 31, 13.35, 11, false, TextFormatAlign.LEFT);
		label(levelInfo, "Last Updated:", -162.55, -39.8, 91);
		field(levelInfo, "updated", -64.1, -39.8, 76, 13.35, 11, false, TextFormatAlign.LEFT);
		label(levelInfo, "Min. Rank:", -162.55, -19.8, 91);
		field(levelInfo, "minRank", -64.1, -19.8, 31, 13.35, 11, false, TextFormatAlign.LEFT);
		label(levelInfo, "Play Count:", -162.55, 0.2, 91);
		field(levelInfo, "plays", -64.1, 0.2, 76, 13.35, 11, false, TextFormatAlign.LEFT);
		label(levelInfo, "Rating:", -162.55, 20.2, 91);

		makeRating(levelInfo, -33.5, 27.7);
		makeMode(levelInfo, -142.95, 73.55);
		// These are Flash buttons centred on their placement: the hover area is each
		// button's HIT-state rectangle and the OVER state greys the icon (music,
		// clock) or lays a 20% white highlight over it (cowboy, items, hats).
		sourceTile(levelInfo, "song", StaticSvg.LevelInfoMusic, -88.5, 71.7, -11.25, -11.4, 23.5, 24, false);
		sourceTile(levelInfo, "cowboyChance", StaticSvg.LevelInfoCowboy, -38.55, 71.7, -13, -10.35, 26, 20.75, true);
		sourceTile(levelInfo, "maxTime", StaticSvg.LevelInfoClock, 9.5, 72, -12.5, -12.5, 25, 25, false);
		gravityButton(levelInfo, 54.8, 74.6);
		sourceTile(levelInfo, "items", StaticSvg.LevelInfoItems, 88.6, 61.9, -0.25, -1.43, 25, 25.76, true);
		sourceTile(levelInfo, "hatsAllowed", StaticSvg.LevelInfoHats, 149.25, 73.9, -13, -13, 26, 26, true);

		actionButton(levelInfo, "share_bt", LevelInfoActionKind.Share, -149.05, 112.8);
		actionButton(levelInfo, "report_bt", LevelInfoActionKind.Report, 150.8, 112.8);
		actionButton(levelInfo, "unpublish_bt", LevelInfoActionKind.Unpublish, 150.8, 112.8);
		playButton = button(this, "play_bt", "Play", -105.8, 99, 100);
		button(this, "close_bt", "Close", 15.2, 99, 100);

		loading = new LoadingView();
		loading.name = "loading";
		addChild(loading);
		levelInfo.visible = false;
	}

	override public function dispose():Void {
		loading.dispose();
		super.dispose();
	}

	private function makeRating(parent:Sprite, x:Float, y:Float):Void {
		var rating = new LevelInfoRatingSymbol();
		rating.name = "rating";
		rating.x = x;
		rating.y = y;
		parent.addChild(rating);
	}

	private function makeMode(parent:Sprite, x:Float, y:Float):Void {
		var mode = new Sprite();
		mode.name = "gameMode";
		mode.x = x;
		mode.y = y;
		var symbol = new LevelModeSymbol();
		symbol.name = "modeSym";
		symbol.x = 17;
		symbol.y = 16;
		mode.addChild(symbol);
		mode.addChild(hoverCover(56, 34));
		parent.addChild(mode);
	}

	private function hoverTile(parent:Sprite, name:String, value:String, x:Float, y:Float, width:Float, height:Float, color:Int):Void {
		var tile = new Sprite();
		tile.name = name;
		tile.x = x;
		tile.y = y;
		tile.graphics.beginFill(color);
		tile.graphics.drawRoundRect(0, 0, width, height, 7, 7);
		tile.graphics.endFill();
		field(tile, null, 0, 6, width, height - 6, 10, true, TextFormatAlign.CENTER).text = value;
		parent.addChild(tile);
	}

	private function sourceTile(parent:Sprite, name:String, asset:StaticSvg, x:Float, y:Float, hitX:Float, hitY:Float, hitWidth:Float,
			hitHeight:Float, highlight:Bool):Void {
		var tile = new Sprite();
		tile.name = name;
		tile.x = x;
		tile.y = y;
		var icon = NativeAssets.svg(asset);
		tile.addChild(icon);
		var over = new openfl.display.Shape();
		over.name = "over";
		if (highlight) {
			over.graphics.beginFill(0xFFFFFF, 0.2);
			over.graphics.drawRect(hitX, hitY, hitWidth, hitHeight);
			over.graphics.endFill();
		}
		over.visible = false;
		tile.addChild(over);
		tile.addChild(hitRect(hitX, hitY, hitWidth, hitHeight));
		listen(tile, openfl.events.MouseEvent.MOUSE_OVER, function(_:openfl.events.MouseEvent):Void {
			if (highlight) over.visible = true;
			else icon.transform.colorTransform = OVER_GREY;
		});
		listen(tile, openfl.events.MouseEvent.MOUSE_OUT, function(_:openfl.events.MouseEvent):Void {
			over.visible = false;
			icon.transform.colorTransform = new openfl.geom.ColorTransform();
		});
		parent.addChild(tile);
	}

	/** Black art drawn as #666666 (white stays white), like the grey OVER-state shapes. */
	private static final OVER_GREY = new openfl.geom.ColorTransform(0.6, 0.6, 0.6, 1, 102, 102, 102);

	/** An invisible Flash button HIT-state rectangle. */
	private static function hitRect(x:Float, y:Float, width:Float, height:Float):openfl.display.Shape {
		var hit = new openfl.display.Shape();
		hit.name = "hitArea";
		hit.graphics.beginFill(0x000000, 0);
		hit.graphics.drawRect(x, y, width, height);
		hit.graphics.endFill();
		return hit;
	}

	private function gravityButton(parent:Sprite, x:Float, y:Float):Void {
		var tile = new Sprite();
		tile.name = "gravity";
		tile.x = x;
		tile.y = y;
		var text = field(tile, null, -7.75, -10.6, 15.5, 21.25, 20, false, TextFormatAlign.CENTER);
		text.defaultTextFormat = new TextFormat(NativeAssets.font(FontAsset.Display), 20, 0x000000, false, null, null, null, null,
			TextFormatAlign.CENTER);
		text.text = "G";
		// HIT state: shape 1248 scaled to (-10.23, -11.58) .. (10.63, 8.72).
		tile.addChild(hitRect(-10.23, -11.58, 20.86, 20.3));
		listen(tile, openfl.events.MouseEvent.MOUSE_OVER, function(_:openfl.events.MouseEvent):Void text.textColor = 0x666666);
		listen(tile, openfl.events.MouseEvent.MOUSE_OUT, function(_:openfl.events.MouseEvent):Void text.textColor = 0x000000);
		parent.addChild(tile);
	}

	private function hoverCover(width:Float, height:Float):Sprite {
		var cover = new Sprite();
		cover.name = "cover";
		cover.graphics.beginFill(0xFFFFFF, 0.34);
		cover.graphics.drawRoundRect(0, 0, width, height, 5, 5);
		cover.graphics.endFill();
		cover.visible = false;
		return cover;
	}

	private function button(parent:Sprite, name:String, value:String, x:Float, y:Float, width:Float):GameButton {
		var control = ownControl(new GameButton(value));
		control.name = name;
		control.x = x;
		control.y = y;
		control.setSize(width, 24);
		parent.addChild(control);
		return control;
	}

	private function actionButton(parent:Sprite, name:String, kind:LevelInfoActionKind, x:Float, y:Float):Void {
		var control = ownControl(new LevelInfoActionButton(kind));
		control.name = name;
		control.x = x;
		control.y = y;
		parent.addChild(control);
	}

	private function label(parent:Sprite, value:String, x:Float, y:Float, width:Float):Void {
		field(parent, null, x, y, width, 18, 11, true, TextFormatAlign.RIGHT).text = value;
	}

	private function field(parent:Sprite, name:Null<String>, x:Float, y:Float, width:Float, height:Float, size:Int, bold:Bool,
		align:TextFormatAlign, multiline:Bool = false, color:Int = 0x000000):TextField {
		var text = new TextField();
		if (name != null) text.name = name;
		FlashTextBox.applyXflBox(text, x, y, width, height);
		text.multiline = multiline;
		text.wordWrap = multiline;
		text.selectable = false;
		text.defaultTextFormat = new TextFormat(NativeAssets.font(FontAsset.Interface), size, color, bold, null, null, null, null, align);
		parent.addChild(text);
		return text;
	}
}

class LevelInfoRatingSymbol extends Sprite {
	private final meter:RatingStarMeter;
	private final scaleProxy:Sprite;

	public function new() {
		super();
		meter = new RatingStarMeter();
		meter.x = -32.6;
		meter.y = -6.5;
		meter.scaleX = 1.18113708496094;
		meter.scaleY = 1.18180847167969;
		addChild(meter);
		scaleProxy = new Sprite();
		scaleProxy.name = "bar";
		addChild(scaleProxy);
		var cover = new Sprite();
		cover.name = "cover";
		cover.graphics.beginFill(0xFFFFFF, 0.2);
		cover.graphics.drawRect(-33, -7.02, 66, 14.02);
		cover.graphics.endFill();
		cover.visible = false;
		addChild(cover);
	}

	public function displayRating(value:Float):Void {
		meter.displayRating(value);
		scaleProxy.scaleX = value / 5;
	}
}

private enum abstract LevelInfoActionKind(Int) {
	var Share = 0;
	var Report = 1;
	var Unpublish = 2;
}

private class LevelInfoActionButton extends NativeControl {
	private var kind:Null<LevelInfoActionKind>;

	public function new(kind:LevelInfoActionKind) {
		super(20, 20);
		flashSimpleButton = true;
		this.kind = kind;
		mouseChildren = false;
		redraw();
	}

	override public function redraw():Void {
		while (numChildren > 0) removeChildAt(0);
		if (kind == null) return;
		var down = state() == Pressed;
		var over = state() == Hovered || state() == Focused;
		var asset = switch (kind) {
			case Share: down ? StaticSvg.LevelInfoShareDown : over ? StaticSvg.LevelInfoShareOver : StaticSvg.LevelInfoShareUp;
			case Report: down ? StaticSvg.LevelInfoReportDown : over ? StaticSvg.LevelInfoReportOver : StaticSvg.LevelInfoReportUp;
			case Unpublish: down ? StaticSvg.LevelInfoUnpublishDown : over ? StaticSvg.LevelInfoUnpublishOver : StaticSvg.LevelInfoUnpublishUp;
		};
		addChild(NativeAssets.svg(asset));
	}
}

/** Explicit five-state replacement for the legacy mode timeline symbol. */
class LevelModeSymbol extends Sprite {
	private var art:openfl.display.DisplayObject;
	public function new() {
		super();
		setFrame(1);
	}

	public function setFrame(frame:Int):Void {
		graphics.clear();
		var assets = [StaticSvg.LevelInfoModeRace, StaticSvg.LevelInfoModeDeathmatch, StaticSvg.LevelInfoModeEgg, StaticSvg.LevelInfoModeObjective,
			StaticSvg.LevelInfoModeHat];
		var index = frame < 1 || frame > assets.length ? 0 : frame - 1;
		graphics.beginFill(0xCCCCCC, 0.749019607843137);
		graphics.drawRect(-17.35, -12.9, 34.2, 25.05);
		graphics.endFill();
		if (art != null && art.parent == this) removeChild(art);
		art = NativeAssets.svg(assets[index]);
		art.x = -12.5;
		art.y = -6.9;
		art.scaleX = 0.318450927734375;
		art.scaleY = 0.316574096679688;
		addChild(art);
	}
}

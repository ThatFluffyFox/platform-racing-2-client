package pr2.lobby.tabs;

import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import pr2.assets.NativeAssetIds.FontAsset;
import pr2.assets.NativeAssets;
import pr2.ui.view.NativeView;

/** Native account-tab background and named information/action controls. */
class AccountInfoView extends NativeView {
	public function new() {
		super();
		// XFL `AccountInfoGraphic` (MovieClips/Symbol 1269) text positions.
		field("nameBox", 2, 2, 156.05, 14.55);
		field("rankBox", 2, 20, 176.05, 14.55);
		field("hatBox", 2, 38, 176.05, 14.55);
		field("guildBox", 2, 56, 176.05, 14.55);
		addButton(new RankTokenButton("rankTokenUp_bt"), 66, 18);
		addButton(new RankTokenButton("rankTokenDown_bt"), 101, 18);
		addButton(new LoadoutsIconButton(), 169, 2);
	}

	private function addButton(button:Sprite, x:Float, y:Float):Void {
		button.x = x;
		button.y = y;
		addChild(button);
	}

	private function field(name:String, x:Float, y:Float, width:Float, height:Float):Void {
		var text = new TextField();
		text.name = name;
		text.x = x;
		text.y = y;
		text.width = width;
		text.height = height;
		text.selectable = false;
		text.multiline = true;
		text.defaultTextFormat = new TextFormat(NativeAssets.font(FontAsset.Interface), 12, 0x000000, false, null, null, null, null,
			TextFormatAlign.LEFT);
		addChild(text);
	}
}

/**
	XFL `MovieClips/Symbol 1264`: a round olive button (Graphics/Symbol 1259)
	with a gloss highlight and shade (Graphics/Symbol 1261), the token count,
	and a red arrow child named `arrow` that AccountTab turns 180 degrees for
	the "unuse" button.
**/
private class RankTokenButton extends Sprite {
	public function new(buttonName:String) {
		super();
		name = buttonName;
		buttonMode = useHandCursor = true;
		// Symbol 1259: transparent 40x20 hit area and the 12.15px circle.
		graphics.beginFill(0xFFFFFF, 0);
		graphics.drawRect(0, 0, 40, 20);
		graphics.endFill();
		graphics.lineStyle(1, 0xFFFF00);
		graphics.beginFill(0x8C9254);
		graphics.drawCircle(6.075, 10.075, 6.075);
		graphics.endFill();

		var text = new TextField();
		text.name = "textBox";
		text.x = 16;
		text.y = 2;
		text.width = 23;
		text.height = 14.55;
		text.selectable = false;
		text.defaultTextFormat = new TextFormat(NativeAssets.font(FontAsset.Interface), 12, 0x737373);
		addChild(text);

		// Symbol 1261: white gloss at the top left and a dark shade at the bottom right.
		var gloss = new Shape();
		gloss.graphics.beginFill(0xFFFFFF, 0.662745098039216);
		gloss.graphics.moveTo(4.25, 4.4);
		gloss.graphics.lineTo(3.85, 4.35);
		gloss.graphics.curveTo(0.9, 4.9, 0.1, 7.5);
		gloss.graphics.curveTo(2.95, 7.5, 3.75, 6.95);
		gloss.graphics.curveTo(4.35, 6.5, 4.35, 5.05);
		gloss.graphics.lineTo(4.25, 4.4);
		gloss.graphics.endFill();
		gloss.graphics.beginFill(0x000000, 0.333333333333333);
		gloss.graphics.moveTo(3.2, 15.4);
		gloss.graphics.curveTo(4.4, 17, 7.1, 16.6);
		gloss.graphics.curveTo(9.75, 16.2, 11.15, 14.8);
		gloss.graphics.curveTo(12.5, 13.4, 12.55, 11.7);
		gloss.graphics.lineTo(12.4, 9.9);
		gloss.graphics.curveTo(11.65, 12.35, 9.45, 14.15);
		gloss.graphics.curveTo(7.25, 15.9, 3.2, 15.4);
		gloss.graphics.endFill();
		addChild(gloss);

		// Symbol 1263, registered at its centre so a 180 degree turn points it down.
		var arrow = new Shape();
		arrow.name = "arrow";
		arrow.x = 6.2;
		arrow.y = 9.95;
		arrow.graphics.lineStyle(1, 0xFFFF00);
		arrow.graphics.beginFill(0xFF0000, 0.662745098039216);
		arrow.graphics.moveTo(1.1, -0.55);
		arrow.graphics.lineTo(1.1, 4.8);
		arrow.graphics.lineTo(-1.1, 4.8);
		arrow.graphics.lineTo(-1.1, -0.55);
		arrow.graphics.lineTo(-4.25, -0.55);
		arrow.graphics.lineTo(0, -4.8);
		arrow.graphics.lineTo(4.25, -0.55);
		arrow.graphics.lineTo(1.1, -0.55);
		arrow.graphics.endFill();
		addChild(arrow);
	}
}

private class LoadoutsIconButton extends Sprite {
	public function new() {
		super();
		name = "loadouts_bt";
		buttonMode = useHandCursor = true;
		var text = new TextField();
		text.x = 2;
		text.y = 2;
		text.width = 15.2;
		text.height = 16.75;
		text.selectable = false;
		text.defaultTextFormat = new TextFormat(NativeAssets.font(FontAsset.Icons), 14, 0x000000);
		text.text = "";
		addChild(text);
	}
}

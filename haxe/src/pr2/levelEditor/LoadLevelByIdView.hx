package pr2.levelEditor;

import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import pr2.assets.NativeAssetIds.FontAsset;
import pr2.assets.NativeAssets;
import pr2.ui.AuthoredScale9;
import pr2.ui.controls.GameButton;
import pr2.ui.controls.GameTextInput;
import pr2.ui.view.NativeView;

/** Port-only level-ID prompt for the editor's Load menu, styled like the other level-management popups. */
class LoadLevelByIdView extends NativeView {
	public final input:GameTextInput;

	public function new() {
		super();
		var background = AuthoredScale9.shadowPanel();
		background.name = "background";
		background.x = -122.5;
		background.y = -68.75;
		background.scaleX = 0.900802612304688;
		background.scaleY = 0.719802856445312;
		addChild(background);

		label("title", "-- Load Level ID --", -107.95, -58.2, 216.95, 17.05, 14, true);
		label("prompt", "Enter the ID of the level to load:", -107.95, -33.2, 216.95, 14.55, 12, false);
		input = ownControl(new GameTextInput());
		input.name = "id_input";
		input.restrict = "0-9";
		input.maxChars = 10;
		input.x = -60;
		input.y = -10;
		input.setSize(120, 22);
		addChild(input);
		button("load_bt", "Load", -88, 24, 79.9972534179688, 23.7000122070312);
		button("cancel_bt", "Cancel", 8, 24, 79.9972534179688, 23.7000122070312);
	}

	private function label(name:String, value:String, x:Float, y:Float, width:Float, height:Float, size:Int, bold:Bool):Void {
		var text = new TextField();
		text.name = name;
		text.x = x;
		text.y = y;
		text.width = width;
		text.height = height;
		text.mouseEnabled = false;
		text.selectable = false;
		text.defaultTextFormat = new TextFormat(NativeAssets.font(FontAsset.Interface), size, 0x000000, bold, null, null, null, null,
			TextFormatAlign.CENTER);
		text.text = value;
		addChild(text);
	}

	private function button(name:String, label:String, x:Float, y:Float, width:Float, height:Float):Void {
		var control = ownControl(new GameButton(label));
		control.name = name;
		control.x = x;
		control.y = y;
		control.setSize(width, height);
		addChild(control);
	}
}

package pr2.lobby.tabs;

import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.text.TextField;
import openfl.text.TextFormat;
import pr2.assets.NativeAssetIds.FontAsset;
import pr2.assets.NativeAssetIds.StaticSvg;
import pr2.assets.NativeAssets;
import pr2.ui.controls.GameButton;
import pr2.ui.controls.GameTextArea;
import pr2.ui.controls.GameTextInput;
import pr2.ui.view.NativeView;
import pr2.ui.FlashTextBox;

/** Exact native composition of XFL `ChatGraphic` (`MovieClips/Symbol 1217`). */
class ChatView extends NativeView {
	public final roomInput:GameTextInput;
	public final chatInputControl:GameTextInput;
	public final transcriptArea:GameTextArea;
	public final roomBox:TextField;
	public final chatInput:TextField;
	public final textBox:TextField;

	public function new() {
		super();
		transcriptArea = ownControl(new GameTextArea(100 * 1.87985229492188, 44 * 6.88603210449219));
		transcriptArea.name = "textArea";
		transcriptArea.x = 0;
		transcriptArea.y = 25;
		transcriptArea.editable = false;
		transcriptArea.wordWrap = true;
		textBox = transcriptArea.textField;
		textBox.name = "textBox";
		addChild(transcriptArea);

		roomInput = ownControl(new GameTextInput());
		roomInput.name = "roomInput";
		roomInput.setSize(100 * 1.0001220703125, 22);
		roomInput.maxChars = 16;
		roomInput.restrict = "^`";
		roomBox = roomInput.textField;
		roomBox.name = "roomBox";
		addChild(roomInput);

		addButton("joinRoom_bt", "Join Room", 103, 0, 100 * 0.660003662109375);
		var info = new InfoButton();
		info.x = 175;
		info.y = 6;
		addChild(info);

		chatInputControl = ownControl(new GameTextInput());
		chatInputControl.name = "chatInputControl";
		chatInputControl.x = 0;
		chatInputControl.y = 331;
		chatInputControl.setSize(100 * 1.45013427734375, 22);
		chatInputControl.maxChars = 150;
		chatInputControl.restrict = "^`";
		chatInput = chatInputControl.textField;
		chatInput.name = "chatInput";
		addChild(chatInputControl);
		addButton("send_bt", "Send", 148, 331, 100 * 0.400009155273438);

		addRule("No swearing.", 0, 356, 65.55);
		addRule("No flooding.", 70, 356, 60.5);
		addRule("Be nice :)", 136, 356, 49.15);
	}

	private function addButton(name:String, label:String, x:Float, y:Float, width:Float):Void {
		var control = ownControl(new GameButton(label));
		control.name = name;
		control.x = x;
		control.y = y;
		control.setSize(width, 22);
		addChild(control);
	}

	private function addRule(value:String, x:Float, y:Float, width:Float):Void {
		var field = new TextField();
		FlashTextBox.applyXflBox(field, x, y, width, 12.15);
		field.selectable = false;
		field.defaultTextFormat = new TextFormat(NativeAssets.font(FontAsset.Interface), 10, 0x666666);
		field.text = value;
		addChild(field);
	}
}

/**
	XFL `Buttons/Symbol 1213` (`InfoButton`), placed unscaled in `ChatGraphic`:
	a grey circle with a "?" that turns yellow on hover.
**/
private class InfoButton extends Sprite {
	private final art = new Sprite();
	private var over = false;
	private var down = false;

	public function new() {
		super();
		name = "infoButton";
		buttonMode = useHandCursor = true;
		mouseChildren = false;
		graphics.beginFill(0xFFFFFF, 0);
		graphics.drawRect(0, 0, 15, 16);
		graphics.endFill();
		addChild(art);
		addEventListener(MouseEvent.MOUSE_OVER, function(_) { over = true; redraw(); });
		addEventListener(MouseEvent.MOUSE_OUT, function(_) { over = down = false; redraw(); });
		addEventListener(MouseEvent.MOUSE_DOWN, function(_) { down = true; redraw(); });
		addEventListener(MouseEvent.MOUSE_UP, function(_) { down = false; redraw(); });
		redraw();
	}

	private function redraw():Void {
		art.removeChildren();
		art.addChild(NativeAssets.svg(down ? StaticSvg.LevelItemInfoDown : over ? StaticSvg.LevelItemInfoOver : StaticSvg.LevelItemInfoUp));
		// openfl-svg does not render the authored SVG <text>; restore the "?"
		// with the same static-text placement as the account part buttons.
		var question = new TextField();
		question.mouseEnabled = false;
		question.selectable = false;
		question.defaultTextFormat = new TextFormat(NativeAssets.font(FontAsset.Interface), 12, over || down ? 0xFFFF00 : 0x000000);
		question.text = "?";
		question.scaleX = 0.906539916992188;
		question.scaleY = 0.731430053710938;
		question.x = -40.2 + 46.65 * question.scaleX - 2 * question.scaleX;
		question.y = -0.2 + (12.06 - 2 - 11.14) * question.scaleY;
		question.width = 6.7 + 4;
		question.height = 20;
		art.addChild(question);
	}
}

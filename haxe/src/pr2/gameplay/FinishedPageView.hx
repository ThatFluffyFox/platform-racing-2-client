package pr2.gameplay;

import openfl.display.Shape;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import pr2.runtime.FontResolver;
import pr2.runtime.SvgAsset;
import pr2.ui.AuthoredScale9;
import pr2.ui.controls.GameButton;
import pr2.ui.view.NativeView;

/** Exact XFL end-of-race shell with native dynamic award fields and buttons. */
class FinishedPageView extends NativeView {
	public static inline final SHELL_ASSET = "assets/svg/effects/finished_page_01.svg";
	public final backgroundPanel:Shape;

	public function new() {
		super();
		backgroundPanel = AuthoredScale9.shadowPanel({x: -145.6, y: -141, scaleX: 1.072021484375, scaleY: 1.54437255859375});
		backgroundPanel.name = "backgroundPanel";
		addChild(backgroundPanel);
		var shell = SvgAsset.createWithoutSymbol(SHELL_ASSET, AuthoredScale9.SHADOW_SYMBOL);
		shell.name = "exactShell";
		addChild(shell);
		for (index in 1...6) {
			var y = -100.5 + (index - 1) * 22;
			field("bonus" + index, -127.95, y, 161.9, 14.5, TextFormatAlign.RIGHT);
			field("exp" + index, 50.25, y, 76, 14.55, TextFormatAlign.LEFT);
		}
		field("expTotal", 50.25, 19.5, 76, 14.55, TextFormatAlign.LEFT);
		// FinishedPageGraphic's static text. The shell SVG is drawn as one Shape,
		// and format.svg does not render <text>, so these are native fields.
		staticLabel("raceCompleteLabel", "-- Race Complete! --", -69.15, -129.75, true);
		staticLabel("totalExpLabel", "Total Experience Points:", -127.95 + 17, 19.5, false);
		staticLabel("rateLevelLabel", "Rate This Level:", -99.45 + 1.5, 90, false);
		button("close_bt", "Close", -111, 121);
		button("return_bt", "Return to Lobby", 8, 121);
		// Port-only diagnostic: sits in the panel's top margin, above the Race Complete title.
		field("physicsFrames", -136, -140.5, 130, 11, TextFormatAlign.LEFT, 8);
	}

	private function button(name:String, label:String, x:Float, y:Float):Void {
		var control = ownControl(new GameButton(label));
		control.name = name;
		control.x = x;
		control.y = y;
		control.setSize(100, 22);
		addChild(control);
	}

	/** Flash static text at its XFL text origin: TextField's 2 px gutter is removed. */
	private function staticLabel(name:String, text:String, x:Float, y:Float, bold:Bool):Void {
		var label = new TextField();
		label.name = name;
		label.autoSize = TextFieldAutoSize.LEFT;
		label.embedFonts = true;
		label.selectable = false;
		label.mouseEnabled = false;
		var format = new TextFormat(FontResolver.resolve(bold ? "Verdana-Bold" : "Verdana"), 12, 0x000000);
		format.letterSpacing = -0.05;
		label.defaultTextFormat = format;
		label.text = text;
		label.x = x - 2;
		label.y = y - 2;
		addChild(label);
	}

	private function field(name:String, x:Float, y:Float, width:Float, height:Float, align:TextFormatAlign, size:Int = 12):Void {
		var text = new TextField();
		text.name = name;
		text.x = x;
		text.y = y;
		text.width = width;
		text.height = height;
		text.selectable = false;
		text.mouseEnabled = false;
		text.defaultTextFormat = new TextFormat("Verdana", size, 0x000000, false, null, null, null, null, align);
		text.text = "--";
		addChild(text);
	}
}

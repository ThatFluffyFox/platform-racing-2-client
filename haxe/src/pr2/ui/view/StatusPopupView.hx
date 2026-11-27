package pr2.ui.view;

import openfl.text.TextField;
import openfl.text.TextFormat;
import pr2.assets.NativeAssetIds.FontAsset;
import pr2.assets.NativeAssetIds.StaticSvg;
import pr2.assets.NativeAssets;
import pr2.ui.controls.GameButton;
import pr2.ui.FlashTextBox;

/** Shared native composition for the authored Connecting and Logging In status popups. */
class StatusPopupView extends NativePopupView {
	public final closeButton:GameButton;
	public var onClose:Null<Void->Void>;

	public function new(labelText:String, connectingLayout:Bool = false) {
		// The editor reconnect flow already owns an outer dialogs.Popup. Avoid a
		// second overlay/fade when this exact authored root is embedded there.
		super(!connectingLayout, !connectingLayout);
		var offset = connectingLayout ? 0.4 : 0;
		var panel = NativeAssets.svg(StaticSvg.QuantityPanel);
		panel.name = "background";
		panel.x = -81.4 + offset;
		panel.y = -48;
		panel.scaleX = 0.604461669921875;
		panel.scaleY = 0.505264282226562;
		addChild(panel);

		var label = new TextField();
		label.name = "statusLabel";
		// ConnectingPopupGraphic's field starts 1.15px further left than LoggingInPopupGraphic's.
		FlashTextBox.applyXflBox(label, connectingLayout ? -38.55 : -37.4, -28.2, connectingLayout ? 79.6 : 77.1, 14.55);
		label.selectable = false;
		label.defaultTextFormat = new TextFormat(NativeAssets.font(FontAsset.Interface), 12, 0);
		label.text = labelText;
		addChild(label);

		closeButton = ownControl(new GameButton("Close"));
		closeButton.name = connectingLayout ? "var_1" : "close_bt";
		closeButton.x = -48.4 + offset;
		closeButton.y = 10;
		closeButton.setSize(100, 22);
		closeButton.onPress = function():Void if (onClose != null) onClose();
		addChild(closeButton);
	}

	/** These authored status roots contain static labels rather than a mutable textBox. */
	public function setMessage(_:String):Void {}

	override public function dispose():Void {
		onClose = null;
		super.dispose();
	}
}

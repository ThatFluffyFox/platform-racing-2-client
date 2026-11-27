package pr2.lobby.dialogs;

import openfl.display.DisplayObject;
import openfl.display.Shape;
import openfl.text.AntiAliasType;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;
import pr2.runtime.FontResolver;

/**
	Port of Flash `dialogs.HoverPopup`: a tooltip with a bold title over wrapped
	HTML content, on a `ShadowBG`, placed beside the hovered target via `InfoPopup`.
	An empty title and content produce nothing (matching Flash).
**/
class HoverPopup extends InfoPopup {
	private var bg:Null<openfl.display.Sprite>;
	/** Unscaled ShadowBG width: Flash's `width` of the popup (filters excluded). */
	private var panelWidth:Float = 0;

	public function new(title:String, content:String, target:DisplayObject) {
		super();
		if (title == "" && content == "") {
			return;
		}
		var titleBox = generateTextBox();
		titleBox.htmlText = "<b>" + title + "</b>";
		titleBox.y = 5;
		var contentBox = generateTextBox();
		contentBox.htmlText = content;
		contentBox.y = titleBox.height + titleBox.y + 5;

		var bgWidth = width + 10;
		var bgHeight = height + 12;
		bg = shadowBG(bgWidth, bgHeight);
		addChildAt(bg, 0);
		panelWidth = bgWidth;

		positionNear(target);
		// The drop shadow is a filter in Flash, outside the popup's measured size,
		// so it is added only once the popup has been placed.
		bg.addChildAt(dropShadow(bgWidth, bgHeight), 0);
	}

	/** Flash measures a filtered object without its shadow; so does this popup. */
	override private function get_width():Float {
		return panelWidth > 0 ? panelWidth * Math.abs(scaleX) : super.get_width();
	}

	override private function set_width(value:Float):Float {
		if (panelWidth > 0) {
			scaleX = value / panelWidth;
			return value;
		}
		return super.set_width(value);
	}

	/**
		Flash ShadowBG at width x height: its 90%-white panel, as the 9-slice grid
		(4.65, 6.65)-(267.6, 186.7) keeps it at any size. Its knocked-out drop shadow is added by
		`dropShadow`.
	**/
	public static function shadowBG(width:Float, height:Float):openfl.display.Sprite {
		var holder = new openfl.display.Sprite();
		holder.name = "bg";
		// ShadowBG's panel shape: 90% white with 4px rounded top corners, drawn at
		// size because its corners stay fixed under the 9-slice grid. (An OpenFL
		// scale9Grid shape inside a scaled popup, like the halved rating hover, was
		// squashed a second time.)
		var panel = new Shape();
		panel.name = "panel";
		panel.graphics.beginFill(0xFFFFFF, 230 / 255);
		panel.graphics.drawRoundRectComplex(0, 0, width, height, 4, 4, 0, 0);
		panel.graphics.endFill();
		holder.addChild(panel);
		return holder;
	}

	/**
		ShadowBG's knocked-out DropShadowFilter of its rectangle (black 60%, blur 3,
		distance 2 at 90 degrees, 2 passes), baked at 2x into a bitmap so it scales
		with the popup: Flash's rating hover halves the whole popup, and OpenFL's
		filter cache left the shadow at full width.
	**/
	private static function dropShadow(width:Float, height:Float):openfl.display.DisplayObject {
		#if (js && html5)
		return dropShadowBitmap(width, height);
		#else
		// Native targets render filters with the object's own transform.
		var shadow = new Shape();
		shadow.name = "shadow";
		shadow.graphics.beginFill(0xFFFFFF);
		shadow.graphics.drawRect(0, 0, width, height);
		shadow.graphics.endFill();
		shadow.filters = [new openfl.filters.DropShadowFilter(2, 90, 0x000000, 0.6, 3, 3, 1, 2, false, true)];
		return shadow;
		#end
	}

	private static function dropShadowBitmap(width:Float, height:Float):openfl.display.Bitmap {
		var density = 2;
		var pad = 6;
		var pixelWidth = Math.ceil((width + pad * 2) * density);
		var pixelHeight = Math.ceil((height + pad * 2) * density);
		var count = pixelWidth * pixelHeight;
		var source = new haxe.ds.Vector<Float>(count);
		var shadow = new haxe.ds.Vector<Float>(count);
		for (y in 0...pixelHeight) {
			var stageY = y / density - pad;
			for (x in 0...pixelWidth) {
				var stageX = x / density - pad;
				var inside = stageX >= 0 && stageX < width;
				source[y * pixelWidth + x] = inside && stageY >= 0 && stageY < height ? 1 : 0;
				shadow[y * pixelWidth + x] = inside && stageY >= 2 && stageY < height + 2 ? 1 : 0;
			}
		}
		pr2.runtime.AlphaBlur.blurAlpha(shadow, pixelWidth, pixelHeight, 3 * density, 2);
		var pixels = new openfl.Vector<UInt>(count);
		for (index in 0...count) {
			var alpha = shadow[index] * 0.6 * (1 - source[index]);
			pixels[index] = Std.int(Math.round(alpha * 255)) << 24;
		}
		var data = new openfl.display.BitmapData(pixelWidth, pixelHeight, true, 0);
		data.setVector(data.rect, pixels);
		var bitmap = new openfl.display.Bitmap(data, openfl.display.PixelSnapping.NEVER, true);
		bitmap.name = "shadow";
		bitmap.scaleX = bitmap.scaleY = 1 / density;
		bitmap.x = bitmap.y = -pad;
		return bitmap;
	}

	private function generateTextBox():TextField {
		var t = new TextField();
		var f = new TextFormat(FontResolver.resolve("Arial"));
		t.defaultTextFormat = f;
		t.width = 150;
		t.height = 1;
		t.x = 5;
		t.multiline = true;
		t.wordWrap = true;
		t.selectable = false;
		t.autoSize = TextFieldAutoSize.LEFT;
		t.antiAliasType = AntiAliasType.ADVANCED;
		addChild(t);
		return t;
	}

	override public function remove():Void {
		if (bg != null) {
			if (bg.parent == this) removeChild(bg);
			bg = null;
		}
		super.remove();
	}
}

package pr2.runtime;

import openfl.display.Shape;
import openfl.geom.ColorTransform;

/**
	An SVG channel (colorMC / colorMC2 art) that takes Flash's solid
	`ColorTransform.color` tint by drawing a recoloured copy of its SVG.
	See `SvgAsset.applySolidTint` for why a colour transform is avoided.
**/
class TintedSvgShape extends Shape {
	public final assetPath:String;
	public var tintColor(default, null):Int = -1;

	public function new(assetPath:String) {
		super();
		this.assetPath = assetPath;
		graphics.copyFrom(SvgAsset.create(assetPath).graphics);
	}

	/** Back to the SVG's own authored colours. */
	public function untint():Void {
		if (tintColor == -1) return;
		tintColor = -1;
		graphics.clear();
		graphics.copyFrom(SvgAsset.create(assetPath).graphics);
		transform.colorTransform = new ColorTransform();
	}

	public function tint(color:Int):Void {
		color &= 0xFFFFFF;
		if (color == tintColor) return;
		tintColor = color;
		if (!SvgAsset.applySolidTint(this, assetPath, color)) {
			transform.colorTransform = new ColorTransform(0, 0, 0, 1, (color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF, 0);
		}
	}
}

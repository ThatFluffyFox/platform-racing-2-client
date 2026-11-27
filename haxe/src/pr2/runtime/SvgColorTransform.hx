package pr2.runtime;

/**
	A Flash-style colour transform (per-channel multiplier plus offset, offsets
	in 0..1) as Animate exports it in a diagonal SVG `feColorMatrix`. Used to
	bake instance colour transforms into SVG paint because `format.svg`
	ignores filters.
**/
class SvgColorTransform {
	public static final IDENTITY = new SvgColorTransform([1, 1, 1, 1], [0, 0, 0, 0]);

	/** Multipliers for red, green, blue, alpha. **/
	public final multipliers:Array<Float>;

	/** Offsets for red, green, blue, alpha, in 0..1. **/
	public final offsets:Array<Float>;

	public function new(multipliers:Array<Float>, offsets:Array<Float>) {
		this.multipliers = multipliers;
		this.offsets = offsets;
	}

	public static function alpha(value:Float):SvgColorTransform {
		return new SvgColorTransform([1, 1, 1, value], [0, 0, 0, 0]);
	}

	/** This transform applied first, then `next`. **/
	public function then(next:SvgColorTransform):SvgColorTransform {
		return new SvgColorTransform([for (index in 0...4) multipliers[index] * next.multipliers[index]],
			[for (index in 0...4) offsets[index] * next.multipliers[index] + next.offsets[index]]);
	}

	public function isIdentity():Bool {
		for (index in 0...4) if (multipliers[index] != 1 || offsets[index] != 0) return false;
		return true;
	}

	public function colorOf(color:Int):Int {
		var red = channel((color >> 16) & 0xFF, 0);
		var green = channel((color >> 8) & 0xFF, 1);
		var blue = channel(color & 0xFF, 2);
		return (red << 16) | (green << 8) | blue;
	}

	public function alphaOf(value:Float):Float {
		return clamp(value * multipliers[3] + offsets[3]);
	}

	public function key():String {
		return multipliers.join(",") + ";" + offsets.join(",");
	}

	private inline function channel(value:Int, index:Int):Int {
		return Math.round(clamp(value / 255 * multipliers[index] + offsets[index]) * 255);
	}

	private static inline function clamp(value:Float):Float {
		return value < 0 ? 0 : value > 1 ? 1 : value;
	}
}

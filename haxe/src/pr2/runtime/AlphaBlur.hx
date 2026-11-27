package pr2.runtime;

import haxe.ds.Vector;

/**
	Flash's BlurFilter kernel on an alpha channel: `quality` passes of a box blur
	`size` pixels wide, horizontally then vertically, with pixels outside the
	image treated as transparent. Used to draw Flash glows and drop shadows as
	plain bitmaps, which scale with their parents (OpenFL's filter cache did not).
**/
class AlphaBlur {
	/** Blur `alpha` (width x height, row-major, 0..1) in place. */
	public static function blurAlpha(alpha:Vector<Float>, width:Int, height:Int, size:Float, quality:Int):Void {
		var scratch = new Vector<Float>(width * height);
		for (_ in 0...quality) {
			boxBlur(alpha, scratch, width, height, size, true);
			boxBlur(scratch, alpha, width, height, size, false);
		}
	}

	/**
		One box-blur pass `size` pixels wide along a row (or column). A fractional
		size blends the neighbouring odd widths so the blur grows smoothly with
		the display scale.
	**/
	public static function boxBlur(source:Vector<Float>, target:Vector<Float>, width:Int, height:Int, size:Float, horizontal:Bool):Void {
		var lower = Math.floor(size);
		if (lower % 2 == 0) lower--;
		if (lower < 1) lower = 1;
		var mix = (size - lower) / 2;
		if (mix < 0) mix = 0;
		var lines = horizontal ? height : width;
		var length = horizontal ? width : height;
		var stride = horizontal ? 1 : width;
		var lowerRadius = Std.int((lower - 1) / 2);
		var upperRadius = lowerRadius + 1;
		var prefix = new Vector<Float>(length + 1);
		for (line in 0...lines) {
			var start = horizontal ? line * width : line;
			prefix[0] = 0;
			for (position in 0...length) prefix[position + 1] = prefix[position] + source[start + position * stride];
			for (position in 0...length) {
				var value = windowSum(prefix, length, position - lowerRadius, position + lowerRadius) / lower;
				if (mix > 0) {
					var wider = windowSum(prefix, length, position - upperRadius, position + upperRadius) / (lower + 2);
					value = value * (1 - mix) + wider * mix;
				}
				target[start + position * stride] = value;
			}
		}
	}

	/** Sum of positions first..last (inclusive), clipped to the line. **/
	private static inline function windowSum(prefix:Vector<Float>, length:Int, first:Int, last:Int):Float {
		if (first < 0) first = 0;
		if (last > length - 1) last = length - 1;
		return last < first ? 0 : prefix[last + 1] - prefix[first];
	}
}

package pr2.runtime;

import openfl.display.DisplayObject;
import openfl.events.Event;
import openfl.filters.BitmapFilter;
import openfl.geom.Matrix;

/**
	Keeps a filtered display object sharp when the HTML5 stage is scaled up.

	OpenFL draws any object with filters into a cache bitmap sized for its
	stage-space bounds, leaving out the stage's display scale. With Flash's
	550x400 stage fitted to a large window, that bitmap (and the text inside
	it) is stretched several times and looks blurry. Flash drew filters at the
	output resolution, so this sets `cacheAsBitmapMatrix` to the on-screen
	scale and rebuilds the filters with blur sizes scaled to match, keeping
	the same look in stage pixels.

	`buildFilters` receives the number of cache pixels per stage pixel; multiply
	blur distances by it. The scale is refreshed when the display scale changes,
	so use this for objects whose own transform stays fixed.
**/
@:access(openfl.display.Stage)
@:access(openfl.display.DisplayObjectRenderer)
final class OutputResolutionFilters {
	private final target:DisplayObject;
	private final buildFilters:Float->Array<BitmapFilter>;
	private var appliedCacheScale:Float = -1;

	public function new(target:DisplayObject, buildFilters:Float->Array<BitmapFilter>) {
		this.target = target;
		this.buildFilters = buildFilters;
		target.filters = buildFilters(1);
		#if (js && html5)
		target.addEventListener(Event.ENTER_FRAME, update);
		target.addEventListener(Event.ADDED_TO_STAGE, update);
		#end
	}

	public function dispose():Void {
		target.removeEventListener(Event.ENTER_FRAME, update);
		target.removeEventListener(Event.ADDED_TO_STAGE, update);
		target.cacheAsBitmapMatrix = null;
		target.filters = null;
	}

	private function update(_:Null<Event>):Void {
		#if (js && html5)
		var stage = target.stage;
		if (stage == null || stage.__renderer == null) return;
		var display = stage.__displayMatrix;
		var displayScale = Math.sqrt(Math.abs(display.a * display.d - display.b * display.c));
		var pixelRatio = stage.__renderer.__pixelRatio;
		if (!(displayScale > 0) || !(pixelRatio > 0)) return;
		// OpenFL multiplies the cache matrix by the renderer's pixel ratio.
		var cacheScale = Math.max(displayScale, pixelRatio);
		if (Math.abs(cacheScale - appliedCacheScale) < 0.001) return;
		appliedCacheScale = cacheScale;

		var world = target.transform.concatenatedMatrix;
		var factor = cacheScale / pixelRatio;
		target.cacheAsBitmapMatrix = new Matrix(world.a * factor, world.b * factor, world.c * factor, world.d * factor, 0, 0);
		target.filters = buildFilters(cacheScale);
		#end
	}
}

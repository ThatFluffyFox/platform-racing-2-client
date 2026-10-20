package pr2.runtime;

#if (js && html5)
import js.Browser;
import js.html.MediaQueryList;
import lime.ui.Window;
import openfl.display.Stage;

/**
	Keeps the HTML5 canvas at the screen's real pixel density.

	Lime reads `window.devicePixelRatio` once, when the window is created, and
	sizes the canvas backing store with it from then on. Zooming the browser
	(Ctrl/Cmd +) or moving the window to a monitor with different scaling
	changes the ratio, and the canvas then stays at the old density while the
	browser stretches it: every vector and block looks soft. Flash re-rendered
	its vectors at the new size, so this follows the ratio and resizes the
	backing store (Lime's resize event then lets OpenFL re-render at the new
	output scale, and the bitmap caches re-rasterize as they do on any resize).
**/
@:access(lime.ui.Window)
@:access(lime._internal.backend.html5.HTML5Window)
@:access(openfl.display.Stage)
@:access(openfl.display.DisplayObjectRenderer)
class Html5PixelRatioSync {
	final stage:Stage;
	final window:Window;
	var query:Null<MediaQueryList> = null;

	public static function install(stage:Stage):Null<Html5PixelRatioSync> {
		var window = stage == null ? null : stage.window;
		if (window == null || window.__backend == null) return null;
		// Only when Lime follows the pixel ratio at all (high DPI on, not the DOM renderer).
		var ratio = currentRatio();
		if (Math.abs(window.__backend.scale - ratio) > 0.001) return null;
		return new Html5PixelRatioSync(stage, window);
	}

	function new(stage:Stage, window:Window) {
		this.stage = stage;
		this.window = window;
		// Browser zoom changes the CSS size too, so it arrives as a resize; a move to
		// another monitor may only change the ratio, which a resolution query reports.
		Browser.window.addEventListener("resize", function(_) sync());
		watchRatio();
	}

	static function currentRatio():Float {
		var ratio:Float = Browser.window.devicePixelRatio;
		return ratio > 0 ? ratio : 1;
	}

	function watchRatio():Void {
		var ratio = currentRatio();
		query = Browser.window.matchMedia('(resolution: ${ratio}dppx)');
		var watched = query;
		var onChange:Dynamic->Void = null;
		onChange = function(_) {
			watched.removeEventListener("change", onChange);
			sync();
			watchRatio();
		};
		watched.addEventListener("change", onChange);
	}

	/** Resizes the canvas backing store if the pixel ratio changed. Returns true when it did. **/
	public function sync():Bool {
		var ratio = currentRatio();
		var backend = window.__backend;
		if (Math.abs(backend.scale - ratio) <= 0.001) return false;
		backend.scale = ratio;
		window.__scale = ratio;
		// OpenFL keeps its own copy for vectors and text (set once when the stage starts).
		stage.__contentsScaleFactor = ratio;
		if (stage.__renderer != null) stage.__renderer.__pixelRatio = ratio;
		// Make Lime treat the element as resized, so it sets the canvas backing
		// store from the new ratio and dispatches its resize event to OpenFL.
		backend.cacheElementWidth = -1;
		backend.cacheElementHeight = -1;
		window.__width = -1;
		backend.updateSize();
		return true;
	}
}
#end

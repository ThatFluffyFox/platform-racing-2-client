package pr2.gameplay.debug;

import pr2.gameplay.debug.ClipScanner.ClipCorner;
import pr2.gameplay.debug.ClipScanner.ClipPortal;

/** A level scan over corners, run in slices: Stage 1 (ClipScanner) or Stage 1.5 (ClipPredictor). **/
interface CornerScan {
	final corners:Array<ClipCorner>;
	/** Clips found, one per corner. **/
	final portals:Array<ClipPortal>;
	/** Corners fully tried without a clip. **/
	final solidCorners:Array<ClipCorner>;
	var cornerIndex(default, null):Int;
	var done(get, never):Bool;
	/** Runs until `maxRuns` physics runs or `deadline()` says time is up. Returns runs made. **/
	function step(maxRuns:Int, ?deadline:Void->Bool):Int;
	/** Status line while running (e.g. "Scanning 3/40 corners/mines, 1 clip"). **/
	function progressText(stopped:Bool):String;
	/** Status line once done. **/
	function doneText():String;
}

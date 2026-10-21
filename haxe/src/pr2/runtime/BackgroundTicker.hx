package pr2.runtime;

import openfl.display.Stage;
import openfl.events.Event;

/**
	Keeps the game running while the browser tab is hidden or in the background.

	Browsers stop `requestAnimationFrame` in a hidden tab, which is what drives
	Lime and so every ENTER_FRAME: the race, the lobby and the Clip Finder all
	stop. They also throttle page timers (to once a second, and after a few
	minutes to once a minute), so the socket's 10 s ping came too late and the
	server (which drops a client after 60 s of silence) logged the player out;
	logging back in before it noticed gave "Your account was already running
	on this server".

	A dedicated Web Worker's timers aren't throttled that way. Its ticks
	(30 a second) drive, while the tab is hidden, the same frame OpenFL runs
	from requestAnimationFrame (ENTER_FRAME, FRAME_CONSTRUCTED, EXIT_FRAME),
	without drawing; and they run the registered intervals (the ping) whether
	the tab is hidden or not. When the tab is visible again, requestAnimationFrame
	takes over the frames.
**/
@:access(openfl.display.Stage)
class BackgroundTicker {
	static inline var TICK_MS:Int = 33;
	/** Frames are driven here only when requestAnimationFrame hasn't run for this long. **/
	static inline var STALLED_MS:Float = 250;

	static var stage:Null<Stage>;
	static var lastBrowserFrameMs:Float = 0;
	static var lastDrivenMs:Float = 0;
	static var intervals:Array<{every:Float, next:Float, run:Void->Void}> = [];
	#if js
	static var worker:Null<js.html.Worker> = null;
	#end

	/** Starts the worker (once) and drives `stage` while the tab is hidden. **/
	public static function install(target:Stage):Void {
		stage = target;
		target.addEventListener(Event.ENTER_FRAME, onBrowserFrame, false, 2000);
		start();
	}

	/**
		Runs `run` every `everyMs`, from the worker's ticks (not throttled in a
		background tab). Returns a function that stops it.
	**/
	public static function every(everyMs:Float, run:Void->Void):Void->Void {
		start();
		var entry = {every: everyMs, next: now() + everyMs, run: run};
		intervals.push(entry);
		return () -> intervals.remove(entry);
	}

	/** True when the worker is running (the browser allows it). **/
	public static function running():Bool {
		#if js
		return worker != null;
		#else
		return false;
		#end
	}

	static function start():Void {
		#if js
		if (worker != null) return;
		try {
			var source = 'setInterval(function(){postMessage(0);},$TICK_MS);';
			var blob = new js.html.Blob([source], {type: "application/javascript"});
			var url = js.html.URL.createObjectURL(blob);
			worker = new js.html.Worker(url);
			worker.onmessage = function(_) tick();
		} catch (_:Dynamic) {
			// No workers (or blocked by the page's policy): the normal timers still run.
			worker = null;
		}
		#end
	}

	static function onBrowserFrame(_:Event):Void {
		if (!driving) lastBrowserFrameMs = now();
	}

	static var driving:Bool = false;

	static function tick():Void {
		var t = now();
		for (entry in intervals.copy()) {
			if (t >= entry.next) {
				// Catch up to now without firing a burst after a long freeze.
				entry.next = t + entry.every;
				entry.run();
			}
		}
		var target = stage;
		if (target == null || !hidden()) return;
		if (t - lastBrowserFrameMs < STALLED_MS) return;
		if (t - lastDrivenMs < TICK_MS - 5) return;
		lastDrivenMs = t;
		driveFrame(target);
	}

	/** One OpenFL frame (as Stage.__onLimeRender), without drawing. **/
	static function driveFrame(target:Stage):Void {
		if (target.__rendering) return;
		driving = true;
		try {
			target.__broadcastEvent(new Event(Event.ENTER_FRAME));
			target.__broadcastEvent(new Event(Event.FRAME_CONSTRUCTED));
			target.__broadcastEvent(new Event(Event.EXIT_FRAME));
			target.__enterFrame(TICK_MS);
		} catch (e:Dynamic) {
			driving = false;
			throw e;
		}
		driving = false;
	}

	static function hidden():Bool {
		#if js
		return js.Browser.document.hidden;
		#else
		return false;
		#end
	}

	static inline function now():Float {
		#if js
		return js.Browser.window.performance.now();
		#else
		return haxe.Timer.stamp() * 1000;
		#end
	}
}

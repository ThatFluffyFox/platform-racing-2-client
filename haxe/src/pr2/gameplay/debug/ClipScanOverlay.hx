package pr2.gameplay.debug;

import openfl.display.Shape;
import pr2.gameplay.debug.ClipScanner.ClipCorner;
import pr2.gameplay.debug.ClipScanner.ClipPortal;

/** What a scanned clip does once the player is inside the wall. **/
enum abstract PortalKind(Int) {
	/** Comes to rest on the far side of the wall, or below the floor. **/
	var PassesThrough = 0;
	/** Clips in but comes back out on the side it started. **/
	var PopsBack = 1;
	/** Never comes to rest (falls out of the level or keeps going). **/
	var FallsAway = 2;
}

/**
	Debug-only world-space overlay for the Clip Finder's level scan. On each
	scanned corner's wall tile: a grey cross if it could not be clipped, or a
	coloured box if it could (green = passes through, yellow = pops back out,
	orange = falls away), with a line from the run-up start to where the player
	comes to rest.
**/
class ClipScanOverlay extends Shape {
	public static inline var COLOR_PASSES:Int = 0x22CC44;
	public static inline var COLOR_POPS_BACK:Int = 0xE8C020;
	public static inline var COLOR_FALLS:Int = 0xFF8822;
	public static inline var COLOR_SOLID:Int = 0x888888;

	public function new() {
		super();
	}

	public static function kindOf(portal:ClipPortal):PortalKind {
		var exitX = portal.exitX, exitY = portal.exitY;
		if (exitX == null || exitY == null) return FallsAway;
		return portal.passesThrough ? PassesThrough : PopsBack;
	}

	public static function colorOf(kind:PortalKind):Int {
		return switch (kind) {
			case PassesThrough: COLOR_PASSES;
			case PopsBack: COLOR_POPS_BACK;
			case FallsAway: COLOR_FALLS;
		}
	}

	public function redraw(portals:Array<ClipPortal>, solidCorners:Array<ClipCorner>):Void {
		var t = ClipSimulator.TILE;
		var g = graphics;
		g.clear();
		for (corner in solidCorners) {
			var x = corner.markX * t, y = corner.markY * t;
			g.lineStyle(1, COLOR_SOLID, 0.6);
			g.moveTo(x + 8, y + 8);
			g.lineTo(x + t - 8, y + t - 8);
			g.moveTo(x + t - 8, y + 8);
			g.lineTo(x + 8, y + t - 8);
		}
		for (portal in portals) {
			var color = colorOf(kindOf(portal));
			var corner = portal.corner;
			var x = corner.markX * t, y = corner.markY * t;
			g.lineStyle(3, color, 0.95);
			g.beginFill(color, 0.25);
			g.drawRect(x, y, t, t);
			g.endFill();
			// Run-up start (feet) to where the player ends up.
			var startX = portal.attempt.startX, startY = portal.attempt.startY - 15;
			g.lineStyle(2, color, 0.8);
			g.drawCircle(startX, startY, 4);
			var exitX = portal.exitX, exitY = portal.exitY;
			if (exitX != null && exitY != null) {
				g.moveTo(startX, startY);
				g.lineTo(exitX, exitY - 15);
				g.beginFill(color, 0.9);
				g.drawCircle(exitX, exitY - 15, 5);
				g.endFill();
			}
		}
	}

	public function dispose():Void {
		graphics.clear();
		if (parent != null) parent.removeChild(this);
	}
}

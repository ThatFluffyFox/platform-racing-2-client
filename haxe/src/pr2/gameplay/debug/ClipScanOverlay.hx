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

	/** The course turn the scan ran in (its positions are that turn's course coordinates). **/
	public var scanRotation:Int = 0;
	/** The course turn it is drawn for: the course's turn now (the layer turns with the course). **/
	public var viewRotation(default, null):Int = 0;

	var lastPortals:Array<ClipPortal> = [];
	var lastSolid:Array<ClipCorner> = [];

	public function new() {
		super();
	}

	/** Redraws for the course turned by `rotation` (when the course has turned since). **/
	public function setViewRotation(rotation:Int):Void {
		if (rotation == viewRotation) return;
		viewRotation = rotation;
		redraw(lastPortals, lastSolid);
	}

	/** A scan position in the coordinates the overlay is drawn in. **/
	function view(x:Float, y:Float):{x:Float, y:Float} {
		if (scanRotation == viewRotation) return {x: x, y: y};
		var level = ClipSimulator.toLevel(x, y, scanRotation);
		return ClipSimulator.toCourse(level.x, level.y, viewRotation);
	}

	/** A scan tile's corner nearest the origin once turned, for drawing it as a box. **/
	function viewTile(tileX:Int, tileY:Int):{x:Float, y:Float} {
		var t = ClipSimulator.TILE;
		var c = view(tileX * t + t / 2, tileY * t + t / 2);
		return {x: c.x - t / 2, y: c.y - t / 2};
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
		lastPortals = portals;
		lastSolid = solidCorners;
		var t = ClipSimulator.TILE;
		var g = graphics;
		g.clear();
		for (corner in solidCorners) {
			var box = viewTile(corner.markX, corner.markY);
			var x = box.x, y = box.y;
			g.lineStyle(1, COLOR_SOLID, 0.6);
			g.moveTo(x + 8, y + 8);
			g.lineTo(x + t - 8, y + t - 8);
			g.moveTo(x + t - 8, y + 8);
			g.lineTo(x + 8, y + t - 8);
		}
		for (portal in portals) {
			var color = colorOf(kindOf(portal));
			var corner = portal.corner;
			var box = viewTile(corner.markX, corner.markY);
			var x = box.x, y = box.y;
			g.lineStyle(3, color, 0.95);
			g.beginFill(color, 0.25);
			g.drawRect(x, y, t, t);
			g.endFill();
			// Run-up start (feet) to where the player ends up.
			var start = view(portal.attempt.startX, portal.attempt.startY - 15);
			g.lineStyle(2, color, 0.8);
			g.drawCircle(start.x, start.y, 4);
			var exitX = portal.exitX, exitY = portal.exitY;
			if (exitX != null && exitY != null) {
				// The exit is in level space (from the ghost).
				var exit = ClipSimulator.toCourse(exitX, exitY - 15, viewRotation);
				g.moveTo(start.x, start.y);
				g.lineTo(exit.x, exit.y);
				g.beginFill(color, 0.9);
				g.drawCircle(exit.x, exit.y, 5);
				g.endFill();
			}
		}
	}

	public function dispose():Void {
		graphics.clear();
		if (parent != null) parent.removeChild(this);
	}
}

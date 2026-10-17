package pr2.gameplay.debug;

import pr2.character.Character;
import pr2.gameplay.debug.ClipSimulator.GhostFrame;
import pr2.gameplay.player.PlayerDisplayPlacement;

/**
	Debug-only translucent character that replays a recorded clip run on a loop:
	it plays the run from the start position, holds briefly on the last frame,
	then resets to the start and plays it again.
**/
class ClipGhost {
	public static inline var GHOST_ALPHA:Float = 0.5;
	/** Frames the ghost holds its final pose before resetting. **/
	public static inline var HOLD_FRAMES:Int = 20;

	public final character:Character;
	var frames:Array<GhostFrame> = [];
	var index:Int = 0;
	var holdRemaining:Int = 0;

	/** Copies the look (parts, hats, colours) of `source`, normally the local player. **/
	public function new(source:Character) {
		character = new Character(source.hat1, source.head, source.body, source.feet);
		character.setColors(source.hat1Color, source.hat1Color2, source.headColor, source.headColor2, source.bodyColor, source.bodyColor2,
			source.feetColor, source.feetColor2);
		// setHats takes [id, colour, colour2] triples, one per worn hat.
		character.setHats([
			source.hat1, source.hat1Color, source.hat1Color2,
			source.hat2, source.hat2Color, source.hat2Color2,
			source.hat3, source.hat3Color, source.hat3Color2,
			source.hat4, source.hat4Color, source.hat4Color2
		]);
		character.alpha = GHOST_ALPHA;
		character.mouseEnabled = false;
		character.mouseChildren = false;
		character.visible = false;
	}

	public function play(recorded:Array<GhostFrame>):Void {
		frames = recorded;
		index = 0;
		holdRemaining = 0;
		character.visible = frames.length > 0;
		pose();
	}

	public function stop():Void {
		frames = [];
		character.visible = false;
	}

	public var playing(get, never):Bool;
	inline function get_playing():Bool return frames.length > 0;

	/** Advance one simulation frame. **/
	public function tick():Void {
		if (frames.length == 0) return;
		if (index >= frames.length - 1) {
			if (holdRemaining++ < HOLD_FRAMES) return;
			index = 0;
			holdRemaining = 0;
		} else {
			index++;
		}
		pose();
	}

	/** True while the replayed body is inside a block (the panel shows "clipping"). **/
	public function inSolid():Bool {
		return frames.length > 0 && frames[index].inSolid;
	}

	function pose():Void {
		if (frames.length == 0) return;
		var frame = frames[index];
		PlayerDisplayPlacement.place(character, character.display, frame.x, frame.y, frame.facing, 0);
		var clip = frame.state.toClipName();
		if (!character.display.isState(clip)) character.display.setState(clip);
		character.display.advanceOneFrame();
	}

	public function dispose():Void {
		stop();
		if (character.parent != null) character.parent.removeChild(character);
	}
}

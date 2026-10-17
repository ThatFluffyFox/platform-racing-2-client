package pr2.gameplay.debug;

import openfl.display.DisplayObjectContainer;
import pr2.character.Character;
import pr2.character.LocalCharacter;
import pr2.gameplay.debug.ClipFinder.ClipFinderSettings;
import pr2.gameplay.debug.ClipSimulator.ClipAttempt;
import pr2.gameplay.debug.ClipSimulator.ClipHats;
import pr2.level.Level;

/**
	Debug-only Clip Finder, toggled in a race with F9+C+D (see Course).

	Opens a panel with stat ranges that default to the local player's current
	stats, then searches stat/input combinations from where the player is
	standing in a cropped copy of the level, a few attempts per frame so the
	race keeps running. Every attempt starts from a fresh simulated player.
	A translucent ghost of the player replays the selected clip on a loop.

	The search never touches the real player, blocks or network state.
**/
class ClipFinderSession {
	/** Simulation time allowed per game frame, so the race keeps its frame rate. **/
	public static inline var FRAME_BUDGET_SECONDS:Float = 0.006;
	/** LocalCharacter.setHats: the moon hat multiplies gravity by 0.85. **/
	static inline var MOON_GRAVITY:Float = 0.85;

	final level:Level;
	final player:LocalCharacter;
	final panelLayer:DisplayObjectContainer;
	final ghostLayer:DisplayObjectContainer;
	final panel:ClipFinderPanel;
	final ghost:ClipGhost;
	var finder:Null<ClipFinder> = null;
	/** Clips from the latest search; kept after Stop so Prev/Next still work. **/
	var clips:Array<ClipFinder.FoundClip> = [];
	var shownClips:Int = 0;
	var selectedClip:Int = -1;
	public var closed(default, null):Bool = false;
	public var onClosed:Null<Void->Void>;

	public function new(level:Level, player:LocalCharacter, panelLayer:DisplayObjectContainer, ghostLayer:DisplayObjectContainer) {
		this.level = level;
		this.player = player;
		this.panelLayer = panelLayer;
		this.ghostLayer = ghostLayer;
		var state = player.stateSnapshot();
		panel = new ClipFinderPanel(state.speedStat, state.accelerationStat, state.jumpStat);
		panel.x = 8;
		panel.y = 24;
		panel.onStart = start;
		panel.onStop = stopSearch;
		panel.onClose = close;
		panel.onShowClip = showClip;
		panelLayer.addChild(panel);
		ghost = new ClipGhost(player);
		ghostLayer.addChild(ghost.character);
		var hats = ClipHats.from(player.controller).names();
		if (player.hasHatFlag(Character.MOON)) hats.push("moon");
		panel.setStatus(state.courseRotation != 0 ? "Course is rotated." : (hats.length == 0 ? "Ready." : 'Ready (hats: ${hats.join(", ")})'));
	}

	function start():Void {
		var state = player.stateSnapshot();
		if (state.courseRotation != 0) {
			panel.setStatus("Only works while the course is upright.");
			return;
		}
		var dirs:Array<Int> = [];
		if (panel.rightBox.selected) dirs.push(1);
		if (panel.leftBox.selected) dirs.push(-1);
		if (dirs.length == 0) {
			panel.setStatus("Tick Left and/or Right.");
			return;
		}
		// Same gravity and hat physics as the real player: the moon hat lowers
		// gravity (LocalCharacter.setHats), the other hats are controller flags.
		var gravity = level.gravity * (player.hasHatFlag(Character.MOON) ? MOON_GRAVITY : 1);
		var settings = new ClipFinderSettings(Math.round(state.x), Math.round(state.y), gravity, panel.speedRow.range(),
			panel.accelRow.range(), panel.jumpRow.range());
		settings.hats = ClipHats.from(player.controller);
		settings.dirs = dirs;
		settings.downModes = panel.downBox.selected ? [false, true] : [false];
		settings.normalJumps = panel.normalJumpRow.enabled;
		settings.maxJumpFrame = panel.normalJumpRow.upTo();
		settings.superCharges = panel.superJumpRow.enabled ? [for (c in ClipAttempt.MIN_SUPER_CHARGE...panel.superJumpRow.upTo() + 1) c] : [];
		if (!settings.normalJumps && settings.superCharges.length == 0) {
			panel.setStatus("Tick Normal jump and/or Super jump.");
			return;
		}
		// Delayed move and air turn add to the default (move at once, never turn).
		settings.moveStarts = panel.delayedMoveRow.enabled ? [for (m in 0...panel.delayedMoveRow.upTo() + 1) m] : [0];
		settings.turnFrames = panel.airTurnRow.enabled ? [-1].concat([for (t in 1...panel.airTurnRow.upTo() + 1) t]) : [-1];
		finder = new ClipFinder(level.blocks, settings);
		clips = finder.clips;
		shownClips = 0;
		selectedClip = -1;
		ghost.stop();
		panel.setClipCount(0);
		panel.setRunning(true);
		updateStatus();
	}

	function stopSearch():Void {
		if (finder == null) return;
		panel.setRunning(false);
		updateStatus(true);
		finder = null;
	}

	/** Called once per simulation frame by the course. **/
	public function tick():Void {
		if (closed) return;
		var search = finder;
		if (search != null && !search.done) {
			var deadline = haxe.Timer.stamp() + FRAME_BUDGET_SECONDS;
			search.step(1000, () -> haxe.Timer.stamp() > deadline);
			if (search.clips.length != shownClips) {
				shownClips = search.clips.length;
				panel.setClipCount(shownClips);
				// Start the ghost on the first clip; later clips are a Next click away.
				if (selectedClip < 0) showClip(0);
			}
			updateStatus();
			if (search.done) panel.setRunning(false);
		}
		ghost.tick();
	}

	function showClip(index:Int):Void {
		if (index < 0 || index >= clips.length) return;
		selectedClip = index;
		var found = clips[index];
		var recorded = found.run.ghost;
		if (recorded != null) ghost.play(recorded);
		panel.setClipInfo(index, '${found.attempt.describe()}, clips on frame ${found.run.clipFrame + 1}. Replaying on a loop.');
	}

	function updateStatus(stopped:Bool = false):Void {
		var search = finder;
		if (search == null) return;
		if (search.blockedStart) {
			panel.setStatus("Can't start here: inside a block.");
			return;
		}
		var verb = search.done ? "Done" : (stopped ? "Stopped" : "Testing");
		panel.setStatus('$verb ${search.tested}/${search.total}, ${search.clipCount} clip${search.clipCount == 1 ? "" : "s"}');
	}

	public function close():Void {
		if (closed) return;
		closed = true;
		finder = null;
		ghost.dispose();
		panel.dispose();
		if (onClosed != null) onClosed();
		onClosed = null;
	}
}

package pr2.gameplay.debug;

import openfl.text.TextField;
import openfl.text.TextFormat;
import pr2.assets.NativeAssetIds.FontAsset;
import pr2.assets.NativeAssets;
import pr2.gameplay.debug.ClipSimulator.ClipAttempt;
import pr2.ui.controls.GameButton;
import pr2.ui.controls.GameCheckBox;
import pr2.ui.controls.GameSelect;
import pr2.ui.controls.GameSlider;
import pr2.ui.controls.SelectOption;
import pr2.ui.view.NativeView;

/** The stages in the panel's "Scan level" menu. **/
enum abstract ScanStage(Int) {
	/** Stage 1: every inside corner in the level, tried with your stats. **/
	var MapScan = 0;
	/** Stage 2: a route from where you stand to the target block. **/
	var RouteToTarget = 1;
	/** Stage 1.5: predicted clips, worked back from landings to start spots anywhere in the level. **/
	var PredictedScan = 2;
	/** Stage 3: movement glitches (higher, faster, or through block edges compared with open ground). **/
	var MovementGlitches = 3;
}

/**
	Debug-only Clip Finder panel (opened in a race with F9+C+D). It sits in the
	corner without dimming the course so the ghost replay stays visible.

	Each stat is fixed at the player's current value unless its "Range" box is
	ticked, which enables a min and a max slider (both starting at the current
	value). Below the stats, each kind of move has a tick box and a slider for
	how many frames of timing to try. All behaviour lives in ClipFinderSession;
	this view only reports what the user picked.
**/
class ClipFinderPanel extends NativeView {
	public static inline var PANEL_WIDTH:Float = 262;
	public static inline var PANEL_HEIGHT:Float = 410;

	public var onStart:Null<Void->Void>;
	public var onStop:Null<Void->Void>;
	public var onClose:Null<Void->Void>;
	public var onShowClip:Null<Int->Void>;
	public var onReplay:Null<Void->Void>;

	public final speedRow:StatRow;
	public final accelRow:StatRow;
	public final jumpRow:StatRow;
	public final leftBox:GameCheckBox;
	public final rightBox:GameCheckBox;
	public final downBox:GameCheckBox;
	/** Normal jumps pressed on frames 0..N. **/
	public final normalJumpRow:OptionRow;
	/** Super jumps charged for 13..N frames. **/
	public final superJumpRow:OptionRow;
	/** Start holding the direction on frames 0..N (jump or stand in place first). **/
	public final delayedMoveRow:OptionRow;
	/** Flip the held direction on frames 1..N. **/
	public final airTurnRow:OptionRow;
	/** Ignore the sliders: the ticked moves may happen on any frame (random search until Stop). **/
	public final anyFrameBox:GameCheckBox;
	/** Only count clips into the picked target block (ticked automatically when one is picked). **/
	public final aimBox:GameCheckBox;
	final rows:Array<OptionRow>;
	final startButton:GameButton;
	final prevButton:GameButton;
	final nextButton:GameButton;
	/** Plays the shown clip's inputs on the real player. **/
	public final replayButton:GameButton;
	/** Pick (or clear) the one block clips must go into. **/
	public final targetButton:GameButton;
	public var onTarget:Null<Void->Void>;
	/**
		"Scan level" menu with the two stages: Stage 1 scans every corner in the
		level for clips with your stats; Stage 2 plans a route from where you
		stand to the target block, clipping through blocks when needed.
	**/
	public final scanSelect:GameSelect<ScanStage>;
	public var onScan:Null<Void->Void>;
	/** Stage 1.5 (predicted clips) picked. **/
	public var onPredict:Null<Void->Void>;
	/** Stage 3 (movement glitches) picked. **/
	public var onGlitches:Null<Void->Void>;
	public var onRoute:Null<Void->Void>;
	final status:TextField;
	final clipInfo:TextField;
	var shownClip:Int = 0;
	var clipTotal:Int = 0;

	public function new(speed:Float, accel:Float, jump:Float) {
		super();
		graphics.lineStyle(1, 0x333333);
		graphics.beginFill(0xFFFFFF, 0.93);
		graphics.drawRoundRect(0, 0, PANEL_WIDTH, PANEL_HEIGHT, 10, 10);
		graphics.endFill();

		addChild(text("Clip Finder", 10, 6, 200, 14, true));
		var close = ownControl(new GameButton("X"));
		close.setSize(22, 20);
		close.x = PANEL_WIDTH - 30;
		close.y = 5;
		close.onPress = function():Void if (onClose != null) onClose();
		addChild(close);
		// "Scan level" menu: picking a stage runs it, then the menu shows its title again.
		scanSelect = ownControl(new GameSelect<ScanStage>());
		scanSelect.setSize(176, 18);
		scanSelect.x = 10;
		scanSelect.y = 19;
		scanSelect.prompt = "Scan level...";
		scanSelect.addOption("Stage 1: map scan (every corner)", MapScan);
		scanSelect.addOption("Stage 1.5: predicted clips", PredictedScan);
		scanSelect.addOption("Stage 2: route to target", RouteToTarget);
		scanSelect.addOption("Stage 3: movement glitches", MovementGlitches);
		scanSelect.rowCount = 4;
		scanSelect.onChange = function(option:SelectOption<ScanStage>):Void {
			scanSelect.selectedIndex = -1;
			chooseScanStage(option.value);
		};
		addChild(scanSelect);

		targetButton = ownControl(new GameButton("Target: any block"));
		targetButton.setSize(140, 20);
		targetButton.x = PANEL_WIDTH - 176;
		targetButton.y = 5;
		targetButton.onPress = function():Void if (onTarget != null) onTarget();
		addChild(targetButton);

		speedRow = new StatRow(this, "Speed", speed, 36);
		accelRow = new StatRow(this, "Accel", accel, 76);
		jumpRow = new StatRow(this, "Jump", jump, 116);

		leftBox = checkBox("Left", true, 10, 146);
		rightBox = checkBox("Right", true, 70, 146);
		downBox = checkBox("Try fast-fall", true, 135, 146);

		normalJumpRow = new OptionRow(this, "Normal jump", true, 170, 0, 60, 20, v -> 'frames 0-$v');
		superJumpRow = new OptionRow(this, "Super jump", false, 194, ClipAttempt.MIN_SUPER_CHARGE, ClipAttempt.MAX_SUPER_CHARGE,
			ClipAttempt.MAX_SUPER_CHARGE, v -> 'charge ${ClipAttempt.MIN_SUPER_CHARGE}-$v');
		delayedMoveRow = new OptionRow(this, "Delayed move", false, 218, 1, 60, 20, v -> 'start 0-$v');
		airTurnRow = new OptionRow(this, "Air turn", false, 242, 1, 60, 30, v -> 'turn 1-$v');
		rows = [normalJumpRow, superJumpRow, delayedMoveRow, airTurnRow];

		anyFrameBox = checkBox("Any frame (random)", false, 10, 266);
		anyFrameBox.setSize(120, 22);
		anyFrameBox.onChange = function(selected:Bool):Void for (row in rows) row.setAnyFrame(selected);
		aimBox = checkBox("Aim at target", false, 140, 266);
		aimBox.setSize(110, 22);

		startButton = ownControl(new GameButton("Start"));
		startButton.setSize(80, 22);
		startButton.x = 10;
		startButton.y = 292;
		startButton.onPress = function():Void {
			if (startButton.label == "Start") {
				if (onStart != null) onStart();
			} else if (onStop != null) {
				onStop();
			}
		};
		addChild(startButton);

		status = text("", 98, 296, 158, 12);
		addChild(status);

		prevButton = ownControl(new GameButton("< Prev"));
		prevButton.setSize(60, 22);
		prevButton.x = 10;
		prevButton.y = 318;
		prevButton.onPress = function():Void showClip(shownClip - 1);
		addChild(prevButton);
		nextButton = ownControl(new GameButton("Next >"));
		nextButton.setSize(60, 22);
		nextButton.x = 76;
		nextButton.y = 318;
		nextButton.onPress = function():Void showClip(shownClip + 1);
		addChild(nextButton);
		replayButton = ownControl(new GameButton("Replay on me"));
		replayButton.setSize(110, 22);
		replayButton.x = 142;
		replayButton.y = 318;
		replayButton.onPress = function():Void if (onReplay != null) onReplay();
		addChild(replayButton);

		clipInfo = text("", 10, 344, PANEL_WIDTH - 20, 60);
		clipInfo.multiline = true;
		clipInfo.wordWrap = true;
		addChild(clipInfo);
		setClipCount(0);
	}

	public function setRunning(running:Bool):Void {
		startButton.label = running ? "Stop" : "Start";
		for (row in [speedRow, accelRow, jumpRow]) row.setLocked(running);
		for (box in [leftBox, rightBox, downBox, anyFrameBox, aimBox]) box.enabled = !running;
		targetButton.enabled = !running;
		scanSelect.enabled = !running;
		for (row in rows) row.setLocked(running);
	}

	public function setStatus(value:String):Void status.text = value;

	/** Runs a stage from the "Scan level" menu (also what a pick in the menu does). **/
	public function chooseScanStage(stage:ScanStage):Void {
		switch (stage) {
			case MapScan:
				if (onScan != null) onScan();
			case PredictedScan:
				if (onPredict != null) onPredict();
			case MovementGlitches:
				if (onGlitches != null) onGlitches();
			case RouteToTarget:
				if (onRoute != null) onRoute();
		}
	}

	public function setClipCount(count:Int):Void {
		clipTotal = count;
		prevButton.enabled = count > 1;
		nextButton.enabled = count > 1;
		replayButton.enabled = count > 0;
		if (count == 0) {
			shownClip = 0;
			clipInfo.text = "No clips yet. The ghost replays a clip on a loop once one is found.";
		}
	}

	/** Free text in the info box (e.g. why a route search found nothing). **/
	public function setInfo(text:String):Void clipInfo.text = text;

	public function setClipInfo(index:Int, description:String):Void {
		shownClip = index;
		clipInfo.text = 'Clip ${index + 1}/$clipTotal: $description';
	}

	function showClip(index:Int):Void {
		if (clipTotal == 0) return;
		var wrapped = ((index % clipTotal) + clipTotal) % clipTotal;
		if (onShowClip != null) onShowClip(wrapped);
	}

	function checkBox(label:String, selected:Bool, x:Float, y:Float):GameCheckBox {
		var box = ownControl(new GameCheckBox(label, selected));
		box.x = x;
		box.y = y;
		addChild(box);
		return box;
	}

	public function text(value:String, x:Float, y:Float, width:Float, height:Float, bold:Bool = false):TextField {
		var field = new TextField();
		field.x = x;
		field.y = y;
		field.width = width;
		field.height = height + 4;
		field.selectable = false;
		field.mouseEnabled = false;
		field.defaultTextFormat = new TextFormat(NativeAssets.font(FontAsset.Interface), bold ? 12 : 10, 0, bold);
		field.text = value;
		return field;
	}

	override public function dispose():Void {
		onStart = null;
		onStop = null;
		onClose = null;
		onShowClip = null;
		onReplay = null;
		onTarget = null;
		onScan = null;
		onPredict = null;
		onGlitches = null;
		onRoute = null;
		super.dispose();
	}
}

/** One stat: "Range" checkbox plus min/max sliders that start at the player's value. **/
class StatRow {
	public final current:Float;
	final rangeBox:GameCheckBox;
	final minSlider:GameSlider;
	final maxSlider:GameSlider;
	final label:TextField;
	final name:String;
	var locked:Bool = false;

	public function new(panel:ClipFinderPanel, name:String, current:Float, y:Float) {
		this.name = name;
		this.current = Math.round(current);
		label = panel.text("", 10, y, 150, 12);
		panel.addChild(label);
		rangeBox = panel.ownControl(new GameCheckBox("Range", false));
		rangeBox.x = 190;
		rangeBox.y = y - 3;
		rangeBox.onChange = function(_):Void refresh();
		panel.addChild(rangeBox);
		minSlider = panel.ownControl(new GameSlider(0, 100, this.current, 1));
		minSlider.setSize(110, 22);
		minSlider.x = 10;
		minSlider.y = y + 16;
		panel.addChild(minSlider);
		maxSlider = panel.ownControl(new GameSlider(0, 100, this.current, 1));
		maxSlider.setSize(110, 22);
		maxSlider.x = 140;
		maxSlider.y = y + 16;
		panel.addChild(maxSlider);
		// Keep min <= max while dragging either thumb.
		minSlider.onChange = function(v:Float):Void {
			if (v > maxSlider.value) maxSlider.value = v;
			refresh();
		};
		maxSlider.onChange = function(v:Float):Void {
			if (v < minSlider.value) minSlider.value = v;
			refresh();
		};
		refresh();
	}

	public var useRange(get, never):Bool;
	function get_useRange():Bool return rangeBox.selected;

	/** Ticks Range and sets both ends (what dragging the two sliders does). **/
	public function setRange(min:Float, max:Float):Void {
		rangeBox.selected = true;
		minSlider.value = min;
		maxSlider.value = max;
		refresh();
	}

	public function range():ClipFinder.StatRange {
		return useRange ? new ClipFinder.StatRange(minSlider.value, maxSlider.value, 1) : ClipFinder.StatRange.fixed(current);
	}

	public function setLocked(value:Bool):Void {
		locked = value;
		refresh();
	}

	function refresh():Void {
		if (!useRange) {
			minSlider.value = current;
			maxSlider.value = current;
		}
		rangeBox.enabled = !locked;
		minSlider.enabled = useRange && !locked;
		maxSlider.enabled = useRange && !locked;
		label.text = useRange ? '$name ${Std.int(minSlider.value)} to ${Std.int(maxSlider.value)}' : '$name ${Std.int(current)} (your stat)';
	}
}

/** A move option: tick box, a label describing the frames tried, and a slider for the upper frame. **/
class OptionRow {
	public final box:GameCheckBox;
	public final slider:GameSlider;
	final label:TextField;
	final describe:Int->String;
	var locked:Bool = false;
	var anyFrame:Bool = false;

	public function new(panel:ClipFinderPanel, name:String, selected:Bool, y:Float, min:Float, max:Float, value:Float, describe:Int->String) {
		this.describe = describe;
		box = panel.ownControl(new GameCheckBox(name, selected));
		box.x = 10;
		box.y = y;
		box.onChange = function(_):Void refresh();
		panel.addChild(box);
		label = panel.text("", 105, y + 3, 60, 12);
		panel.addChild(label);
		slider = panel.ownControl(new GameSlider(min, max, value, 1));
		slider.setSize(85, 22);
		slider.x = 168;
		slider.y = y + 2;
		slider.onChange = function(_):Void refresh();
		panel.addChild(slider);
		refresh();
	}

	public var enabled(get, never):Bool;
	function get_enabled():Bool return box.selected;

	/** The slider's value: the highest frame (or charge) to try. **/
	public function upTo():Int return Std.int(slider.value);

	public function setLocked(value:Bool):Void {
		locked = value;
		refresh();
	}

	/** With "Any frame" the slider is ignored; the tick box still picks whether the move is tried. **/
	public function setAnyFrame(value:Bool):Void {
		anyFrame = value;
		refresh();
	}

	function refresh():Void {
		box.enabled = !locked;
		slider.enabled = box.selected && !locked && !anyFrame;
		label.text = !box.selected ? "off" : (anyFrame ? "any frame" : describe(upTo()));
	}
}

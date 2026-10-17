package pr2.gameplay.debug;

import openfl.text.TextField;
import openfl.text.TextFormat;
import pr2.assets.NativeAssetIds.FontAsset;
import pr2.assets.NativeAssets;
import pr2.ui.controls.GameButton;
import pr2.ui.controls.GameCheckBox;
import pr2.ui.controls.GameSlider;
import pr2.ui.view.NativeView;

/**
	Debug-only Clip Finder panel (opened in a race with F9+C+D). It sits in the
	corner without dimming the course so the ghost replay stays visible.

	Each stat is fixed at the player's current value unless its "Range" box is
	ticked, which enables a min and a max slider (both starting at the current
	value). All behaviour lives in ClipFinderSession; this view only reports
	what the user picked.
**/
class ClipFinderPanel extends NativeView {
	public static inline var PANEL_WIDTH:Float = 262;
	public static inline var PANEL_HEIGHT:Float = 318;

	public var onStart:Null<Void->Void>;
	public var onStop:Null<Void->Void>;
	public var onClose:Null<Void->Void>;
	public var onShowClip:Null<Int->Void>;

	public final speedRow:StatRow;
	public final accelRow:StatRow;
	public final jumpRow:StatRow;
	public final leftBox:GameCheckBox;
	public final rightBox:GameCheckBox;
	public final downBox:GameCheckBox;
	public final jumpWindowSlider:GameSlider;
	final jumpWindowLabel:TextField;
	final startButton:GameButton;
	final prevButton:GameButton;
	final nextButton:GameButton;
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
		addChild(text("Searches from where you are standing.", 10, 22, 240, 12));

		speedRow = new StatRow(this, "Speed", speed, 40);
		accelRow = new StatRow(this, "Accel", accel, 82);
		jumpRow = new StatRow(this, "Jump", jump, 124);

		leftBox = ownControl(new GameCheckBox("Left", true));
		leftBox.x = 10;
		leftBox.y = 168;
		addChild(leftBox);
		rightBox = ownControl(new GameCheckBox("Right", true));
		rightBox.x = 70;
		rightBox.y = 168;
		addChild(rightBox);
		downBox = ownControl(new GameCheckBox("Try fast-fall", true));
		downBox.x = 135;
		downBox.y = 168;
		addChild(downBox);

		jumpWindowLabel = text("", 10, 192, 140, 12);
		addChild(jumpWindowLabel);
		jumpWindowSlider = ownControl(new GameSlider(0, 60, 20, 1));
		jumpWindowSlider.setSize(100, 22);
		jumpWindowSlider.x = 150;
		jumpWindowSlider.y = 194;
		jumpWindowSlider.onChange = function(_):Void updateJumpWindowLabel();
		addChild(jumpWindowSlider);
		updateJumpWindowLabel();

		startButton = ownControl(new GameButton("Start"));
		startButton.setSize(80, 22);
		startButton.x = 10;
		startButton.y = 214;
		startButton.onPress = function():Void {
			if (startButton.label == "Start") {
				if (onStart != null) onStart();
			} else if (onStop != null) {
				onStop();
			}
		};
		addChild(startButton);

		status = text("", 98, 218, 158, 12);
		addChild(status);

		prevButton = ownControl(new GameButton("< Prev"));
		prevButton.setSize(60, 22);
		prevButton.x = 10;
		prevButton.y = 242;
		prevButton.onPress = function():Void showClip(shownClip - 1);
		addChild(prevButton);
		nextButton = ownControl(new GameButton("Next >"));
		nextButton.setSize(60, 22);
		nextButton.x = 76;
		nextButton.y = 242;
		nextButton.onPress = function():Void showClip(shownClip + 1);
		addChild(nextButton);

		clipInfo = text("", 10, 268, PANEL_WIDTH - 20, 44);
		clipInfo.multiline = true;
		clipInfo.wordWrap = true;
		addChild(clipInfo);
		setClipCount(0);
	}

	public function setRunning(running:Bool):Void {
		startButton.label = running ? "Stop" : "Start";
		for (row in [speedRow, accelRow, jumpRow]) row.setLocked(running);
		for (box in [leftBox, rightBox, downBox]) box.enabled = !running;
		jumpWindowSlider.enabled = !running;
	}

	public function setStatus(value:String):Void status.text = value;

	public function setClipCount(count:Int):Void {
		clipTotal = count;
		prevButton.enabled = count > 1;
		nextButton.enabled = count > 1;
		if (count == 0) {
			shownClip = 0;
			clipInfo.text = "No clips yet. The ghost replays a clip on a loop once one is found.";
		}
	}

	public function setClipInfo(index:Int, description:String):Void {
		shownClip = index;
		clipInfo.text = 'Clip ${index + 1}/$clipTotal: $description';
	}

	function showClip(index:Int):Void {
		if (clipTotal == 0) return;
		var wrapped = ((index % clipTotal) + clipTotal) % clipTotal;
		if (onShowClip != null) onShowClip(wrapped);
	}

	function updateJumpWindowLabel():Void {
		jumpWindowLabel.text = 'Jump on frames 0-${Std.int(jumpWindowSlider.value)}';
	}

	public function jumpWindow():Int return Std.int(jumpWindowSlider.value);

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
		minSlider.y = y + 18;
		panel.addChild(minSlider);
		maxSlider = panel.ownControl(new GameSlider(0, 100, this.current, 1));
		maxSlider.setSize(110, 22);
		maxSlider.x = 140;
		maxSlider.y = y + 18;
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

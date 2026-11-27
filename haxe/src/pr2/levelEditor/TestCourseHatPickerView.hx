package pr2.levelEditor;

import openfl.display.Sprite;
import openfl.events.Event;
import openfl.filters.DropShadowFilter;
import openfl.geom.Matrix;
import pr2.character.CharacterRig;
import pr2.character.CharacterRig.RigPartChannels;
import pr2.runtime.SvgAsset;
import pr2.ui.view.NativeView;

/** Exact native composition of XFL `HatPickerGraphic`. */
class TestCourseHatPickerView extends NativeView {
	private final hat:Sprite;
	private var overlay:Null<Sprite>;
	private var overlayFrames:Array<String> = [];
	public var overlayCurrentFrame(default, null):Int = 0;

	public function new() {
		super();
		hat = new Sprite();
		hat.name = "hat";
		hat.transform.matrix = new Matrix(0.300888061523438, 0.0806121826171875, -0.0806121826171875, 0.300888061523438, 56, 20);
		addChild(hat);
		arrow("left", 10, -0.999984741210938);
		arrow("right", 100, 1);
		listen(this, Event.ENTER_FRAME, advanceOverlay);
	}

	public function setHat(id:Int):Void {
		while (hat.numChildren > 0) hat.removeChildAt(0);
		overlay = null;
		overlayFrames = [];
		overlayCurrentFrame = 0;
		var channels = hatChannels(id);
		pr2.character.CharacterView.addFixedLayer(hat, channels.fixedBelow, "fixedBelow");
		var primary = SvgAsset.create(channels.primary);
		primary.name = "colorMC";
		hat.addChild(primary);
		var fixed = SvgAsset.create(channels.fixed);
		fixed.name = "fixed";
		hat.addChild(fixed);
		var secondary = SvgAsset.create(channels.secondary);
		secondary.name = "colorMC2";
		secondary.visible = id == 16;
		hat.addChild(secondary);
		pr2.character.CharacterView.addFixedLayer(hat, channels.fixedAbove, "fixedAbove");
		if (channels.overlayAnimation != null && channels.overlayAnimation.frames.length > 0) {
			overlayFrames = channels.overlayAnimation.frames.copy();
			overlay = new Sprite();
			overlay.name = "animatedOverlay";
			hat.addChild(overlay);
			renderOverlayFrame();
		}
	}

	private function advanceOverlay(_:Event):Void {
		if (!pr2.runtime.FrameClock.shouldRunSimulationFrame()) return;
		stepOverlay();
	}

	private function stepOverlay():Void {
		if (overlayFrames.length == 0) return;
		overlayCurrentFrame = (overlayCurrentFrame + 1) % overlayFrames.length;
		renderOverlayFrame();
	}

	private function renderOverlayFrame():Void {
		if (overlay == null || overlayFrames.length == 0) return;
		while (overlay.numChildren > 0) overlay.removeChildAt(0);
		var frame = SvgAsset.create(overlayFrames[overlayCurrentFrame]);
		frame.name = "vectorFrame";
		overlay.addChild(frame);
	}

	public function advanceOverlayFrameForTests():Void stepOverlay();

	private function arrow(name:String, x:Float, scaleX:Float):Void {
		var arrow = new EditorNativeGraphic("HatPickerArrow");
		arrow.name = name;
		arrow.x = x;
		arrow.scaleX = scaleX;
		arrow.filters = [new DropShadowFilter(3, 90, 0, 0.25, 2, 2, 1, 1)];
		addChild(arrow);
	}

	private static function hatChannels(id:Int):RigPartChannels {
		for (variant in CharacterRig.loadClassic().parts.hat.variants) if (variant.id == id) return variant;
		throw 'Character rig has no supported hat $id';
	}
}

package pr2.gameplay;

import openfl.display.Sprite;
import pr2.character.CharacterRig;
import pr2.character.CharacterRig.RigPartChannels;
import pr2.runtime.SvgAsset;

/** Native loose-hat vector with primary and secondary tint channels. */
class HatEffectView extends Sprite {
	public final colorMC:Sprite;
	public final colorMC2:Sprite;
	public final fixedArt:Sprite;
	public final fixedBelowArt:Sprite;
	public final fixedAboveArt:Sprite;
	public final animatedOverlay:Sprite;
	public var currentFrame(default, null):Int = 1;
	public var overlayCurrentFrame(default, null):Int = 1;
	private var overlayFrames:Array<String> = [];

	public function new() {
		super();
		name = "HatGraphic";
		fixedBelowArt = new Sprite();
		fixedBelowArt.name = "staticBelow";
		addChild(fixedBelowArt);
		colorMC = new Sprite();
		colorMC.name = "colorMC";
		addChild(colorMC);
		fixedArt = new Sprite();
		fixedArt.name = "static";
		addChild(fixedArt);
		colorMC2 = new Sprite();
		colorMC2.name = "colorMC2";
		addChild(colorMC2);
		fixedAboveArt = new Sprite();
		fixedAboveArt.name = "staticAbove";
		addChild(fixedAboveArt);
		animatedOverlay = new Sprite();
		animatedOverlay.name = "animatedOverlay";
		addChild(animatedOverlay);
		setHatId(1);
	}

	public function setHatId(frame:Int):Void {
		currentFrame = frame;
		var channels = hatChannels(frame);
		setChannel(colorMC, channels.primary);
		setChannel(fixedArt, channels.fixed);
		setChannel(colorMC2, channels.secondary);
		setChannel(fixedBelowArt, channels.fixedBelow);
		setChannel(fixedAboveArt, channels.fixedAbove);
		overlayFrames = channels.overlayAnimation == null ? [] : channels.overlayAnimation.frames.copy();
		overlayCurrentFrame = 1;
		renderOverlayFrame();
	}

	public function advanceOneFrame():Void {
		if (overlayFrames.length == 0) return;
		overlayCurrentFrame = overlayCurrentFrame >= overlayFrames.length ? 1 : overlayCurrentFrame + 1;
		renderOverlayFrame();
	}

	private function renderOverlayFrame():Void {
		while (animatedOverlay.numChildren > 0) animatedOverlay.removeChildAt(0);
		if (overlayFrames.length == 0) return;
		var art = SvgAsset.create(overlayFrames[overlayCurrentFrame - 1]);
		art.name = "vectorFrame";
		animatedOverlay.addChild(art);
	}

	private static function setChannel(holder:Sprite, path:Null<String>):Void {
		while (holder.numChildren > 0) holder.removeChildAt(0);
		if (path == null) return;
		var art = SvgAsset.create(path);
		art.name = path;
		holder.addChild(art);
	}

	private static function hatChannels(id:Int):RigPartChannels {
		for (variant in CharacterRig.loadClassic().parts.hat.variants) if (variant.id == id) return variant;
		throw 'Unsupported loose hat frame $id';
	}

	public function dispose():Void {
		if (parent != null) parent.removeChild(this);
	}
}

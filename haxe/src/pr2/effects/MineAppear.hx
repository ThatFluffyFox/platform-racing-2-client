package pr2.effects;

import openfl.display.Sprite;
import openfl.events.Event;
import openfl.utils.Assets;
import pr2.animation.AnimationClock;
import pr2.audio.SoundEffects;

/**
	Authored mine placement effect from `effects.MineAppear`.
**/
class MineAppear extends Sprite {
	public static inline var LIFETIME_FRAMES:Int = 33;
	public static inline var PLACE_FRAMES:Int = 38;
	public static inline var SOUND_PATH:String = "assets/audio/sfx/mine_appear.mp3";

	public var animation(default, null):Null<MineAppearAnimation>;
	private final clock:AnimationClock;
	private var onComplete:Null<Void->Void>;
	private var completed:Bool = false;
	private var framesElapsed:Int = 0;
	private final createdOnSimulationFrame:Int;

	public function new(worldX:Float, worldY:Float, rotationDegrees:Float, cameraX:Float = 0, cameraY:Float = 0, ?onComplete:Void->Void,
			playSound:Bool = true) {
		super();
		x = worldX;
		y = worldY;
		rotation = rotationDegrees;
		this.onComplete = onComplete;
		createdOnSimulationFrame = pr2.runtime.FrameClock.current == null ? -1 : pr2.runtime.FrameClock.current.simulationFrameNumber;
		clock = new AnimationClock();
		animation = new MineAppearAnimation();
		clock.add(animation.playback);
		addChild(animation);
		addEventListener(Event.ENTER_FRAME, tick);

		if (playSound && Assets.exists(SOUND_PATH)) {
			SoundEffects.playGameSound(Assets.getSound(SOUND_PATH), worldX, worldY, cameraX, cameraY);
		}
	}

	private function tick(event:Event):Void {
		if (!pr2.runtime.FrameClock.shouldRunSimulationFrame()) return;
		var frameClock = pr2.runtime.FrameClock.current;
		if (frameClock != null && frameClock.simulationFrameNumber == createdOnSimulationFrame) return;
		clock.advance();
		framesElapsed++;
		if (framesElapsed >= PLACE_FRAMES) {
			remove(true);
		}
	}

	public function remove(runComplete:Bool = false):Void {
		removeEventListener(Event.ENTER_FRAME, tick);
		if (runComplete && !completed && onComplete != null) {
			completed = true;
			onComplete();
		}
		onComplete = null;
		if (animation != null) {
			animation.dispose();
			animation = null;
		}
		clock.dispose();
		if (parent != null) {
			parent.removeChild(this);
		}
	}
}

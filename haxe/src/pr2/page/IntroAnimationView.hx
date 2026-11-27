package pr2.page;

import openfl.display.Sprite;
import openfl.events.Event;
import openfl.media.SoundChannel;
import openfl.media.SoundTransform;
import openfl.utils.Assets;
import pr2.animation.TimelineClip;
import pr2.lobby.account.Settings;

typedef IntroSoundPlayer = String->Float->Null<SoundChannel>;

/** Typed owner for the supported semantic Lottie intro timelines. */
class IntroAnimationView extends Sprite {
	public var currentFrame(get, never):Int;
	public var totalFrames(get, never):Int;
	public final logoHolder:Sprite;
	public final timeline:TimelineClip;
	private var soundChannel:Null<SoundChannel>;
	#if ios
	private static inline var JIGGMIN_SOUND = "assets/audio/ios/logo_theme.wav";
	#else
	private static inline var JIGGMIN_SOUND = "assets/audio/sfx/logo_theme.mp3";
	#end
	private final playSound:IntroSoundPlayer;
	/** When the theme's cue fired while the browser was still blocking sound. */
	private var lockedCueMs:Float = -1;

	public function new(kind:String, ?playSound:IntroSoundPlayer) {
		super();
		if (kind != "jiggmin" && kind != "kongregate") throw 'Unsupported intro $kind';
		this.playSound = playSound == null ? playAssetSound : playSound;
		name = kind + "Intro";
		timeline = new TimelineClip('assets/intro/$kind.lottie.json');
		timeline.markerHandler = onMarker;
		addChild(timeline);
		var attachment = timeline.attachment("logo_mc");
		if (attachment != null) {
			logoHolder = attachment;
		} else {
			logoHolder = new Sprite();
			addChild(logoHolder);
		}
		timeline.addEventListener(Event.COMPLETE, onComplete);
		timeline.emitCurrentMarkers();
	}

	public function stop():Void timeline.stop();

	public function dispose():Void {
		stopWaitingForAudio();
		timeline.removeEventListener(Event.COMPLETE, onComplete);
		timeline.markerHandler = null;
		timeline.dispose();
		if (soundChannel != null) soundChannel.stop();
		soundChannel = null;
		if (parent != null) parent.removeChild(this);
	}

	private function onComplete(_:Event):Void {
		dispatchEvent(new Event(Event.COMPLETE));
	}

	private function onMarker(marker:String):Void {
		if (marker != "sound:logo_theme") return;
		if (soundChannel != null) soundChannel.stop();
		#if (js && html5)
		// Browsers block sound until the player first clicks or presses a key,
		// and the intro starts before that. Flash had no such rule, so when sound
		// is still blocked, start the theme as soon as it is allowed, at the point
		// the intro has reached.
		if (audioBlocked()) {
			lockedCueMs = haxe.Timer.stamp() * 1000;
			addEventListener(Event.ENTER_FRAME, checkAudioUnblocked);
			return;
		}
		#end
		soundChannel = playSound(JIGGMIN_SOUND, Settings.soundLevel / 100);
	}

	private function checkAudioUnblocked(_:Event):Void {
		#if (js && html5)
		if (audioBlocked()) return;
		var elapsed = haxe.Timer.stamp() * 1000 - lockedCueMs;
		stopWaitingForAudio();
		var volume = Settings.soundLevel / 100;
		if (volume <= 0 || !Assets.exists(JIGGMIN_SOUND)) return;
		var sound = Assets.getSound(JIGGMIN_SOUND);
		if (sound == null || elapsed >= sound.length) return;
		soundChannel = sound.play(elapsed, 0, new SoundTransform(volume));
		#end
	}

	private function stopWaitingForAudio():Void {
		lockedCueMs = -1;
		removeEventListener(Event.ENTER_FRAME, checkAudioUnblocked);
	}

	#if (js && html5)
	private static function audioBlocked():Bool {
		return js.Syntax.code("(typeof Howler !== 'undefined' && Howler.ctx != null && Howler.ctx.state !== 'running')");
	}
	#end

	private static function playAssetSound(path:String, volume:Float):Null<SoundChannel> {
		if (volume <= 0) return null;
		if (!Assets.exists(path)) throw 'Missing intro sound asset $path';
		var sound = Assets.getSound(path);
		if (sound == null) throw 'Unable to decode intro sound asset $path';
		return sound.play(0, 0, new SoundTransform(volume));
	}

	private inline function get_currentFrame():Int return timeline.currentFrame;
	private inline function get_totalFrames():Int return timeline.totalFrames;
}

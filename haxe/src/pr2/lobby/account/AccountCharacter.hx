package pr2.lobby.account;

import openfl.display.Sprite;
import pr2.character.CharacterView;

/**
	Editable customize-preview character, the slice of Flash `character.Character`
	the Account tab drives: a single visible hat plus head/body/feet, each with a
	primary colour and an optional epic (secondary) colour. Wraps the shared
	`CharacterView` and re-applies appearance on every change, exactly like the
	original `applyAppearance` round-trip.

	`-1` for an epic colour means the part is not epic (no second colour); the
	preview then hides that part's secondary tint.
**/
class AccountCharacter extends Sprite {
	/** Authored transform retained by CharacterGraphic's state children. */
	public static inline final INTERNAL_GRAPHIC_SCALE:Float = 0.15;

	public var hat1:Int;
	public var head:Int;
	public var body:Int;
	public var feet:Int;

	public var hat1Color:Int = 0;
	public var headColor:Int = 0;
	public var bodyColor:Int = 0;
	public var feetColor:Int = 0;

	public var hat1Color2:Int = -1;
	public var headColor2:Int = -1;
	public var bodyColor2:Int = -1;
	public var feetColor2:Int = -1;

	public final display:CharacterView;

	/** Flash `DjinnEffects`: frost particles for Frost Djinn bodies and feet (id 35). */
	private var djinnEmitters:Array<pr2.character.ParticleEmitter> = [];
	private var djinnAlpha:Float = 0.5;

	public function new(hatId:Int = 1, headId:Int = 1, bodyId:Int = 1, feetId:Int = 1) {
		super();
		this.hat1 = hatId;
		this.head = headId;
		this.body = bodyId;
		this.feet = feetId;
		display = new CharacterView(0, -1, null, "stand", {head: headId, body: bodyId, feet: feetId}, [hatId, 1, 1, 1]);
		// The neutral rig retains the authored ~0.15 root matrix, so the wrapper
		// remains at scale 1 exactly like Flash's Character instance.
		addChild(display);
		// Previews show one character, so draw its parts as vectors like Flash.
		// The race-time part bitmap cache resamples each part through its
		// rotated slot every frame, which softens outlines visibly at this size.
		display.setPartBitmapCacheEnabled(false);
		// Flash's customize/account preview is a live Character MovieClip, so the
		// standing idle plays continuously. Drive it from the stage clock; the
		// listener is released automatically when the preview is detached.
		display.enableIdleAnimation();
		addEventListener(openfl.events.Event.ADDED_TO_STAGE, function(_):Void updateDjinnEffects());
		addEventListener(openfl.events.Event.REMOVED_FROM_STAGE, function(_):Void clearDjinnEffects());
	}

	/** Flash `Character.djinnUpdateAlpha`: fades the frost particles (unowned previews use 0.1). */
	public function djinnUpdateAlpha(newAlpha:Float):Void {
		djinnAlpha = newAlpha;
		updateDjinnEffects();
	}

	private function updateDjinnEffects():Void {
		clearDjinnEffects();
		if (parent == null || stage == null) return;
		if (body == 35) {
			addDjinnEmitter("body", bodyColor, bodyColor2, 16, null, null, 2, 3, 1.05, 0.9, -10, 10, -1, -0.75, -15, -10);
		}
		if (feet == 35) {
			addDjinnEmitter("frontFoot", feetColor, feetColor2, 8, -2, 2, null, null, null, null, -5, 5, 0.075, 0.1, 0, 0);
			addDjinnEmitter("backFoot", feetColor, feetColor2, 8, -2, 2, null, null, null, null, -5, 5, 0.075, 0.1, 0, 0);
		}
	}

	private function addDjinnEmitter(slotName:String, color:Int, color2:Int, life:Int, minVelX:Null<Float>, maxVelX:Null<Float>, minVelY:Null<Float>,
			maxVelY:Null<Float>, fricX:Null<Float>, fricY:Null<Float>, minOffsetY:Float, maxOffsetY:Float, minScale:Float, maxScale:Float, offsetX:Float,
			offsetY:Float):Void {
		var target = display.effectTarget(slotName);
		if (target == null) return;
		djinnEmitters.push(new pr2.character.PositionedParticleEmitter(75, 999999999, target, parent, {
			graphic: "DjinnIceGraphic", colors: [color, color2], life: life, startAlpha: djinnAlpha / 5, minVelAlpha: 0, maxVelAlpha: djinnAlpha,
			minVelX: minVelX, maxVelX: maxVelX, minVelY: minVelY, maxVelY: maxVelY, velScaleX: 0.1, velScaleY: 0.1, fricX: fricX, fricY: fricY,
			minOffsetX: -5, maxOffsetX: 5, minOffsetY: minOffsetY, maxOffsetY: maxOffsetY, minScale: minScale, maxScale: maxScale
		}, offsetX, offsetY));
	}

	private function clearDjinnEffects():Void {
		for (emitter in djinnEmitters) emitter.remove();
		djinnEmitters = [];
	}

	public function setColors(hatColor:Int, hatColor2:Int, headColor:Int, headColor2:Int, bodyColor:Int, bodyColor2:Int, feetColor:Int,
			feetColor2:Int):Void {
		this.hat1Color = hatColor;
		this.hat1Color2 = hatColor2;
		this.headColor = headColor;
		this.headColor2 = headColor2;
		this.bodyColor = bodyColor;
		this.bodyColor2 = bodyColor2;
		this.feetColor = feetColor;
		this.feetColor2 = feetColor2;
		applyAppearance();
	}

	public function setHatId(id:Int):Void {
		hat1 = id;
		applyAppearance();
	}

	public function setHeadId(id:Int):Void {
		head = id;
		applyAppearance();
	}

	public function setBodyId(id:Int):Void {
		body = id;
		applyAppearance();
	}

	public function setFeetId(id:Int):Void {
		feet = id;
		applyAppearance();
	}

	public function setHatColors(color:Int, epic:Int):Void {
		hat1Color = color;
		hat1Color2 = epic;
		applyAppearance();
	}

	public function setHeadColors(color:Int, epic:Int):Void {
		headColor = color;
		headColor2 = epic;
		applyAppearance();
	}

	public function setBodyColors(color:Int, epic:Int):Void {
		bodyColor = color;
		bodyColor2 = epic;
		applyAppearance();
	}

	public function setFeetColors(color:Int, epic:Int):Void {
		feetColor = color;
		feetColor2 = epic;
		applyAppearance();
	}

	private function applyAppearance():Void {
		display.setAppearance({head: head, body: body, feet: feet}, {
			head: {primary: headColor, secondary: headColor2},
			body: {primary: bodyColor, secondary: bodyColor2},
			feet: {primary: feetColor, secondary: feetColor2}
		});
		display.setHatIds([hat1, 1, 1, 1]);
		updateDjinnEffects();
		display.setHatSlotColors([
			{primary: hat1Color, secondary: hat1Color2},
			{primary: 0, secondary: -1},
			{primary: 0, secondary: -1},
			{primary: 0, secondary: -1}
		]);
	}

	/**
		Serialised customize payload used by `set_customize_info`, matching the
		original field order:
		`hat1Color`headColor`bodyColor`feetColor`hat1Color2`headColor2`bodyColor2`feetColor2`hat`head`body`feet`.
	**/
	public function getPartInfoStr():String {
		return hat1Color
			+ "`" + headColor
			+ "`" + bodyColor
			+ "`" + feetColor
			+ "`" + hat1Color2
			+ "`" + headColor2
			+ "`" + bodyColor2
			+ "`" + feetColor2
			+ "`" + hat1
			+ "`" + head
			+ "`" + body
			+ "`" + feet;
	}

	public function remove():Void {
		clearDjinnEffects();
		if (display.parent == this) {
			removeChild(display);
		}
		if (parent != null) {
			parent.removeChild(this);
		}
	}
}

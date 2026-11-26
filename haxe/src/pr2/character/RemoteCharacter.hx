package pr2.character;

import openfl.display.Sprite;
import openfl.events.Event;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import pr2.gameplay.MiniMapDot;
import pr2.gameplay.RotationMath;
import pr2.gameplay.presentation.CharacterPresentationLayer;
import pr2.gameplay.presentation.PresentationPose;
import pr2.net.CommandHandler;
import pr2.runtime.FontResolver;
import pr2.runtime.FrameClock;

typedef RemoteCharacterPoint = {
	var x:Float;
	var y:Float;
}

/**
	Network-driven character ported from `flash/character/RemoteCharacter.as`.

	This covers the B4 consume/interpolation core: tempID-scoped command
	registration, queued `p` / `var` / `exactPos` updates, Flash's catch-up model,
	minimap-dot position updates, remote block-touch probes, and command teardown.
	The visual side-effects for jet/sting/heart are still delegated through hooks
	until the live race shell owns those systems.
**/
class RemoteCharacter extends Character {
	private static inline var MAX_PRESENTATION_DELTA:Float = 60;
	public var mapDot(default, null):Null<MiniMapDot>;
	public var mapRotation:Float = 0;
	public var catchupRate(default, null):Float = 1;
	public var posX(default, null):Float = 0;
	public var posY(default, null):Float = 0;
	public var lastX(default, null):Float = 0;
	public var lastY(default, null):Float = 0;
	public var remoteRotation(default, null):Int = 0;
	public var rotMod(default, null):Int = 0;
	public var updateQueueLength(get, never):Int;

	public var onParentChange:Null<String->Void> = null;
	public var onSparklesChange:Null<Bool->Void> = null;
	public var onJetChange:Null<Bool->Void> = null;
	public var onHeartGain:Null<Void->Void> = null;
	public var onSting:Null<Array<String>->Void> = null;
	public var onBlockTouch:Null<Int->Int->Void> = null;

	private var updateQueue:Array<Dynamic> = [];
	private var commandHandler:Null<CommandHandler>;
	private final presentationPose:PresentationPose = new PresentationPose();
	private var presentationLayer:CharacterPresentationLayer = CharacterPresentationLayer.Front;
	private var presentationDiscontinuityPending:Bool = true;
	private var externalPresentationSnapPending:Bool = false;
	private var mapRotationSource:Null<Void->Float> = null;
	/** Flash CharacterGraphic.nameHolder (Symbol 893): the name above the head. */
	private var nameHolder:Null<Sprite>;

	public function new(tempId:Int, ?dot:MiniMapDot, userName:String = "", hatId:Int = 1, headId:Int = 1, bodyId:Int = 1, feetId:Int = 1,
			groupStr:String = "0", ?handler:CommandHandler) {
		super(hatId, headId, bodyId, feetId);
		this.tempID = tempId;
		this.mapDot = dot;
		if (mapDot != null) {
			mapDot.setTempID(tempID);
		}
		this.groupStr = groupStr;
		this.userName = userName;
		buildNameHolder(userName);
		this.catchupRate = updateInterval + 1;
		commandHandler = handler != null ? handler : CommandHandler.commandHandler;
		registerCommands();
		addEventListener(Event.ENTER_FRAME, onEnterFrame);
	}

	public function stepFrame():Void {
		stepSimulationFrame(null);
	}

	/**
		Flash reads `map.rotation` on every remote-character frame. Live courses bind
		that value here so players remain in the same world position when the viewer
		and sender have committed different rotate-block orientations.
	**/
	public function bindMapRotation(source:Void->Float):Void {
		mapRotationSource = source;
		mapRotation = source();
	}

	public function pos(args:Array<String>):Void {
		var delta:RemoteCharacterPoint = args.length > 0 && args[0] == "" ? {x: 0, y: 0} : {x: parseFloatArg(args, 0), y: parseFloatArg(args, 1)};
		var i = 1;
		while (i < updateInterval) {
			updateQueue.push({});
			i++;
		}
		var update:Dynamic = {};
		Reflect.setField(update, "pos", delta);
		updateQueue.push(update);
	}

	public function setVar(args:Array<String>):Void {
		if (args.length < 2) {
			return;
		}
		var field = args[0];
		var value = args[1];
		if (updateQueue.length > 0) {
			var last:Dynamic = updateQueue[updateQueue.length - 1];
			if (Reflect.field(last, field) != null && updateQueue.length >= 2) {
				Reflect.setField(updateQueue[updateQueue.length - 2], field, Reflect.field(last, field));
			}
			Reflect.setField(last, field, value);
		} else {
			var update:Dynamic = {};
			Reflect.setField(update, field, value);
			updateQueue.push(update);
		}
	}

	public function setExactPos(args:Array<String>):Void {
		if (updateQueue.length == 0) {
			return;
		}
		Reflect.setField(updateQueue[updateQueue.length - 1], "x", parseIntArg(args, 0));
		Reflect.setField(updateQueue[updateQueue.length - 1], "y", parseIntArg(args, 1));
	}

	override public function setPos(px:Float, py:Float):Void {
		super.setPos(px, py);
		posX = px;
		posY = py;
		updateSegs(mapRotation);
		invalidatePresentationPose();
	}

	public function setScaleX(value:Float):Void {
		// Flash flips nameHolder with the character so the name stays readable.
		scaleX = value;
		if (nameHolder != null) {
			nameHolder.scaleX = value;
		}
	}

	/**
		Flash RemoteCharacter sets nameHolder.nameBox and nameBox2 to the user
		name and colours nameBox like the player's minimap dot. Symbol 893 puts
		the coloured nameBox one pixel up-right of a black nameBox2 shadow; the
		holder sits 84.25 px above the character at 25% alpha.
	**/
	private function buildNameHolder(name:String):Void {
		nameHolder = new Sprite();
		nameHolder.name = "nameHolder";
		nameHolder.y = -84.25;
		nameHolder.alpha = 0.25;
		nameHolder.mouseEnabled = false;
		nameHolder.mouseChildren = false;
		nameHolder.addChild(nameField("nameBox2", name, -50, 3, 0x000000));
		nameHolder.addChild(nameField("nameBox", name, -49, 2, MiniMapDot.colorForTempId(tempID)));
		display.addChild(nameHolder);
	}

	private static function nameField(fieldName:String, text:String, x:Float, y:Float, color:Int):TextField {
		var field = new TextField();
		field.name = fieldName;
		field.x = x;
		field.y = y;
		field.width = 100;
		field.height = 14.55;
		field.selectable = false;
		field.mouseEnabled = false;
		var format = new TextFormat(FontResolver.resolve("Verdana"), 12, color);
		format.align = TextFormatAlign.CENTER;
		field.defaultTextFormat = format;
		field.text = text;
		return field;
	}

	public function setScaleY(_:Float):Void {}

	public function setPresentationLayer(parentLayer:String):Void {
		var next = parentLayer == "backBackground" ? CharacterPresentationLayer.Back : CharacterPresentationLayer.Front;
		if (next == presentationLayer) return;
		presentationLayer = next;
		requestPresentationSnap();
	}

	public function requestPresentationSnap():Void {
		externalPresentationSnapPending = true;
		presentationPose.markDiscontinuity();
		snapPresentationToAuthoritative();
	}

	public function heart(_:Array<String>):Void {
		gainHeart();
		if (onHeartGain != null) {
			onHeartGain();
		}
	}

	public function sting(args:Array<String>):Void {
		if (onSting != null) {
			onSting(args);
		}
	}

	override public function remove():Void {
		removeEventListener(Event.ENTER_FRAME, onEnterFrame);
		unregisterCommands();
		commandHandler = null;
		mapRotationSource = null;
		updateQueue = [];
		presentationPose.clear();
		if (mapDot != null) {
			mapDot.remove();
			mapDot = null;
		}
		super.remove();
	}

	private function onEnterFrame(event:Event):Void {
		if (!FrameClock.shouldRunSimulationFrame()) {
			if (FrameClock.shouldRenderIntermediatePresentationFrame()) renderPresentationFrame();
			return;
		}
		stepSimulationFrame(event);
	}

	private function stepSimulationFrame(event:Null<Event>):Void {
		var beforeX = x;
		var beforeY = y;
		presentationPose.beginSimulationTick(beforeX, beforeY, rotation, scaleX < 0 ? -1 : 1, presentationLayer);
		go(event, true);
		var deltaX = x - beforeX;
		var deltaY = y - beforeY;
		presentationPose.finishSimulationTick(
			x,
			y,
			rotation,
			scaleX < 0 ? -1 : 1,
			presentationLayer,
			presentationDiscontinuityPending
				|| externalPresentationSnapPending
				|| removed
				|| PresentationPose.movementTooLarge(deltaX, deltaY, MAX_PRESENTATION_DELTA)
		);
		presentationDiscontinuityPending = false;
		snapPresentationToAuthoritative();
	}

	public function renderPresentationFrame():Void {
		if (!presentationPose.hasSamples) return;
		var predictedX = RemotePresentationPolicy.guardedExtrapolation(
			presentationPose.previousX,
			presentationPose.currentX,
			presentationPose.discontinuity
		);
		var predictedY = RemotePresentationPolicy.guardedExtrapolation(
			presentationPose.previousY,
			presentationPose.currentY,
			presentationPose.discontinuity
		);
		var predictedRotation = RemotePresentationPolicy.guardedExtrapolation(
			presentationPose.previousRotation,
			presentationPose.currentRotation,
			presentationPose.discontinuity
		);
		var worldOffsetX = predictedX - presentationPose.currentX;
		var worldOffsetY = predictedY - presentationPose.currentY;
		var radians = -presentationPose.currentRotation * Math.PI / 180;
		var cos = Math.cos(radians);
		var sin = Math.sin(radians);
		var localScaleX = scaleX == 0 ? 1 : scaleX;
		display.x = (worldOffsetX * cos - worldOffsetY * sin) / localScaleX;
		display.y = worldOffsetX * sin + worldOffsetY * cos;
		display.rotation = predictedRotation - presentationPose.currentRotation;
		setPresentationWorldOffset(worldOffsetX, worldOffsetY);
		externalPresentationSnapPending = false;
	}

	private function invalidatePresentationPose():Void {
		presentationDiscontinuityPending = true;
		externalPresentationSnapPending = true;
		presentationPose.clear();
		snapPresentationToAuthoritative();
	}

	private function snapPresentationToAuthoritative():Void {
		display.x = 0;
		display.y = 0;
		display.rotation = 0;
		clearPresentationWorldOffset();
	}

	private function go(_:Event, advanceAnimation:Bool):Void {
		if (mapRotationSource != null) {
			mapRotation = mapRotationSource();
		}
		if (updateQueue.length > 0) {
			catchupRate -= 0.01;
			var i = 0;
			while (i < updateQueue.length) {
				var queuedPos:Null<RemoteCharacterPoint> = cast Reflect.field(updateQueue[i], "pos");
				if (queuedPos != null) {
					var dx = queuedPos.x / (i + 1);
					var dy = queuedPos.y / (i + 1);
					posX += dx;
					posY += dy;
					queuedPos.x -= dx;
					queuedPos.y -= dy;
					break;
				}
				i++;
			}
			var rotated = RotationMath.rotatePoint(posX, posY, -(mapRotation + remoteRotation));
			velX = lastX - x;
			velY = lastY - y;
			lastX = x;
			lastY = y;
			x = rotated.x;
			y = rotated.y;
			if (mapDot != null) {
				var dotPoint = RotationMath.rotatePoint(posX, posY, -remoteRotation);
				mapDot.x = dotPoint.x;
				mapDot.y = dotPoint.y;
			}
			updateSegs(mapRotation);
			rotation = mapRotation + remoteRotation + rotMod;
			applyQueuedUpdate(updateQueue.shift());
			if (updateQueue.length > catchupRate) {
				// Flash recursively consumes excess network frames here, but the
				// The neutral character rig still advances only once per stage frame.
				go(null, false);
			}
		} else {
			catchupRate += 0.08;
		}
		if (catchupRate > 10) {
			catchupRate = 10;
		}
		processBlockTouches();
		if (advanceAnimation) {
			display.advanceOneFrame();
		}
	}

	private function applyQueuedUpdate(update:Dynamic):Void {
		if (Reflect.field(update, "state") != null) {
			changeState(Std.string(Reflect.field(update, "state")));
		}
		if (Reflect.field(update, "scaleX") != null) {
			setScaleX(parseFloatValue(Reflect.field(update, "scaleX")));
		}
		if (Reflect.field(update, "parent") != null && onParentChange != null) {
			onParentChange(Std.string(Reflect.field(update, "parent")));
		}
		if (Reflect.field(update, "x") != null) {
			posX = parseFloatValue(Reflect.field(update, "x"));
			posY = parseFloatValue(Reflect.field(update, "y"));
		}
		if (Reflect.field(update, "rotMod") != null) {
			rotMod = parseIntValue(Reflect.field(update, "rotMod"));
		}
		if (Reflect.field(update, "rot") != null) {
			remoteRotation = parseIntValue(Reflect.field(update, "rot"));
		}
		if (Reflect.field(update, "item") != null) {
			setItem(parseIntValue(Reflect.field(update, "item")));
		}
		if (Reflect.field(update, "sparkle") != null) {
			var enabled = Std.string(Reflect.field(update, "sparkle")) == "1";
			if (enabled) {
				beginSparkles();
			} else {
				endSparkles();
			}
			if (onSparklesChange != null) {
				onSparklesChange(enabled);
			}
		}
		if (Reflect.field(update, "jet") != null) {
			var enabled = Std.string(Reflect.field(update, "jet")) == "1";
			if (enabled) {
				beginJet();
			} else {
				endJet();
			}
			if (onJetChange != null) {
				onJetChange(enabled);
			}
		}
		if (Reflect.field(update, "beginRemove") != null) {
			beginRemove();
		}
	}

	private function processBlockTouches():Void {
		if (onBlockTouch == null) {
			return;
		}
		var deltaX = posX - lastX;
		var deltaY = posY - lastY;
		for (probe in blockTouchProbes(deltaX, deltaY)) {
			var seg = RotationMath.rotatePoint(probe.x / 30, probe.y / 30, mapRotation);
			onBlockTouch(seg.x, seg.y);
		}
	}

	private function registerCommands():Void {
		if (commandHandler == null) {
			return;
		}
		commandHandler.defineCommand("p" + tempID, pos);
		commandHandler.defineCommand("var" + tempID, setVar);
		commandHandler.defineCommand("exactPos" + tempID, setExactPos);
		commandHandler.defineCommand("setHats" + tempID, setHatsCommand);
		commandHandler.defineCommand("heart" + tempID, heart);
		commandHandler.defineCommand("sting" + tempID, sting);
	}

	private function unregisterCommands():Void {
		if (commandHandler == null) {
			return;
		}
		commandHandler.defineCommand("p" + tempID, null);
		commandHandler.defineCommand("var" + tempID, null);
		commandHandler.defineCommand("exactPos" + tempID, null);
		commandHandler.defineCommand("setHats" + tempID, null);
		commandHandler.defineCommand("heart" + tempID, null);
		commandHandler.defineCommand("sting" + tempID, null);
	}

	private function setHatsCommand(args:Array<String>):Void {
		// A no-hat server frame ends immediately after the command delimiter, so
		// splitting it produces `[""]`. Treat that as an empty hat stack instead
		// of parsing the blank field as frame 0.
		if (args.length == 1 && args[0] == "") {
			setHats([]);
			return;
		}
		setHats([for (arg in args) Std.parseInt(arg)]);
	}

	private function get_updateQueueLength():Int {
		return updateQueue.length;
	}

	private static function parseFloatArg(args:Array<String>, index:Int):Float {
		return index < args.length ? parseFloatValue(args[index]) : 0;
	}

	private static function parseIntArg(args:Array<String>, index:Int):Int {
		return index < args.length ? parseIntValue(args[index]) : 0;
	}

	private static function parseFloatValue(value:Dynamic):Float {
		var parsed = Std.parseFloat(Std.string(value));
		return Math.isNaN(parsed) ? 0 : parsed;
	}

	private static function parseIntValue(value:Dynamic):Int {
		var parsed = Std.parseInt(Std.string(value));
		return parsed == null ? 0 : parsed;
	}
}

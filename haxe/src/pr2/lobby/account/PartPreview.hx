package pr2.lobby.account;

import openfl.display.DisplayObject;
import openfl.display.Sprite;
import openfl.geom.Matrix;

/** Live character-backed preview for a single catalog part. */
class PartPreview extends Sprite {
	public final character:AccountCharacter;
	/** What EpicFlash recolours: the part's colorMC2 channel once `showEpic` runs. */
	public var epicTarget(default, null):DisplayObject;
	public var secondaryVisible(default, null):Bool;
	private final partType:String;
	private var singleFoot:Bool = false;

	public function new(type:String, id:Int, owned:Bool) {
		super();
		name = "partPreview";
		partType = type;
		var hat = type == "HAT" ? id : 1;
		var head = type == "HEAD" ? id : 1;
		var body = type == "BODY" ? id : 1;
		var feet = type == "FEET" ? id : 1;
		character = new AccountCharacter(hat, head, body, feet);
		character.setColors(0x6C91C2, -1, 0xD2A779, -1, 0x7399C8, -1, 0x545E70, -1);
		epicTarget = character;
		secondaryVisible = type == "HAT" && id == 16;
		if (secondaryVisible) character.setHatColors(0xD3B13B, 0xF2DE79);
		// Flash stops the part clip on its frame (no idle) in its authored colours.
		character.display.showAsPartPreview();
		// Isolate last: re-applying the appearance (the cheese hat's colours
		// above) shows every part again.
		isolatePart(type);
		addChild(character);
		alpha = owned ? 1 : 0.1;
	}

	private function isolatePart(type:String):Void {
		var rigRoot = Std.downcast(character.display.getChildByName("rigRoot"), Sprite);
		if (rigRoot == null) return;
		var selected = type.toLowerCase();
		for (index in 0...rigRoot.numChildren) {
			var slot = rigRoot.getChildAt(index);
			slot.visible = slot.name == selected
				|| (selected == "hat" && slot.name == "head")
				|| (selected == "feet" && (slot.name == "frontFoot" || (slot.name == "backFoot" && !singleFoot)));
		}
		if (selected == "hat") {
			var head = Std.downcast(rigRoot.getChildByName("head"), Sprite);
			if (head != null) {
				var artwork = head.getChildByName("artwork");
				if (artwork != null) artwork.visible = false;
			}
		} else if (selected == "head") {
			character.display.hatSocket.visible = false;
		}
	}

	/**
		Place the preview so the part's rig node (Flash's hatsMC, headsMC, bodyMC
		or footMC) sits at `authored`, the matrix of that clip in the Flash popup.
		Flash shows a single foot, so the back foot is hidden.
	**/
	public function placePart(type:String, authored:Matrix):Void {
		var rigRoot = Std.downcast(character.display.getChildByName("rigRoot"), Sprite);
		if (rigRoot == null) return;
		var anchor:Null<DisplayObject> = partArtwork(type);
		if (anchor == null) return;
		if (type == "FEET") {
			singleFoot = true;
			var backFoot = rigRoot.getChildByName("backFoot");
			if (backFoot != null) backFoot.visible = false;
		}
		// The rig centres each part's artwork; Flash's part clip (headsMC, bodyMC,
		// footMC) draws it offset by the part's registration (hats have none).
		@:privateAccess var parts = character.display.rig.parts;
		var registration = switch (type) {
			case "HEAD": parts.head.registration;
			case "BODY": parts.body.registration;
			case "FEET": parts.feet.registration;
			default: {x: 0.0, y: 0.0};
		};
		var partClip = new Matrix(1, 0, 0, 1, registration.x, registration.y);
		partClip.concat(authored);
		var placement = new Matrix();
		var node:Null<DisplayObject> = anchor;
		while (node != null && node != this) {
			placement.concat(node.transform.matrix);
			node = node.parent;
		}
		placement.invert();
		placement.concat(partClip);
		transform.matrix = placement;
	}

	/**
		Flash shows the part's colorMC2 and flashes only that channel. Recolouring
		the whole preview painted the epic colour over the entire part.
	**/
	public function showEpic():Void {
		secondaryVisible = true;
		switch (partType) {
			case "HAT": character.setHatColors(character.hat1Color, 0xFFFFFF);
			case "HEAD": character.setHeadColors(character.headColor, 0xFFFFFF);
			case "BODY": character.setBodyColors(character.bodyColor, 0xFFFFFF);
			case "FEET": character.setFeetColors(character.feetColor, 0xFFFFFF);
			default:
		}
		isolatePart(partType);
		var artwork = partArtwork(partType);
		var secondary = artwork == null ? null : artwork.getChildByName("secondary");
		if (secondary != null) epicTarget = secondary;
	}

	private function partArtwork(type:String):Null<openfl.display.DisplayObjectContainer> {
		var rigRoot = Std.downcast(character.display.getChildByName("rigRoot"), Sprite);
		if (rigRoot == null) return null;
		var slot:Null<DisplayObject> = switch (type) {
			case "HAT": character.display.hatSocket.getChildByName("hat1");
			case "HEAD": rigRoot.getChildByName("head");
			case "BODY": rigRoot.getChildByName("body");
			case "FEET": rigRoot.getChildByName("frontFoot");
			default: null;
		};
		var container = Std.downcast(slot, openfl.display.DisplayObjectContainer);
		return container == null ? null : Std.downcast(container.getChildByName("artwork"), openfl.display.DisplayObjectContainer);
	}

	public function remove():Void {
		character.remove();
		if (parent != null) parent.removeChild(this);
	}
}

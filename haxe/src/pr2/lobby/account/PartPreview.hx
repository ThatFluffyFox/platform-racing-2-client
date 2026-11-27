package pr2.lobby.account;

import openfl.display.DisplayObject;
import openfl.display.Sprite;
import openfl.geom.Matrix;

/** Live character-backed preview for a single catalog part. */
class PartPreview extends Sprite {
	public final character:AccountCharacter;
	public final epicTarget:Sprite;
	public var secondaryVisible(default, null):Bool;

	public function new(type:String, id:Int, owned:Bool) {
		super();
		name = "partPreview";
		var hat = type == "HAT" ? id : 1;
		var head = type == "HEAD" ? id : 1;
		var body = type == "BODY" ? id : 1;
		var feet = type == "FEET" ? id : 1;
		character = new AccountCharacter(hat, head, body, feet);
		character.setColors(0x6C91C2, -1, 0xD2A779, -1, 0x7399C8, -1, 0x545E70, -1);
		isolatePart(type);
		addChild(character);
		// EpicFlash belongs on the authored part artwork. The old compatibility
		// runtime applied its color transform to the preview clip itself; a
		// separately drawn purple ring was never part of the Flash composition.
		epicTarget = character;
		epicTarget.name = "epicTarget";
		secondaryVisible = type == "HAT" && id == 16;
		if (secondaryVisible) character.setHatColors(0xD3B13B, 0xF2DE79);
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
				|| (selected == "feet" && (slot.name == "frontFoot" || slot.name == "backFoot"));
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
		var anchor:Null<DisplayObject> = switch (type) {
			case "HAT": character.display.hatSocket.getChildByName("hat1");
			case "HEAD": rigRoot.getChildByName("head");
			case "BODY": rigRoot.getChildByName("body");
			case "FEET": rigRoot.getChildByName("frontFoot");
			default: null;
		};
		if (anchor == null) return;
		if (type == "FEET") {
			var backFoot = rigRoot.getChildByName("backFoot");
			if (backFoot != null) backFoot.visible = false;
		}
		var placement = new Matrix();
		var node:Null<DisplayObject> = anchor;
		while (node != null && node != this) {
			placement.concat(node.transform.matrix);
			node = node.parent;
		}
		placement.invert();
		placement.concat(authored);
		transform.matrix = placement;
	}

	public function showEpic():Void {
		secondaryVisible = true;
	}

	public function remove():Void {
		character.remove();
		if (parent != null) parent.removeChild(this);
	}
}

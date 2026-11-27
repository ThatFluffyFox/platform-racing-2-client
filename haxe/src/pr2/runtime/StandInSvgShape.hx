package pr2.runtime;

import openfl.display.DisplayObject;
import openfl.display.Shape;
import openfl.events.Event;

/**
	A part's `static_under_secondary.svg`: black stand-in shapes that the
	secondary (colorMC2) channel covers exactly in Flash. It is drawn only while
	`cover` is hidden, so the anti-aliased edge of the black copy cannot leak
	around the tinted shape. Views that toggle `cover` directly get the matching
	state every frame; call `sync()` to update it immediately.
**/
class StandInSvgShape extends Shape {
	private final cover:DisplayObject;

	public function new(assetPath:String, cover:DisplayObject) {
		super();
		this.cover = cover;
		graphics.copyFrom(SvgAsset.create(assetPath).graphics);
		addEventListener(Event.ENTER_FRAME, enteredFrame);
		sync();
	}

	public function sync():Void {
		visible = !cover.visible;
	}

	private function enteredFrame(_:Event):Void {
		sync();
	}

	/** Adds the stand-in for `asset` directly under `cover`; nothing when the part has none. */
	public static function addUnder(asset:Null<String>, cover:DisplayObject, name:String):Null<StandInSvgShape> {
		if (asset == null || cover.parent == null) return null;
		var shape = new StandInSvgShape(asset, cover);
		shape.name = name;
		shape.x = cover.x;
		shape.y = cover.y;
		cover.parent.addChildAt(shape, cover.parent.getChildIndex(cover));
		return shape;
	}
}

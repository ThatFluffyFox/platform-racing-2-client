package pr2.gameplay;

import openfl.display.Sprite;
import openfl.events.Event;
import pr2.runtime.HairlineScale;

/**
	A minimap marker square with Flash's pixel-hinted hairline outline: the
	player dots (`MiniMapDot`) and the finish boxes (`MiniMapFinishGraphic`).

	Flash draws a hairline one device pixel wide at any scale. OpenFL scales
	strokes with the marker, the minimap and the stage display scale, which left
	a thick, blurred outline, so the outline is redrawn at one device pixel when
	the marker is resized or the stage resizes.
**/
class MiniMapMarker extends Sprite {
	/** Authored width/height of the marker square, excluding its hairline. */
	public static inline var AUTHORED_SIZE:Float = 4;

	private var fillColor:Int;
	private final outlineColor:Int;
	private final left:Float;
	private final top:Float;

	public function new(fillColor:Int, outlineColor:Int, left:Float, top:Float) {
		super();
		this.fillColor = fillColor;
		this.outlineColor = outlineColor;
		this.left = left;
		this.top = top;
		drawMarker();
		addEventListener(Event.ADDED_TO_STAGE, addedToStage);
		addEventListener(Event.REMOVED_FROM_STAGE, removedFromStage);
	}

	/**
		Size the marker so its square is `pixels` stage pixels across under a
		parent drawn at `parentScale`, like Flash's `width = height = 4 / scale`.
		Flash measures the zero-width hairline as adding nothing, so this sets the
		scale directly instead of `width`, which OpenFL measures with the stroke.
	**/
	public function fitTo(pixels:Float, parentScale:Float):Void {
		scaleX = scaleY = pixels / (AUTHORED_SIZE * parentScale);
		drawMarker();
	}

	private function setFillColor(color:Int):Void {
		fillColor = color;
		drawMarker();
	}

	private function addedToStage(_event:Event):Void {
		stage.addEventListener(Event.RESIZE, stageResized);
		drawMarker();
	}

	private function removedFromStage(_event:Event):Void {
		if (stage != null) stage.removeEventListener(Event.RESIZE, stageResized);
	}

	private function stageResized(_event:Event):Void {
		drawMarker();
	}

	private function drawMarker():Void {
		graphics.clear();
		graphics.lineStyle(hairlineThickness(), outlineColor, 1, true);
		graphics.beginFill(fillColor);
		graphics.drawRect(left, top, AUTHORED_SIZE, AUTHORED_SIZE);
		graphics.endFill();
	}

	private function hairlineThickness():Float {
		var deviceThickness = HairlineScale.current(stage);
		if (deviceThickness <= 0) return 0;
		var matrix = transform.concatenatedMatrix;
		var scale = Math.sqrt(Math.abs(matrix.a * matrix.d - matrix.b * matrix.c));
		return scale > 0 ? deviceThickness / scale : deviceThickness;
	}
}

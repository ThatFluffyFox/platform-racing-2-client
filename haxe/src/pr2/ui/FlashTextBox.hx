package pr2.ui;

import openfl.text.TextField;

/**
	Places a TextField from its Animate (XFL) text box the way Flash compiled it.

	The XFL records a text field's box as the area inside its 2px text gutter.
	The published SWF's field bounds add that gutter on every side, so a Flash
	TextField starts 2px up-left of the XFL box and is 4px wider and taller,
	and its text is laid out 2px inside those bounds. OpenFL also lays text out
	2px inside the field, so giving it the XFL box drew every line of text 2px
	low and right and wrapped it 4px too narrow (checked against the SWF's
	DefineEditText bounds for every field in the race HUD, lobby, popups and
	level editor).
**/
class FlashTextBox {
	public static inline var GUTTER:Float = 2;

	/** Sets `field`'s rectangle from the XFL text box at (x, y) sized width x height. */
	public static function applyXflBox(field:TextField, x:Float, y:Float, width:Float, height:Float):TextField {
		field.x = x - GUTTER;
		field.y = y - GUTTER;
		field.width = width + GUTTER * 2;
		field.height = height + GUTTER * 2;
		return field;
	}
}

package pr2.levelEditor;

import openfl.events.Event;
import pr2.lobby.account.ColorPicker;
import pr2.ui.StageFocus;

class EditorBackgroundColorPickerButton extends EditorSideBarEntry {
	private final picker:ColorPicker;

	public function new(title:String = "", desc:String = "") {
		super("color", title, desc);
		picker = new ColorPicker();
		picker.name = "colorPicker";
		picker.direction = ColorPicker.LEFT;
		picker.width = 30;
		picker.height = 30;
		// Flash's BackgroundColorPickerButton applies the colour on CLOSE only.
		// Committing every live preview recoloured the editor under the open
		// popup and kept its eyedropper from working.
		picker.addEventListener(Event.CLOSE, closeCommitColor);
		addChild(picker);
		updateColor();
	}

	public function updateColor():Void {
		var editor = LevelEditor.editor;
		if (editor != null) {
			picker.setColor(editor.color);
		}
	}

	public function setPickedColor(color:Int):Void {
		picker.setColor(color);
		commitColor();
	}

	public function pickerColor():Int {
		return picker.getColor();
	}

	override public function remove():Void {
		picker.removeEventListener(Event.CLOSE, closeCommitColor);
		picker.remove();
		super.remove();
	}

	private function commitColor():Void {
		var editor = LevelEditor.editor;
		if (editor != null) {
			editor.setColor(picker.getColor());
		}
	}

	private function closeCommitColor(?_):Void {
		commitColor();
		StageFocus.reset();
	}
}

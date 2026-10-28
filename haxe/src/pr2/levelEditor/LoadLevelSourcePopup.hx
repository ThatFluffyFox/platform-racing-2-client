package pr2.levelEditor;

import pr2.lobby.dialogs.Popup;
import pr2.lobby.LobbyArt;
import pr2.lobby.LobbyArt.Binding;
import pr2.util.DisplayUtil;

/**
	Port-only: what the editor's Load button opens. My Levels keeps the Flash
	flow (moderators still get the Level Reports / My Levels chooser), Level ID
	loads any level by its ID, and Load from File reads a saved level payload.
**/
class LoadLevelSourcePopup extends Popup {
	public final art:LoadLevelSourceView;
	private final canViewReports:Bool;
	private var bindings:Array<Binding> = [];

	public function new(canViewReports:Bool) {
		super();
		this.canViewReports = canViewReports;
		art = new LoadLevelSourceView();
		addChild(art);
		bind("mine_bt", clickMine);
		bind("id_bt", clickLevelId);
		bind("file_bt", clickFile);
		bind("cancel_bt", function():Void startFadeOut());
	}

	private function clickMine():Void {
		if (canViewReports) {
			new ChooseLevelsModePopup();
		} else {
			new GetLevelsPopup();
		}
		startFadeOut();
	}

	private function clickLevelId():Void {
		new LoadLevelByIdPopup();
		startFadeOut();
	}

	private function clickFile():Void {
		// The browser only opens a file picker from inside the click handler.
		LevelFileImport.browse();
		startFadeOut();
	}

	private function bind(name:String, handler:Void->Void):Void {
		var binding = LobbyArt.bind(DisplayUtil.directChildByName(art, name), handler);
		if (binding != null) {
			bindings.push(binding);
		}
	}

	override public function remove():Void {
		for (binding in bindings) {
			LobbyArt.unbind(binding);
		}
		bindings = [];
		art.dispose();
		super.remove();
	}
}

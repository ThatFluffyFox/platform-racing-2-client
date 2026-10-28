package pr2.levelEditor;

import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import pr2.lobby.dialogs.MessagePopup;
import pr2.lobby.dialogs.Popup;
import pr2.lobby.LobbyArt;
import pr2.lobby.LobbyArt.Binding;
import pr2.lobby.search.SearchQuery;
import pr2.net.LevelListClient;
import pr2.net.LevelListClient.LevelListResult;
import pr2.util.DisplayUtil;

/**
	Port-only: loads any level into the editor by its ID. The level's current
	version comes from the same `search_levels.php` id search the lobby uses;
	the editor then loads it through the normal LoadingLevelPopup path.
**/
class LoadLevelByIdPopup extends Popup {
	public static var searchFactory:Map<String, String>->(LevelListResult->Void)->(String->Void)->Void = defaultSearch;
	public static var loadFactory:Int->Int->Void = defaultLoad;

	public final art:LoadLevelByIdView;
	private var bindings:Array<Binding> = [];
	private var searching:Bool = false;

	public function new() {
		super();
		art = new LoadLevelByIdView();
		addChild(art);
		bind("load_bt", submit);
		bind("cancel_bt", function():Void startFadeOut());
		art.input.textField.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
		if (art.input.textField.stage != null) {
			art.input.textField.stage.focus = art.input.textField;
		}
	}

	/** Parsed level ID, or null when the box doesn't hold a positive whole number. **/
	public static function parseLevelId(text:String):Null<Int> {
		var trimmed = text == null ? "" : StringTools.trim(text);
		if (!~/^[0-9]+$/.match(trimmed)) {
			return null;
		}
		var id = Std.parseInt(trimmed);
		return id == null || id <= 0 ? null : id;
	}

	public function submit():Void {
		if (searching) {
			return;
		}
		var id = parseLevelId(art.input.text);
		if (id == null) {
			new MessagePopup("Error: Enter a level ID (numbers only).");
			return;
		}
		searching = true;
		searchFactory(SearchQuery.buildPost(Std.string(id), "id", "date", "desc", 1), function(result:LevelListResult):Void {
			searching = false;
			for (level in result.levels) {
				if (level.levelId == id) {
					loadFactory(level.levelId, level.version);
					startFadeOut();
					return;
				}
			}
			new MessagePopup('Error: Could not find level $id.');
		}, function(message:String):Void {
			searching = false;
			new MessagePopup("Error: " + (message == null || message == "" ? 'Could not look up level $id.' : message));
		});
	}

	private function onKeyDown(event:KeyboardEvent):Void {
		if (event.keyCode == Keyboard.ENTER) {
			submit();
		}
	}

	private static function defaultSearch(params:Map<String, String>, onResult:LevelListResult->Void, onError:String->Void):Void {
		LevelListClient.search(params, onResult, onError);
	}

	private static function defaultLoad(levelId:Int, version:Int):Void {
		new LoadingLevelPopup(levelId, version);
	}

	private function bind(name:String, handler:Void->Void):Void {
		var binding = LobbyArt.bind(DisplayUtil.directChildByName(art, name), handler);
		if (binding != null) {
			bindings.push(binding);
		}
	}

	override public function remove():Void {
		art.input.textField.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
		for (binding in bindings) {
			LobbyArt.unbind(binding);
		}
		bindings = [];
		art.dispose();
		super.remove();
	}
}

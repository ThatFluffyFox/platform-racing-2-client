package pr2.levelEditor;

import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.net.FileFilter;
import openfl.net.FileReference;
import pr2.lobby.dialogs.MessagePopup;
import pr2.net.LevelDataClient;
import pr2.net.ServerLevelData;

/**
	Port-only "Load from File" for the level editor. Accepts:
	- a level exactly as the server sends it (`level_id=…&data=m4`…` plus the
	  32-character hash), e.g. a file saved by tools/fetch_levels.py;
	- the same vars without the hash;
	- just the block data string (`m4`…`).
	The level loads into the editor like a server level; saving it uploads it
	as the player's own level.
**/
class LevelFileImport {
	private static var file:Null<FileReference>;

	/** Opens the file picker and loads the chosen file into the open editor. **/
	public static function browse():Void {
		var reference = new FileReference();
		file = reference;
		reference.addEventListener(Event.SELECT, function(_):Void {
			reference.load();
		});
		reference.addEventListener(Event.COMPLETE, function(_):Void {
			var bytes = reference.data;
			var text = bytes == null ? "" : bytes.readUTFBytes(bytes.length);
			file = null;
			loadText(text);
		});
		reference.addEventListener(IOErrorEvent.IO_ERROR, function(_):Void {
			file = null;
			new MessagePopup("Error: Could not read that file.");
		});
		try {
			reference.browse([new FileFilter("PR2 level (*.txt)", "*.txt"), new FileFilter("All files", "*.*")]);
		} catch (error:Dynamic) {
			file = null;
			new MessagePopup("Error: Loading from a file is not supported here.");
		}
	}

	/** Parses the file and puts the level in the editor, or explains what was wrong. **/
	public static function loadText(text:String):Void {
		var data = parse(text);
		if (data == null) {
			new MessagePopup("Error: That file doesn't contain a PR2 level.");
			return;
		}
		if (LevelEditor.editor != null) {
			LevelEditor.editor.applyLoadedLevelData(data);
		}
	}

	/** The level in `text`, or null when it holds no level block data. **/
	public static function parse(text:String):Null<ServerLevelData> {
		var body = text == null ? "" : StringTools.trim(text);
		if (body == "") {
			return null;
		}
		// Just the data blob: wrap it as the `data` var.
		if (~/^m[1-4]`/.match(body)) {
			body = "data=" + body;
		}
		if (body.indexOf("data=") < 0) {
			return null;
		}
		// LevelDataClient.parse expects the server's trailing hash; supply a
		// placeholder when the file doesn't end with one.
		if (!~/[0-9a-f]{32}$/.match(body)) {
			body += "00000000000000000000000000000000";
		}
		var data:ServerLevelData;
		try {
			data = LevelDataClient.parse(body, 0, 0);
		} catch (error:Dynamic) {
			return null;
		}
		return data.data == "" || !~/^m[1-4]`/.match(data.data) ? null : data;
	}
}

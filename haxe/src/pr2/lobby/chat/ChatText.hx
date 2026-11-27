package pr2.lobby.chat;

/**
	Port of the chat-relevant text helpers from Flash `com.jiggmin.data.Data`:
	HTML escaping, whitespace trimming, and the swear filter toggle. These run on
	every incoming chat line, so they are kept pure and deterministic for testing.
**/
class ChatText {
	private function new() {}

	public static function cleanHTML(s:String):String {
		s = StringTools.replace(s, "&", "&amp;");
		s = StringTools.replace(s, ">", "&gt;");
		s = StringTools.replace(s, "<", "&lt;");
		s = StringTools.replace(s, "'", "&apos;");
		s = StringTools.replace(s, "\"", "&quot;");
		return s;
	}

	public static function trimWhitespace(s:String, keepNL:Bool = false):String {
		if (s == null) {
			return "";
		}
		s = StringTools.trim(s);
		// Collapse the remaining control whitespace to spaces. With keepNL only
		// tabs/form-feeds are replaced; otherwise newlines/returns/vtabs too.
		var pattern = keepNL ? ~/[\t\x0C]/g : ~/[\t\n\r\x0B\x0C]/g;
		return pattern.replace(s, " ");
	}

	public static function escapeString(s:String, preserveNewLine:Bool = false):String {
		return cleanHTML(trimWhitespace(s, preserveNewLine));
	}

	public static function escapeAndFilterString(s:String):String {
		if (s == null) {
			return "";
		}
		return filterSwears(cleanHTML(trimWhitespace(s)));
	}

	// Flash `Data.filterSwears`: each pattern is replaced, case-insensitively,
	// with one random entry of its themed list (picked once per pattern per
	// call). The matched words are stored ROT13-encoded so the source never
	// spells them out; `swearPattern` decodes them when the patterns are built.
	private static final swearReplacements:Array<Array<String>> = [
		["dang", "dingy-goo", "condemnation"],
		["fooey", "fingilly", "funk-master", "freak monster", "jiminy cricket"],
		["shoot", "shewet"],
		["someone cooler than me", "ladies magnet", "cooler race"],
		["cooler gender", "female dog"],
	];
	// [encoded word, whole-word suffix pattern or null, replacement list index],
	// in Flash's order.
	private static final swearRules:Array<Array<Dynamic>> = [
		["qnza", null, 0],
		["shpx", null, 1],
		["avt", "(?:g(?:a|er)?)?(?:s)?", 3],
		["fcvp", "", 3],
		["fuvg", null, 2],
		["ovgpu", null, 4],
		["phag", null, 4],
		["juber", null, 4],
	];
	private static var swearPatterns:Array<EReg>;

	private static function rot13(s:String):String {
		var out = new StringBuf();
		for (i in 0...s.length) {
			var c = s.charCodeAt(i);
			if (c >= "a".code && c <= "z".code) {
				c = "a".code + (c - "a".code + 13) % 26;
			}
			out.addChar(c);
		}
		return out.toString();
	}

	private static function swearPattern(rule:Array<Dynamic>):EReg {
		var word = rot13(rule[0]);
		var suffix:String = rule[1];
		return suffix == null ? new EReg(word, "gi") : new EReg("\\b(" + word + suffix + ")\\b", "gi");
	}

	public static function filterSwears(s:String):String {
		if (s == null) {
			return s;
		}
		if (swearPatterns == null) {
			swearPatterns = [for (rule in swearRules) swearPattern(rule)];
		}
		for (i in 0...swearRules.length) {
			var choices = swearReplacements[swearRules[i][2]];
			s = swearPatterns[i].replace(s, choices[Math.floor(Math.random() * choices.length)]);
		}
		return s;
	}

	public static function parseLinks(s:String):String {
		s = parseUser(s);
		s = parseUrl(s);
		s = ~/\[level=(\d{1,8})\](.+)\[\/level\]/gi.replace(s,
			"<a href='event:level`$1'><u><font color='#0000FF'>$2</font></u></a>");
		s = ~/\[guild=(\d{1,6})\](.+)\[\/guild\]/gi.replace(s,
			"<a href='event:guild`$1'><u><font color='#0000FF'>$2</font></u></a>");
		s = ~/\[guildlink=(\d{1,6})\](.+)\[\/guildlink\]/gi.replace(s,
			"<a href='event:guild`$1'><u><font color='#0000FF'>$2</font></u></a>");
		s = ~/\[invite=(\d+)\](.+)\[\/invite\]/gi.replace(s,
			"<a href='event:invite`$1'><u><font color='#0000FF'>$2</font></u></a>");
		s = ~/\[invitelink=(\d+)\](.+)\[\/invitelink\]/gi.replace(s,
			"<a href='event:invite`$1'><u><font color='#0000FF'>$2</font></u></a>");
		s = ~/\[discordverif=(.+)\](.+)\[\/discordverif\]/gi.replace(s,
			"<a href='event:discordverify`$1'><u><font color='#0000FF'>$2</font></u></a>");
		s = ~/\[color=(#[0-9a-fA-F]{6})\](.+)\[\/color\]/gi.replace(s, "<font color='$1'>$2</font>");
		s = ~/\[b\](.+)\[\/b\]/gi.replace(s, "<b>$1</b>");
		s = ~/\[bold\](.+)\[\/bold\]/gi.replace(s, "<b>$1</b>");
		s = ~/\[i\](.+)\[\/i\]/gi.replace(s, "<i>$1</i>");
		s = ~/\[em\](.+)\[\/em\]/gi.replace(s, "<i>$1</i>");
		s = ~/\[u\](.+)\[\/u\]/gi.replace(s, "<u>$1</u>");
		s = ~/\[tiny\](.+)\[\/tiny\]/gi.replace(s, "<font size='6'>$1</font>");
		s = ~/\[small\](.+)\[\/small\]/gi.replace(s, "<font size='9'>$1</font>");
		s = ~/\[medium\](.+)\[\/medium\]/gi.replace(s, "<font size='12'>$1</font>");
		s = ~/\[large\](.+)\[\/large\]/gi.replace(s, "<font size='24'>$1</font>");
		s = ~/\[big\](.+)\[\/big\]/gi.replace(s, "<font size='24'>$1</font>");
		return s;
	}

	private static function parseUser(s:String):String {
		var re = ~/\[user=(\d(?:,(\d|\*))?)\]([a-zA-Z0-9\-.:;=?~!()@*,+$#% ]+)\[\/user\]/gi;
		return re.map(s, function(r:EReg):String {
			var group = r.matched(1);
			var name = r.matched(3);
			return "<a href='event:user`" + group + "`" + name + "`1'><u><font color='#" + HtmlNameMaker.groupColor(group) + "'>" + name
				+ "</font></u></a>";
		});
	}

	private static function parseUrl(s:String):String {
		var bare = ~/\[url\](https?:\/\/(www\.)?[-a-zA-Z0-9@:%._+~#=]{2,256}\.[a-z]{2,4}\b(((?:&amp;)|[-a-zA-Z0-9@:%_+.~#?&\/=])*))\[\/url\]/g;
		s = bare.map(s, function(r:EReg):String {
			var url = StringTools.replace(r.matched(1), "&amp;", "&");
			return "<a href='event:url`" + url + "'><u><font color='#0000FF'>" + url + "</font></u></a>";
		});
		var named = ~/\[url=(https?:\/\/(www\.)?[-a-zA-Z0-9@:%._+~#=]{2,256}\.[a-z]{2,4}\b(((?:&amp;)|[-a-zA-Z0-9@:%_+.~#?&\/=])*))\](.+?)\[\/url\]/g;
		return named.map(s, function(r:EReg):String {
			return "<a href='event:url`" + StringTools.replace(r.matched(1), "&amp;", "&") + "'><u><font color='#0000FF'>" + r.matched(5)
				+ "</font></u></a>";
		});
	}
}

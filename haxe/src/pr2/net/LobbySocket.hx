package pr2.net;

import com.jiggmin.data.Time;
import haxe.Timer;
#if js
import js.Browser;
import js.html.WebSocket;
#end
import pr2.lobby.LobbySession;
import pr2.lobby.Memory;
import pr2.lobby.messages.UnreadNotif;
import pr2.page.PageHolder;

/**
	The single persistent game socket, mirroring Flash `Main.socket`: it is opened
	once when the player connects to a server and then reused for the whole
	session — the login handshake and every lobby/gameplay command share it. There
	is no per-page socket and no handing a connection from one owner to another.

	Incoming frames (END_CHAR terminated) are always routed to `CommandHandler`,
	including during login. LoginSocketProbe temporarily registers handlers for
	the handshake commands, matching Flash's single global command dispatcher.

	With no transport attached — headless tests and the OpenFL harness — writes are
	simply recorded into `sentCommands`, which lets parity tests assert exactly
	which commands a tab would have emitted without needing a live server.
**/
class LobbySocket {
	/** Commands written since the last `resetSent()` — inspected by tests. */
	public static var sentCommands:Array<String> = [];
	public static var sendNum:Int = 0;
	public static var closeCount:Int = 0;
	public static var campaignPage:Int = 0;
	public static var nowMs:Void->Float = defaultNowMs;

	/** Connection lifecycle hooks for the login UI; the lobby ignores these. */
	public static var onOpen:Null<Void->Void>;
	public static var onConnectionError:Null<Void->Void>;
	public static var onConnectionClose:Null<Void->Void>;

	private static var protocol:Null<LoginSocketProtocol>;
	private static var connected:Bool = false;
	private static var pingIntervalActive:Bool = false;
	private static var pingTimer:Null<Timer>;
	private static var serverTime:Time = new Time(function():Float return nowMs());
	#if js
	private static var socket:Null<WebSocket>;
	private static var buffer:String = "";
	#end

	private function new() {}

	/** Open the one game socket for `server`, replacing any previous connection. */
	public static function connect(server:ServerInfo, secure:Bool = false):Void {
		#if js
		close();
		CommandHandler.commandHandler.serverId = server.serverId;
		protocol = new LoginSocketProtocol(server.serverId);
		buffer = "";
		socket = new WebSocket(server.websocketUrl(secure));
		socket.onopen = function(_):Void {
			connected = true;
			openedAtMs = lastSendMs = lastCommandMs = lastReceiveMs = nowMs();
			startPingInterval();
			if (onOpen != null) {
				onOpen();
			}
		};
		socket.onmessage = function(event):Void {
			lastReceiveMs = nowMs();
			for (frame in splitFrames(Std.string(event.data))) {
				CommandHandler.commandHandler.handleServerFrame(frame);
			}
		};
		openedAtMs = -1;
		socket.onerror = function(_):Void {
			// An error on an open connection is always followed by `close`, which
			// says why; only a socket that never opened couldn't connect.
			if (openedAtMs < 0) handleConnectionError();
		};
		socket.onclose = function(event:js.html.CloseEvent):Void {
			if (openedAtMs < 0) {
				handleConnectionError();
				return;
			}
			lastCloseText = describeClose(event.code);
			handleConnectionClose();
		};
		#end
	}

	/** When the connection opened (-1 = not open yet), and when anything / a non-ping command was last sent. **/
	private static var openedAtMs:Float = -1;
	private static var lastSendMs:Float = 0;
	private static var lastCommandMs:Float = 0;
	private static var lastPingMs:Float = -1e12;
	/** When the server last sent anything (it answers every ping), and the name of the last command sent. **/
	private static var lastReceiveMs:Float = 0;
	private static var lastSentName:String = "";
	/** Why the last connection closed, for the "Disconnected." message. **/
	private static var lastCloseText:String = "";

	/** Milliseconds since the last command other than a ping was sent (the server drops players after 30 minutes without one). **/
	public static function msSinceLastCommand():Float {
		return nowMs() - lastCommandMs;
	}

	/**
		The server (PR2Client.onTimer) drops a connection after 60 s without any
		command, or 30 minutes with only pings, and closes it at once on a bad
		command hash or an out-of-order command number.
	**/
	private static function describeClose(code:Int):String {
		var t = nowMs();
		// Woken from a pause, the close can be handled before the next check runs.
		if (lastTickMs > 0 && t - lastTickMs > longestPauseMs) {
			longestPauseMs = t - lastTickMs;
			longestPauseEndMs = t;
		}
		var open = Math.round((t - openedAtMs) / 60000);
		var sent = Math.round((t - lastSendMs) / 1000);
		var command = Math.round((t - lastCommandMs) / 60000);
		var heard = Math.round((t - lastReceiveMs) / 1000);
		// The server answers every ping (sent every 10 s), so a long silence means the
		// line went dead before the close: the network or the server, not a command.
		// A page the browser froze sends nothing, so the server drops it after 60 s;
		// the close is only seen (and queued sends go out) once the tab wakes up.
		var paused = longestPauseMs >= 55000 && t - longestPauseEndMs < 10000;
		var cause = paused ? " The browser paused this page for over a minute, so the server dropped it."
			: sent >= 55 ? " Nothing was sent for a minute (the tab may have been asleep)."
			: (command >= 29 ? " Only pings were sent for 30 minutes, so the server counted you as away."
				: (heard >= 25 ? ' The server stopped answering ${heard}s before the drop (network or server).' : ""));
		return '(code $code after $open min connected; last sent ${sent}s ago ($lastSentName), last heard from the server ${heard}s ago, last game command $command min ago.$cause${pauseText(t)})';
	}

	public static function write(command:String):Void {
		sentCommands.push(command);
		sendNum++;
		if (sendNum == 12) {
			sendNum++;
		}
		#if js
		Browser.document.body.setAttribute("data-pr2-last-command", command);
		if (socket != null && socket.readyState == WebSocket.OPEN && protocol != null) {
			socket.send(protocol.commandFrame(command));
			lastSendMs = nowMs();
			var tick = command.indexOf("`");
			lastSentName = tick < 0 ? command : command.substr(0, tick);
			if (!StringTools.startsWith(command, "ping`")) lastCommandMs = lastSendMs;
		}
		#end
	}

	public static function close():Void {
		closeCount++;
		if (connected) {
			write("close`");
		}
		stopPingInterval();
		#if js
		if (socket != null) {
			socket.onopen = null;
			socket.onmessage = null;
			socket.onerror = null;
			socket.onclose = null;
			socket.close();
			socket = null;
		}
		buffer = "";
		#end
		connected = false;
		protocol = null;
		sendNum = 0;
		CommandHandler.commandHandler.sendNum = -1;
		clearRuntimeState();
	}

	/** True when a real transport is connected (vs. record-only headless mode). */
	public static function isConnected():Bool {
		#if js
		return connected && socket != null && socket.readyState == WebSocket.OPEN;
		#else
		return connected;
		#end
	}

	public static function resetSent():Void {
		sentCommands = [];
		sendNum = 0;
		closeCount = 0;
		connected = false;
		stopPingInterval();
		nowMs = defaultNowMs;
		serverTime = new Time(function():Float return nowMs());
	}

	/** Last command emitted, or "" if none — convenience for assertions. */
	public static function lastSent():String {
		return sentCommands.length == 0 ? "" : sentCommands[sentCommands.length - 1];
	}

	public static function sendPing():Void {
		if (isConnected()) {
			write("ping`");
		}
	}

	public static function receivePing(args:Array<String>):Void {
		var serverSeconds = args.length > 0 ? Std.parseFloat(args[0]) : Math.NaN;
		if (Math.isNaN(serverSeconds)) {
			return;
		}
		var localSeconds = serverTime.getTimestamp();
		if (Math.abs(serverSeconds - localSeconds) > 2) {
			serverTime.setTime(serverSeconds);
		}
	}

	public static function getMS():Float {
		return serverTime.getMS();
	}

	public static function getTimestamp():Float {
		return serverTime.getTimestamp();
	}

	public static function getDay():Float {
		return serverTime.getDay();
	}

	public static function pingIsActiveForTests():Bool {
		return pingIntervalActive;
	}

	public static function simulateOpenForTests():Void {
		connected = true;
		startPingInterval();
		if (onOpen != null) {
			onOpen();
		}
	}

	public static function simulateConnectionCloseForTests():Void {
		handleConnectionClose();
	}

	public static function simulateConnectionErrorForTests():Void {
		handleConnectionError();
	}

	public static function remove():Void {
		onOpen = null;
		onConnectionError = null;
		onConnectionClose = null;
		close();
	}

	private static function startPingInterval():Void {
		stopPingInterval();
		pingIntervalActive = true;
		#if js
		// The worker-driven ticker keeps pinging in a background tab, where page
		// timers are throttled to once a minute and the server (60 s of silence)
		// would drop the player. Without workers, a normal timer.
		// Both the worker and a page timer ask; whichever comes first pings, so a
		// stalled one (a throttled timer, a worker the browser paused) can't
		// leave the connection silent.
		lastPingMs = nowMs();
		lastTickMs = 0;
		longestPauseMs = 0;
		frozenTimes = 0;
		watchFreezes();
		stopBackgroundPing = pr2.runtime.BackgroundTicker.every(2000, pingIfDue);
		pingTimer = new Timer(2000);
		pingTimer.run = pingIfDue;
		#end
	}

	private static function pingIfDue():Void {
		// Asked every 2 s: a longer gap means no code ran (the browser froze or paused the tab).
		var now = nowMs();
		if (lastTickMs > 0 && now - lastTickMs > longestPauseMs) {
			longestPauseMs = now - lastTickMs;
			longestPauseEndMs = now;
		}
		lastTickMs = now;
		if (nowMs() - lastPingMs < 10000) return;
		lastPingMs = nowMs();
		sendPing();
	}

	private static var stopBackgroundPing:Null<Void->Void> = null;
	/** Pauses in the page while connected: the longest gap between the 2 s checks, when it ended, and how often the browser froze the tab. **/
	private static var lastTickMs:Float = 0;
	private static var longestPauseMs:Float = 0;
	private static var longestPauseEndMs:Float = 0;
	private static var frozenTimes:Int = 0;
	private static var freezeWatched:Bool = false;

	/** Chrome fires `freeze` before it stops a background tab (other browsers show it as a pause). **/
	private static function watchFreezes():Void {
		#if js
		if (freezeWatched) return;
		freezeWatched = true;
		Browser.document.addEventListener("freeze", function(_) frozenTimes++);
		#end
	}

	/** What the page was doing before a drop: hidden, frozen, or paused for a while. **/
	private static function pauseText(now:Float):String {
		var parts:Array<String> = [];
		#if js
		if (Browser.document.hidden) parts.push("the tab is hidden");
		#end
		if (frozenTimes > 0) parts.push('the browser froze the tab ${frozenTimes}x');
		if (longestPauseMs >= 5000) {
			parts.push('the page stopped for ${Math.round(longestPauseMs / 1000)}s, ${Math.round((now - longestPauseEndMs) / 1000)}s before the drop');
		}
		return parts.length == 0 ? "" : " " + parts.join("; ") + ".";
	}

	private static function stopPingInterval():Void {
		#if js
		if (pingTimer != null) {
			pingTimer.stop();
		}
		if (stopBackgroundPing != null) {
			stopBackgroundPing();
			stopBackgroundPing = null;
		}
		#end
		pingTimer = null;
		pingIntervalActive = false;
	}

	private static function handleConnectionClose():Void {
		stopPingInterval();
		connected = false;
		clearRuntimeState();
		var why = lastCloseText;
		lastCloseText = "";
		var text = why == "" ? "Disconnected." : 'Disconnected from the server $why';
		if (onConnectionClose != null) {
			onConnectionClose();
		} else {
			var rootHolder = PageHolder.getRootHolder();
			if (rootHolder == null) {
				pr2.app.ScreenFactory.message(text);
			} else if (rootHolder.getCurrentPage() == null || !rootHolder.getCurrentPage().isLoginScreen) {
				pr2.app.ScreenFactory.message(text);
				rootHolder.changePage(pr2.app.ScreenFactory.login());
			}
		}
	}

	private static function handleConnectionError():Void {
		stopPingInterval();
		connected = false;
		clearRuntimeState();
		if (onConnectionError != null) {
			onConnectionError();
		} else {
			pr2.app.ScreenFactory.message("Could not connect. This could be because: \n A: My server is broken. \n B: The internet is broken. \n C: Evil aliens.");
		}
	}

	private static function clearRuntimeState():Void {
		Memory.remove("coursePageNumcampaign");
		Memory.remove("campaignInfo" + campaignPage);
		LobbySession.isSpecialUser = false;
		LobbySession.isPrizer = false;
		LobbySession.isTempMod = false;
		LobbySession.isTrialMod = false;
		LobbySession.tournamentMode = false;
		LobbySession.serverOwner = 0;
		UnreadNotif.reset();
	}

	private static function defaultNowMs():Float {
		return Date.now().getTime();
	}

	#if js
	// Server frames are terminated by END_CHAR (\x04). Buffer partial reads and
	// emit only complete frames.
	private static function splitFrames(data:String):Array<String> {
		buffer += data;
		var frames = [];
		var endIndex = buffer.indexOf(LoginSocketProtocol.END_CHAR);
		while (endIndex >= 0) {
			frames.push(buffer.substr(0, endIndex));
			buffer = buffer.substr(endIndex + 1);
			endIndex = buffer.indexOf(LoginSocketProtocol.END_CHAR);
		}
		return frames;
	}
	#end
}

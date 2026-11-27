package pr2.page;

import openfl.display.Shape;
import pr2.runtime.SvgAsset;

private typedef LoginPageArt = {
	final assetPath:String;
	final trimX:Int;
	final trimY:Int;
}

/**
	Login menu ported from the Flash `menu.LoginPage`.

	The page art is rendered from the Animate SVG export. The original
	Flash menu buttons are runtime text controls, so only those labels and hit
	areas are rebuilt in Haxe.
**/
class LoginPage extends Page {
	private static inline var LOGIN_PAGE_NO_LOGO_ASSET = "assets/svg/login/login_page_no_logo.svg";
	private static inline var LOGIN_PAGE_NO_LOGO_TRIM_X = 868;
	private static inline var LOGIN_PAGE_NO_LOGO_TRIM_Y = 846;

	private static inline var MENU_X:Float = 275;
	private static inline var MENU_Y:Float = 228;
	private static inline var MENU_SPACING:Float = 22;

	private var background:Null<LoginBackground>;
	private var pageArt:Null<Shape>;
	private var timelineFade:Null<LoginPageFade>;
	private var title:Null<LoginTitle>;
	private var buttons:Array<LoginPageMenuButton> = [];
	public var flow(default, null):LoginFlow;
	public final siteMode:String;

	public function new(?siteMode:String) {
		super();
		isLoginScreen = true;
		this.siteMode = siteMode == null ? "kongregate" : siteMode;
		flow = new LoginFlow(function(userName, server):Void {
			if (pageHolder != null) pageHolder.changePage(pr2.app.ScreenFactory.lobby(userName, server));
		});
	}

	override public function initialize():Void {
		background = new LoginBackground();
		addChild(background);

		var art = loginPageArtFor(siteMode);
		pageArt = SvgAsset.create(art.assetPath);
		addChild(pageArt);

		title = new LoginTitle();
		addChild(title);

		addMenuButton("Log In", flow.openLoginDialog);
		addMenuButton("Play as Guest", flow.openGuestDialog);
		addMenuButton("Create Account", function():Void flow.openCreateAccountDialog());
		addMenuButton("Instructions", flow.openInstructions);
		addMenuButton("Credits", flow.openCreditsDialog);

		// LoginPageGraphic's first timeline layer is a full-stage black square
		// fading through 19 authored frames. The static SVG does not retain it.
		timelineFade = new LoginPageFade();
		addChild(timelineFade);

		addChild(flow);
		flow.start();
	}

	override public function remove():Void {
		flow.remove();
		if (timelineFade != null) {
			timelineFade.dispose();
			timelineFade = null;
		}

		for (button in buttons) {
			button.remove();
			if (button.parent != null) {
				button.parent.removeChild(button);
			}
		}
		buttons = [];

		if (title != null) {
			title.dispose();
			if (title.parent != null) title.parent.removeChild(title);
		}
		title = null;

		if (pageArt != null && pageArt.parent != null) {
			pageArt.parent.removeChild(pageArt);
		}
		pageArt = null;

		if (background != null) {
			background.remove();
			if (background.parent != null) {
				background.parent.removeChild(background);
			}
			background = null;
		}
		super.remove();
	}

	private function addMenuButton(label:String, clickHandler:Void->Void):Void {
		var button = new LoginPageMenuButton(label, clickHandler);
		button.name = switch label {
			case "Log In": "loginButton";
			case "Play as Guest": "guestButton";
			case "Create Account": "createAccountButton";
			case "Instructions": "instructionsButton";
			case "Credits": "creditsButton";
			default: "loginMenuButton";
		};
		button.x = MENU_X;
		button.y = MENU_Y + buttons.length * MENU_SPACING;
		buttons.push(button);
		addChild(button);
	}

	private static function loginPageArtFor(_siteMode:String):LoginPageArt {
		return {assetPath: LOGIN_PAGE_NO_LOGO_ASSET, trimX: LOGIN_PAGE_NO_LOGO_TRIM_X, trimY: LOGIN_PAGE_NO_LOGO_TRIM_Y};
	}

}

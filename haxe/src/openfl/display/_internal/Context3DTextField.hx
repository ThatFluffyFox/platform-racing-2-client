// Copied from OpenFL 9.5.2 (openfl/display/_internal/Context3DTextField.hx) with one PR2 change,
// marked below. It shadows the library file through the haxe/src class path; re-copy it when OpenFL is upgraded.
package openfl.display._internal;

#if !flash
import openfl.display._internal.CairoTextField;
import openfl.display._internal.CanvasTextField;
import openfl.display.OpenGLRenderer;
import openfl.text.TextField;

#if !openfl_debug
@:fileXml(' tags="haxe,release" ')
@:noDebug
#end
@:access(openfl.display.Graphics)
@:access(openfl.text.TextField)
@SuppressWarnings("checkstyle:FieldDocComment")
class Context3DTextField
{
	/**
		PR2 change (the rest of this file is OpenFL 9.5.2's own). Text is
		rasterized to a canvas at the software renderer's pixel ratio, with the
		stage's display scale left out (Context3DGraphics renders text with an
		identity world transform). OpenFL sets that ratio to the window's
		devicePixelRatio, so with the stage scaled up to fill the window (the
		HTML5 stage is Flash's 550x400 fitted to the browser) every text field
		was drawn at about half its on-screen resolution or less and stretched:
		at 150% Windows scaling in a 1180x858 window, 1.5 instead of 3.2 pixels
		per stage pixel. Flash drew text at the output resolution, so use the
		full display scale (devicePixelRatio times the stage scale).
	**/
	static function textPixelRatio(renderer:OpenGLRenderer):Float
	{
		var ratio = renderer.__pixelRatio;
		var display = renderer.__worldTransform;
		if (display != null)
		{
			var scale = Math.max(Math.sqrt(display.a * display.a + display.b * display.b), Math.sqrt(display.c * display.c + display.d * display.d));
			if (scale > ratio) ratio = scale;
		}
		return ratio;
	}

	public static function render(textField:TextField, renderer:OpenGLRenderer):Void
	{
		renderer.__softwareRenderer.__pixelRatio = textPixelRatio(renderer);

		#if (js && html5)
		CanvasTextField.render(textField, cast renderer.__softwareRenderer, textField.__worldTransform);
		#elseif lime_cairo
		CairoTextField.render(textField, cast renderer.__softwareRenderer, textField.__worldTransform);
		#end
		textField.__graphics.__hardwareDirty = false;
	}

	public static function renderDrawable(textField:TextField, renderer:OpenGLRenderer):Void
	{
		renderer.__updateCacheBitmap(textField, false);

		if (textField.__cacheBitmap != null && !textField.__isCacheBitmapRender)
		{
			Context3DBitmap.render(textField.__cacheBitmap, renderer);
		}
		else
		{
			Context3DTextField.render(textField, renderer);
			Context3DDisplayObject.render(textField, renderer);
		}

		renderer.__renderEvent(textField);
	}

	public static function renderDrawableMask(textField:TextField, renderer:OpenGLRenderer):Void
	{
		Context3DTextField.renderMask(textField, renderer);
		Context3DDisplayObject.renderDrawableMask(textField, renderer);
	}

	public static function renderMask(textField:TextField, renderer:OpenGLRenderer):Void
	{
		renderer.__softwareRenderer.__pixelRatio = textPixelRatio(renderer);
		#if (js && html5)
		CanvasTextField.render(textField, cast renderer.__softwareRenderer, textField.__worldTransform);
		#elseif lime_cairo
		CairoTextField.render(textField, cast renderer.__softwareRenderer, textField.__worldTransform);
		#end
		textField.__graphics.__hardwareDirty = false;
	}
}
#end

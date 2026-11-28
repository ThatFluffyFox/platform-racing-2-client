package pr2.ui;

import openfl.display.DisplayObject;
import openfl.display.DisplayObjectContainer;
import openfl.display.InteractiveObject;
import openfl.display.Shape;
import openfl.display.SimpleButton;
import openfl.display.Stage;
import openfl.events.Event;
import openfl.events.KeyboardEvent;
import openfl.events.MouseEvent;
import openfl.geom.Rectangle;
import openfl.text.TextField;
import openfl.text.TextFieldType;
import openfl.ui.Keyboard;
import pr2.ui.controls.NativeControl;

/**
	Tab traversal as PR2's Flash build had it. The first fl.controls component
	on stage creates a `fl.managers.FocusManager` for the stage, and from the
	login screen on it owns the Tab key:

	- Tab stops are tab-enabled objects on the display list (SimpleButtons,
	  `buttonMode` sprites, input text fields, components) whose ancestors are
	  visible and allow tab children; disabled components and buttons, and
	  dynamic or unselectable text fields, are skipped. A component is one stop.
	- The order is display-list depth (`sortByDepth` compares child-index
	  paths from the stage), not screen position. If any stop has a positive
	  `tabIndex`, only those stops are used, in `tabIndex` order.
	- Components draw their own focus skin. Any other focused object gets the
	  Flash Player's yellow focus rectangle while focus is shown, and Enter or
	  Space activates a focused button.
	- Pointer input hides the indicators until the next Tab.
**/
class KeyboardFocusManager {
	private static inline var FOCUS_COLOR:Int = 0xFFFF00;

	private static var installedStage:Null<Stage>;
	private static var focusRect:Null<Shape>;
	private static var rectTarget:Null<InteractiveObject>;

	private function new() {}

	public static function install(stage:Stage):Void {
		if (installedStage == stage) return;
		if (installedStage != null) {
			installedStage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown, true);
			installedStage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
			installedStage.removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown, true);
			installedStage.removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
			hideFocusRect();
		}
		installedStage = stage;
		stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown, true, 1000);
		// When Stage itself is the event target there is no capture phase.
		stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown, false, 1000);
		stage.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown, true, 1000);
		stage.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown, false, 1000);
	}

	/** Pointer input hides focus rectangles until the next Tab, exactly like Flash. */
	private static function onMouseDown(_:MouseEvent):Void {
		NativeControl.showFocusIndicator = false;
		hideFocusRect();
		if (installedStage == null) return;
		var current:Null<DisplayObject> = installedStage.focus;
		while (current != null) {
			var control = Std.downcast(current, NativeControl);
			if (control != null) {
				control.hideFocusIndicator();
				return;
			}
			current = current.parent;
		}
	}

	private static function onKeyDown(event:KeyboardEvent):Void {
		var stage = installedStage;
		if (stage == null || event.isDefaultPrevented()) return;
		if (event.keyCode == Keyboard.TAB) {
			advanceFocus(stage, event.shiftKey);
			event.preventDefault();
			return;
		}
		if ((event.keyCode == Keyboard.ENTER || event.keyCode == Keyboard.SPACE) && rectTarget != null && stage.focus == rectTarget
			&& event.eventPhase != openfl.events.EventPhase.CAPTURING_PHASE) {
			activateFocusedButton(rectTarget);
		}
	}

	/**
		Flash Player clicks a keyboard-focused button on Enter or Space. Buttons
		that already handle their own keys (LobbyArt bindings, components) are
		left to them, so nothing fires twice.
	**/
	private static function activateFocusedButton(target:InteractiveObject):Void {
		if (Std.isOfType(target, TextField) || Std.isOfType(target, NativeControl)) return;
		if (target.hasEventListener(KeyboardEvent.KEY_DOWN)) return;
		target.dispatchEvent(new MouseEvent(MouseEvent.CLICK, true, false));
	}

	private static function advanceFocus(stage:Stage, reverse:Bool):Void {
		var candidates = orderedCandidates(stage);
		if (candidates.length == 0) return;
		NativeControl.showFocusIndicator = true;
		var currentIndex = candidateIndex(candidates, stage.focus);
		var offset = reverse ? -1 : 1;
		var nextIndex = currentIndex < 0 ? (reverse ? candidates.length - 1 : 0) : currentIndex + offset;
		if (nextIndex < 0) nextIndex = candidates.length - 1;
		if (nextIndex >= candidates.length) nextIndex = 0;
		var next = candidates[nextIndex];
		// A component takes focus through its own focus(), which hands a TextInput's
		// focus to its field so typing reaches it.
		var control = Std.downcast(next, NativeControl);
		if (control != null) control.focus() else stage.focus = next;
		// Flash Player selects a text field's contents when Tab reaches it.
		var field = Std.downcast(stage.focus, TextField);
		if (field != null && field.type == TextFieldType.INPUT) field.setSelection(0, field.text.length);
		showFocusRect(stage, next);
	}

	private static function orderedCandidates(root:DisplayObjectContainer):Array<InteractiveObject> {
		var entries:Array<FocusEntry> = [];
		collect(root, entries);
		var hasAuthoredOrder = false;
		for (entry in entries) {
			if (entry.target.tabIndex > 0) {
				hasAuthoredOrder = true;
				break;
			}
		}
		if (hasAuthoredOrder) {
			entries = entries.filter(function(entry):Bool return entry.target.tabIndex > 0);
			entries.sort(compareAuthored);
		}
		// Otherwise `collect` already visits in display-list depth order.
		return [for (entry in entries) entry.target];
	}

	/**
		Depth-first in child order: the order fl.managers.FocusManager.sortByDepth
		gives. Where a container's own tab stops match one of the SWF symbols in
		FlashTabOrder, those siblings take that symbol's depth order instead, since
		the port does not always add a view's controls in the authored order.
	**/
	private static function collect(container:DisplayObjectContainer, entries:Array<FocusEntry>):Void {
		var units:Array<Array<InteractiveObject>> = [];
		var stopNames:Array<Null<String>> = [];
		for (i in 0...container.numChildren) {
			var child = container.getChildAt(i);
			if (!child.visible) continue;
			var unit:Array<InteractiveObject> = [];
			var interactive = Std.downcast(child, InteractiveObject);
			var ownStop = interactive != null && isTabStop(interactive);
			if (ownStop) unit.push(interactive);
			var childContainer = Std.downcast(child, DisplayObjectContainer);
			// A UIComponent is one atomic tab stop; its skin and fields are not.
			if (childContainer != null && childContainer.tabChildren && !Std.isOfType(child, NativeControl)) {
				var nested:Array<FocusEntry> = [];
				collect(childContainer, nested);
				for (entry in nested) unit.push(entry.target);
			}
			if (unit.length == 0) continue;
			units.push(unit);
			stopNames.push(ownStop ? flashName(child.name) : null);
		}
		applyFlashOrder(units, stopNames);
		for (unit in units) {
			for (target in unit) entries.push(new FocusEntry(target, entries.length));
		}
	}

	private static function flashName(name:Null<String>):Null<String> {
		if (name == null) return null;
		return StringTools.endsWith(name, "_control") ? name.substr(0, name.length - "_control".length) : name;
	}

	/** Reorders the named sibling stops among their own slots by the matching SWF symbol. */
	private static function applyFlashOrder(units:Array<Array<InteractiveObject>>, stopNames:Array<Null<String>>):Void {
		var slots:Array<Int> = [];
		for (i in 0...stopNames.length) if (stopNames[i] != null) slots.push(i);
		if (slots.length < 2) return;
		var order:Null<Array<String>> = null;
		for (symbol in FlashTabOrder.symbols) {
			var all = true;
			for (slot in slots) {
				if (symbol.indexOf(stopNames[slot]) < 0) {
					all = false;
					break;
				}
			}
			if (all) {
				order = symbol;
				break;
			}
		}
		if (order == null) return;
		var picked = [for (slot in slots) {unit: units[slot], rank: order.indexOf(stopNames[slot])}];
		picked.sort(function(a, b):Int return a.rank - b.rank);
		for (i in 0...slots.length) units[slots[i]] = picked[i].unit;
	}

	private static function isTabStop(target:InteractiveObject):Bool {
		if (!target.tabEnabled) return false;
		var control = Std.downcast(target, NativeControl);
		if (control != null) return control.enabled;
		var field = Std.downcast(target, TextField);
		if (field != null) return field.type == TextFieldType.INPUT && field.selectable;
		var button = Std.downcast(target, SimpleButton);
		if (button != null) return button.enabled;
		// The port stacks invisible hit sprites over decorative art; a sprite that
		// can never take a click is not a Flash button.
		return target.mouseEnabled;
	}

	private static function compareAuthored(a:FocusEntry, b:FocusEntry):Int {
		var order = a.target.tabIndex - b.target.tabIndex;
		return order == 0 ? a.serial - b.serial : order;
	}

	private static function candidateIndex(candidates:Array<InteractiveObject>, focus:Null<InteractiveObject>):Int {
		var current:Null<DisplayObject> = focus;
		while (current != null) {
			var interactive = Std.downcast(current, InteractiveObject);
			if (interactive != null) {
				var index = candidates.indexOf(interactive);
				if (index >= 0) return index;
			}
			current = current.parent;
		}
		return -1;
	}

	/**
		Flash Player's stage focus rectangle: a yellow outline around the focused
		object. Components draw their own focus skin and text fields show a caret,
		so neither gets one.
	**/
	private static function showFocusRect(stage:Stage, target:InteractiveObject):Void {
		var control = Std.downcast(target, NativeControl);
		if ((control != null && !control.flashSimpleButton) || Std.isOfType(target, TextField)) {
			hideFocusRect();
			return;
		}
		if (focusRect == null) {
			focusRect = new Shape();
			focusRect.name = "stageFocusRect";
		}
		rectTarget = target;
		stage.addChild(focusRect);
		drawFocusRect(null);
		stage.addEventListener(Event.ENTER_FRAME, drawFocusRect);
	}

	private static function hideFocusRect():Void {
		if (installedStage != null) installedStage.removeEventListener(Event.ENTER_FRAME, drawFocusRect);
		rectTarget = null;
		if (focusRect != null && focusRect.parent != null) focusRect.parent.removeChild(focusRect);
	}

	/** Follows the focused object every frame, and drops the outline once focus moves. */
	private static function drawFocusRect(_:Null<Event>):Void {
		var stage = installedStage;
		var target = rectTarget;
		if (stage == null || focusRect == null || target == null) return;
		if (stage.focus != target || target.stage == null || !NativeControl.showFocusIndicator) {
			hideFocusRect();
			return;
		}
		if (stage.getChildIndex(focusRect) != stage.numChildren - 1) stage.addChild(focusRect);
		var bounds:Rectangle = visualBounds(target, stage);
		var g = focusRect.graphics;
		g.clear();
		g.lineStyle(2, FOCUS_COLOR, 1, true);
		g.drawRect(bounds.x - 1, bounds.y - 1, bounds.width + 2, bounds.height + 2);
	}

	/**
		Flash outlines what the button shows. Port buttons often carry a larger
		transparent hit rectangle in their own graphics, so measure the visible
		children when there are any.
	**/
	private static function visualBounds(target:InteractiveObject, stage:Stage):Rectangle {
		var container = Std.downcast(target, DisplayObjectContainer);
		var union:Null<Rectangle> = null;
		if (container != null) {
			for (i in 0...container.numChildren) {
				var child = container.getChildAt(i);
				if (!child.visible) continue;
				var b = child.getBounds(stage);
				if (b.width <= 0 || b.height <= 0) continue;
				union = union == null ? b : union.union(b);
			}
		}
		return union != null ? union : target.getBounds(stage);
	}

	public static function focusRectTargetForTests():Null<InteractiveObject> return rectTarget;
}

private class FocusEntry {
	public final target:InteractiveObject;
	public final serial:Int;

	public function new(target:InteractiveObject, serial:Int) {
		this.target = target;
		this.serial = serial;
	}
}

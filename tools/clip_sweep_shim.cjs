// Browser globals that Lime/OpenFL's html5 backend touches while static
// initializers run (e.g. a BitmapData creating a canvas). The clip sweep never
// draws anything; it only needs the module to load under Node, so every
// browser object is a permissive stub that accepts any call or property read.
function stub() {
	const fn = function () {
		return proxy;
	};
	const proxy = new Proxy(fn, {
		get(target, key) {
			if (key === Symbol.toPrimitive) return () => 0;
			if (key === "then") return undefined;
			if (key in target) return target[key];
			return proxy;
		},
		set(target, key, value) {
			target[key] = value;
			return true;
		},
		apply() {
			return proxy;
		},
		construct() {
			return proxy;
		},
	});
	return proxy;
}

globalThis.location = globalThis.location || { href: "" };
globalThis.window = globalThis.window || stub();
globalThis.document = globalThis.document || globalThis.window.document;

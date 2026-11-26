package pr2.gameplay.player;

import pr2.level.Level.LevelBlock;

class PixelPoint {
	public final x:Float;
	public final y:Float;

	public function new(x:Float, y:Float) {
		this.x = x;
		this.y = y;
	}
}

class TilePoint {
	public final x:Int;
	public final y:Int;

	public function new(x:Int, y:Int) {
		this.x = x;
		this.y = y;
	}
}

class PresentationContact {
	public var block(default, null):Null<LevelBlock> = null;
	public var tileX(default, null):Int = 0;
	public var tileY(default, null):Int = 0;

	public function new() {}

	public inline function capture(block:LevelBlock):Void {
		this.block = block;
		tileX = block.x;
		tileY = block.y;
	}

	public inline function clear():Void {
		block = null;
	}
}

typedef BlockRefs = {
	final floorLeft:Null<LevelBlock>;
	final floorCenter:Null<LevelBlock>;
	final floorRight:Null<LevelBlock>;
	final wallLeft:Null<LevelBlock>;
	final midBlock:Null<LevelBlock>;
	final wallRight:Null<LevelBlock>;
	final ceilLeft:Null<LevelBlock>;
	final ceiling:Null<LevelBlock>;
	final ceilRight:Null<LevelBlock>;
	final headBlock:Null<LevelBlock>;
	final topBlock:Null<LevelBlock>;
}

typedef PendingMinePlacement = {
	var tileX:Int;
	var tileY:Int;
	var framesRemaining:Int;
	var displayX:Int;
	var displayY:Int;
}

typedef PendingProjectileDamage = {
	var shotX:Float;
	var shotY:Float;
	var velX:Float;
	var velY:Float;
	var damageForce:Float;
	var framesRemaining:Int;
}

typedef PhysicsBlockTrace = {
	var kind:String;
	var source:String;
	var beforeState:String;
	var beforeBlock:String;
}

class PlayerStats {
	public final speed:Float;
	public final acceleration:Float;
	public final jump:Float;

	public function new(speed:Float, acceleration:Float, jump:Float) {
		this.speed = speed;
		this.acceleration = acceleration;
		this.jump = jump;
	}
}

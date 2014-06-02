package tink.lang.macros;

import haxe.macro.Expr;
import tink.macro.*;
import tink.core.*;

using tink.MacroApi;

class Dispatch {
	static function make(type:String) {
		var Type = type.charAt(0).toUpperCase() + type.substr(1);
		function mk(s:String, t)
			return s.asComplexType([TPType(t)]);
		return new Pair(':$type', {
			published: function (t) return mk('tink.core.$Type', t),
			internal: function (t) return mk('tink.core.$Type.${Type}Trigger', t),
			init: function (pos, t) return ENew('tink.core.$Type.${Type}Trigger'.asTypePath([TPType(t)]), []).at(pos),
			publish: function (e:Expr) return e.field('as$Type', e.pos).call(e.pos)
		});
	}
	static var types = [
		make('signal'),
		make('future')
	];
	
	static public function members(ctx:ClassBuilder) {
		for (type in types) {
			var make = type.b;
			for (member in ctx) 	
				switch (member.extractMeta(type.a)) {
					case Success(tag):
						switch (member.kind) {
							case FVar(t, e):
								if (t == null)
									t = if (e == null) 
											macro : tink.core.Signal.Noise;
										else 
											e.pos.makeBlankType();
								if (e == null) {	
									var own = '_' + member.name;
									ctx.addMember( {
										name: own,
										kind: FVar(make.internal(t), make.init(tag.pos, t)),
										pos: tag.pos
									}, true).isPublic = false;	
									e = make.publish(own.resolve(tag.pos));
								}
								member.kind = FVar(make.published(t), e);
								member.addMeta(':read');
							default:
								member.pos.error('can only declare signals on variables');
						}
					default:
				}
		}
	}	
	
	static public function normalize(e:Expr)
		return switch e {
			case macro @until($a{args}) $handler:
				macro @:pos(e.pos) @when($a{args}) $handler;
			default: e;	
		}
	
	static var DISPATCHER = macro tink.lang.helpers.StringDispatcher;
	
	static public function on(e:Expr) 
		return
			switch e {
				case macro @when($a{args}) $handler:
					if (args.length == 0)
						e.reject('At least one signal/event/future expected');
					var ret = [for (arg in args) 
						switch arg {
							case macro @capture $dispatcher[$event]
								,macro $dispatcher[@capture $event]:
								//TODO: allow for Iterable<String>
								macro @:pos(arg.pos) 
									$DISPATCHER.capture($DISPATCHER.promote($dispatcher), $event, __h);
							case macro $dispatcher[$event]:
								macro @:pos(arg.pos) 
									$DISPATCHER.promote($dispatcher).watch($event, __h);
							default:
								macro @:pos(arg.pos) $arg.when(__h);
						}
					].toArray();
					macro (function (__h) return $ret)($handler);//TODO: SIAF only generated because otherwise inference order will cause compiler error
				default: e;
			}
			
	static public function with(e:Expr) 
		return switch e {
			case macro @with($target) $handle:
				function transform(e:Expr) return switch e {
					case macro @with($_) $_: e;//should not occur in fact
					case macro @when($a{args}) $handler:
						args = 
							[for (arg in args) 
								switch arg.typeof() {
									case Success(t) if (t.getID() == 'String'):
										switch arg {
											case macro @capture $event: 
												macro @:pos(arg.pos) @capture ___t[$event];
											case event: 
												macro @:pos(arg.pos) ___t[$event];
										}
									default:
										switch arg {
											case macro $i{name}: 
												macro @:pos(arg.pos) ___t.$name;
											case macro $i{name}($a{args}): 
												macro @:pos(arg.pos) ___t.$name($a{args});
											default: arg;
										}
								}
							];
						handler = transform(handler);
						macro @when($a{args}) $handler;
					default: e.map(transform);
				}
				macro {
					var ___t = $target;
					${transform(handle)};
					___t;
				}
			default: e;
		}
}
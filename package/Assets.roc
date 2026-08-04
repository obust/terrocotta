## Platform-independent texture adapter.
##
## The boxed draw callback captures the platform's typed texture resource. This
## keeps its ownership and validation intact while allowing Terracotta to stay
## independent of a particular rendering platform.

import Color

Assets := [].{

	TextureRect : {
		source : { x : F32, y : F32, width : F32, height : F32 },
		dest : { x : F32, y : F32, width : F32, height : F32 },
		origin : { x : F32, y : F32 },
		rotation : F32,
		tint : Color,
	}

	TextureQuad : {
		top_left : { x : F32, y : F32 },
		bottom_left : { x : F32, y : F32 },
		bottom_right : { x : F32, y : F32 },
		top_right : { x : F32, y : F32 },
		tint : Color,
	}

	TextureCommand : [DrawRect(TextureRect), DrawQuad(TextureQuad)]

	TextureConfig : {
		width : F32,
		height : F32,
		draw! : TextureCommand => {},
	}

	KeyedTextureConfig : {
		key : U64,
		width : F32,
		height : F32,
		draw! : TextureCommand => {},
	}

	Texture :: {
		key : U64,
		width : F32,
		height : F32,
		draw : Box(TextureCommand => {}),
	}

	new : TextureConfig -> Texture
	new = |config| Texture.({ key: 0, width: config.width, height: config.height, draw: Box.box(config.draw!) })

	new_keyed : KeyedTextureConfig -> Texture
	new_keyed = |config| Texture.({ key: config.key, width: config.width, height: config.height, draw: Box.box(config.draw!) })

	key : Texture -> U64
	key = |Texture.(texture)| texture.key

	width : Texture -> F32
	width = |Texture.(texture)| texture.width

	height : Texture -> F32
	height = |Texture.(texture)| texture.height

	size : Texture -> { x : F32, y : F32 }
	size = |texture| { x: Assets.width(texture), y: Assets.height(texture) }

	rect : Texture -> { x : F32, y : F32, width : F32, height : F32 }
	rect = |texture| { x: 0, y: 0, width: Assets.width(texture), height: Assets.height(texture) }

	draw! : Texture, TextureCommand => {}
	draw! = |Texture.(texture), command| (Box.unbox(texture.draw))(command)
}

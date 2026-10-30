import rr.Assets
import rr.Audio
import rr.Draw
import render/SunnySprites

GameAssets := {
	store : Assets.Store,
	atlas : Draw.Texture,
	atlas_props : Draw.Texture,
	back : Draw.Texture,
	middle : Draw.Texture,
	tileset : Draw.Texture,
	title : Draw.Texture,
	press_enter : Draw.Texture,
	instructions : Draw.Texture,
	credits : Draw.Texture,
	music : Audio.Music,
	sprites : SunnySprites.Manifest,
	prop_sprites : SunnySprites.Manifest,
}.{
	assets_dir : Str
	assets_dir = "examples/game-sunnyland/assets"
	load! = |io| {
		asset_root = io.files().open_dir_read!(assets_dir)?
		store = Assets.open!(asset_root, IgnoreManifest)?
		Ok({
			store,
			atlas: Assets.load_texture!(store, "atlas/atlas.png")?,
			atlas_props: Assets.load_texture!(store, "atlas/atlas-props.png")?,
			back: Assets.load_texture!(store, "environment/back.png")?,
			middle: Assets.load_texture!(store, "environment/middle.png")?,
			tileset: Assets.load_texture!(store, "environment/tileset.png")?,
			title: Assets.load_texture!(store, "sprites/title-screen.png")?,
			press_enter: Assets.load_texture!(store, "sprites/press-enter-text.png")?,
			instructions: Assets.load_texture!(store, "sprites/instructions.png")?,
			credits: Assets.load_texture!(store, "sprites/credits-text.png")?,
			music: Audio.load_music!(store, "sound/platformer_level03_loop.ogg")?,
			sprites: SunnySprites.atlas,
			prop_sprites: SunnySprites.atlas_props,
		})
	}
}

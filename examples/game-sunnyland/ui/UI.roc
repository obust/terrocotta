import tc.Color
import rr.Draw
import tc.Element exposing [ImageSizing.*, box, image, style, text]
import tc.Program exposing [View]
import ../GameAssets
import ../Game

UI := [].{
	Msg : [Resume, Restart]
	view : Game.World, GameAssets -> List(View(Msg))
	view = |world, assets| List.concat([hud(world), controls_hint], overlay_for(world, assets))
}

gap : F32
gap = 8

scrim_color = (0x0C1925.Color).with_alpha(170)

panel_color = (0x172B33.Color).with_alpha(245)

hud_background_color = (0x142227.Color).with_alpha(205)

hud_border_color = (0xB4DCD4.Color).with_alpha(150)

hud_text_color = (0xE9EFD9.Color).with_alpha(255)

title_accent_color = 0xF7D47B.Color

win_accent_color = 0x9CF08B.Color

dead_accent_color = 0xF08080.Color

hud : Game.World -> View(UI.Msg)
hud = |world| box({ style: |_| style.width(Fit({})).height(Fit({})).direction(Row).pad(gap, gap * 2, gap, gap * 2).background(hud_background_color).border({ color: hud_border_color, left: 1, right: 1, top: 1, bottom: 1 }).radius(8).font_size(12).font_color(hud_text_color).floating(Floating({ target: Parent, config: { ..Element.default_floating_config, z_index: 10, offset: { x: 12, y: 12 }, attach_points: { element: LeftTop, target: LeftTop }, capture: Passthrough, clip_to: AttachedParent } })) }, [text("HEALTH ${world.player.health.to_str()} · ITEMS ${world.collected.to_str()} / ${world.total_pickups.to_str()}")])

controls_hint : View(UI.Msg)
controls_hint = box({ style: |_| style.width(Fit({})).height(Fit({})).pad(gap, gap * 2, gap, gap * 2).background(hud_background_color).border({ color: hud_border_color, left: 1, right: 1, top: 1, bottom: 1 }).radius(8).font_size(12).font_color(hud_text_color).text_align(Center).floating(Floating({ target: Parent, config: { ..Element.default_floating_config, z_index: 20, offset: { x: 0, y: -12 }, attach_points: { element: CenterBottom, target: CenterBottom }, capture: Passthrough, clip_to: AttachedParent } })) }, [text("Left/Right: Move · Down: Crouch · Space: Jump · Esc: Pause · R: Restart")])

overlay_for : Game.World, GameAssets -> List(View(UI.Msg))
overlay_for = |world, assets| match world.state {
	Playing => []
	Title => [image_overlay([image(assets.title, { width: Pixels(388), height: Pixels(76) }), image(assets.press_enter, { width: Pixels(152), height: Pixels(24) })])]
	Instructions => [image_overlay([image(assets.instructions, { width: Pixels(568), height: Pixels(336) }), image(assets.press_enter, { width: Pixels(152), height: Pixels(24) })])]
	Paused => [message("PAUSED", "Esc resumes  ·  R restarts", title_accent_color)]
	Dead => [message_with_prompt("TRY AGAIN", "You ran out of hearts", assets.press_enter, dead_accent_color)]
	Won => [message_with_prompt("HOME SWEET HOME", "All treasures collected", assets.press_enter, win_accent_color)]
}

image_overlay : List(View(UI.Msg)) -> View(UI.Msg)
image_overlay = |images| box({ style: |_| style.width(Grow({})).height(Grow({})).background(scrim_color).child_align({ x: Center, y: Center }).floating(Floating({ target: Root, config: { ..Element.default_floating_config, z_index: 100, capture: Capture } })) }, [box({ style: |_| style.width(Fit({})).height(Fit({})).direction(Col).gap(gap * 3).child_align({ x: Center, y: Center }) }, images)])

message : Str, Str, Color -> View(UI.Msg)
message = |heading, body, accent| box({ style: |_| style.width(Grow({})).height(Grow({})).background(scrim_color).child_align({ x: Center, y: Center }).font_size(12).font_color(Color.white).floating(Floating({ target: Root, config: { ..Element.default_floating_config, z_index: 100, capture: Capture } })) }, [box({ style: |_| style.width(Fit({})).height(Fit({})).direction(Col).gap(gap * 2).pad(gap * 3, gap * 4, gap * 3, gap * 4).background(panel_color).border({ color: accent, left: 2, right: 2, top: 2, bottom: 2 }).radius(12).child_align({ x: Center, y: Center }) }, [text(heading), text(body)])])

message_with_prompt : Str, Str, Draw.Texture, Color -> View(UI.Msg)
message_with_prompt = |heading, body, prompt_texture, accent| box({ style: |_| style.width(Grow({})).height(Grow({})).background(scrim_color).child_align({ x: Center, y: Center }).font_size(12).font_color(Color.white).floating(Floating({ target: Root, config: { ..Element.default_floating_config, z_index: 100, capture: Capture } })) }, [box({ style: |_| style.width(Fit({})).height(Fit({})).direction(Col).gap(gap * 2).pad(gap * 3, gap * 4, gap * 3, gap * 4).background(panel_color).border({ color: accent, left: 2, right: 2, top: 2, bottom: 2 }).radius(12).child_align({ x: Center, y: Center }) }, [text(heading), text(body), image(prompt_texture, { width: Pixels(152), height: Pixels(24) })])])

## Bridge Terracotta's platform-independent startup settings to current roc-ray.
import rr.App

import tc.Program

RocRayApp := [].{
	config : Program.Config -> App.Config
	config = |config| {
		pacing = if config.vsync {
			VSync
		} else if config.target_fps > 0 {
			Capped(config.target_fps)
		} else {
			Uncapped
		}
		cursor = if config.cursor_visible CursorVisible else CursorHidden

		App.default
			.with_title(config.title)
			.with_size({ width: config.width, height: config.height })
			.with_frame_pacing(pacing)
			.with_resizable(config.resizable)
			.with_fullscreen(config.fullscreen)
			.with_cursor(cursor)
	}
}

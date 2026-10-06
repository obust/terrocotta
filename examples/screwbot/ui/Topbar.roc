## The top-level controls emit robot commands directly; the app shell routes
## them to the world.
import tc.Color
import tc.Element exposing [box, style, text]
import tc.Program exposing [View]
import tc.Theme
import tc.Widget

import ../scene/RobotKinematics

Topbar := [].{
	view : Theme -> View(msg)
	view = |theme| box(
		{
			style: |_|
				style.width(Grow({})).height(Fixed(92)).background(theme.palette.surface.base.fill).border({ color: theme.palette.edge.border, left: 0, right: 0, top: 0, bottom: 1 }).pad(12, 20, 12, 20).gap(14).direction(Row).child_align({ x: Start, y: Center }).font_color(theme.palette.surface.base.content),
		},
		[
			box(
				{ style: |_| style.width(Fit({})).height(Fit({})).direction(Row).gap(12).child_align({ x: Start, y: Center }) },
				[
					box({ style: |_| style.width(Fixed(4)).height(Fixed(50)).background(theme.palette.primary.base.fill).radius(2) }, []),
					box(
						{ style: |_| style.width(Fit({})).height(Fit({})).direction(Col).gap(2).child_align({ x: Start, y: Start }) },
						[
							box({ style: |_| style.width(Fit({})).height(Fit({})).font_size(30).font_color(theme.palette.primary.base.fill) }, [text("SCREWBOT")]),
							box({ style: |_| style.width(Fit({})).height(Fit({})).font_size(15).font_color(theme.palette.text.muted) }, [text("Live 3D Projective Geometric Algebra")]),
						],
					),
				],
			),
		],
	)
}

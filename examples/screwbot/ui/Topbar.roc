## The top-level controls emit robot commands directly; the app shell routes
## them to the world.
import tc.Color
import tc.Element exposing [box, style, text]
import tc.Program exposing [View]
import tc.Theme
import tc.Widget

import tc.Palette as BuiltinPalette
import ../scene/RobotKinematics
import ../scene/Robot
import ../scene/RobotKinematics
import ../ui/Utils exposing [preset_button]

Topbar := [].{
	view : Theme, RobotKinematics.Solution -> View(Robot.Msg)
	view = |theme, solution| box(
		{
			style: |_|
				style.width(Grow({ min: 0, max: 10000 })).height(Fixed(92)).background(BuiltinPalette.atom_dark.background).border({ color: BuiltinPalette.atom_dark.text.with_alpha(55), left: 0, right: 0, top: 0, bottom: 1 }).pad(12, 20, 12, 20).gap(14).direction(Row).child_align({ x: Start, y: Center }).font_color(BuiltinPalette.atom_dark.text),
		},
		[
			box(
				{ style: |_| style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).direction(Row).gap(12).child_align({ x: Start, y: Center }) },
				[
					box({ style: |_| style.width(Fixed(4)).height(Fixed(50)).background(BuiltinPalette.atom_dark.primary).radius(2) }, []),
					box(
						{ style: |_| style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).direction(Col).gap(2).child_align({ x: Start, y: Start }) },
						[
							box({ style: |_| style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).font_size(30).font_color(BuiltinPalette.atom_dark.primary) }, [text("SCREWBOT // PGA LAB")]),
							box({ style: |_| style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).font_size(15).font_color(BuiltinPalette.atom_dark.text.with_alpha(170)) }, [text("LMB move target  //  RMB orbit warehouse  //  live 3D PGA")]),
						],
					),
				],
			),
			box({ style: |_| style.width(Grow({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })) }, []),
			Widget.badge(theme, if solution.reachable Success else Danger, if solution.reachable "TARGET LOCK" else "LIMIT"),
			box(
				{ style: |_| style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).background(BuiltinPalette.atom_dark.background.darken(8)).border({ color: BuiltinPalette.atom_dark.text.with_alpha(55), left: 1, right: 1, top: 1, bottom: 1 }).radius(9).pad(4, 4, 4, 4).gap(4).direction(Row).child_align({ x: Start, y: Center }) },
				[
					preset_button(False, "ASSEMBLY", SelectPose(AssemblyPose)),
					preset_button(False, "FOLDED", SelectPose(FoldedPose)),
					preset_button(True, "LONG REACH", SelectPose(LongReachPose)),
				],
			),
		],
	)
}

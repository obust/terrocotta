## The control panel emits only robot commands and has no app-shell knowledge.
import rr.Physics

import tc.Color
import tc.Element exposing [box, style]
import tc.Program exposing [View]
import tc.Theme
import tc.Widget

import ../scene/RobotKinematics
import ../scene/Robot
import ../scene/RobotKinematics
import ../scene/Drawing exposing [degrees]
import ../ui/Utils exposing [card, coefficient_readout, control, decimal, readout]

Inspector := [].{
	view : Theme, Robot.RobotState, RobotKinematics.Solution -> View(Robot.Msg)
	view = |theme, robot, solution| {
		target = robot.target.coords()
		state_color = if solution.reachable theme.palette.success.base.fill else theme.palette.danger.base.fill
		state_label = if solution.reachable "SOLVED" else "OUT OF REACH"
		box(
			{ style: |_| style.width(Fixed(380)).pad(theme.gap, theme.gap, theme.gap, theme.gap).gap(theme.gap).direction(Col).overflow(Hidden, Scroll).child_align({ x: Start, y: Start }) },
			[
				card(
					theme,
					"ARM CONFIGURATION",
					[
						control(theme, "upper link", robot.arm.upper_length, 60, 170, 1, |value| SetArm({ ..robot.arm, upper_length: value })),
						control(theme, "fore link", robot.arm.fore_length, 60, 170, 1, |value| SetArm({ ..robot.arm, fore_length: value })),
						Widget.checkbox(theme, robot.arm.elbow_up, "Elbow-up branch", |checked| SetArm({ ..robot.arm, elbow_up: checked })),
					],
				),
				card(
					theme,
					"TARGET / DRAG IN VIEWPORT",
					[
						control(theme, "X", target.x, -230, 230, 1, |value| SetTarget(Physics.point(value, target.y, target.z))),
						control(theme, "Y", target.y, 5, 285, 1, |value| SetTarget(Physics.point(target.x, value, target.z))),
						control(theme, "Z", target.z, -160, 160, 1, |value| SetTarget(Physics.point(target.x, target.y, value))),
						Widget.button(theme, Primary, "Random", [OnClick(RandomizeTarget)]),
					],
				),
				card(
					theme,
					"SOLVER STATUS",
					[
						readout(theme, "state", state_label, state_color),
						readout(theme, "tool error", "${decimal(solution.error, 2)} mm", state_color),
						readout(theme, "base yaw", "${decimal(degrees(solution.base_angle), 1)} deg", theme.palette.background.base.content),
						readout(theme, "shoulder", "${decimal(degrees(solution.shoulder_angle), 1)} deg", theme.palette.background.base.content),
						readout(theme, "elbow", "${decimal(degrees(solution.elbow_angle), 1)} deg", theme.palette.background.base.content),
					],
				),
			],
		)
	}
}

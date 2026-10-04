## The control panel emits only robot commands and has no app-shell knowledge.
import rr.Physics

import tc.Color
import tc.Element exposing [box, style]
import tc.Program exposing [View]
import tc.Theme
import tc.Widget

import Palette exposing [blue, cyan, green, ink, red]
import RobotArm
import RobotScene
import SceneDraw exposing [decimal, degrees]
import Ui exposing [card, coefficient_readout, content_stack, control, readout]

Inspector := [].{
	view : Theme, RobotScene.RobotState, RobotArm.Solution -> View(RobotScene.Msg)
	view = |theme, robot, solution| {
		target = robot.target.coords()
		state_color = if solution.reachable green else red
		state_label = if solution.reachable "SOLVED" else "OUT OF REACH"
		pga_section = if robot.show_pga pga_inspector(solution) else content_stack([])
		box(
			{ style: |_| style.width(Fixed(380)).height(Grow({ min: 0, max: 10000 })).gap(12).direction(Col).overflow(Hidden, Scroll).child_align({ x: Start, y: Start }) },
			[
				card("SOLVER STATUS", content_stack([
					readout("state", state_label, state_color), readout("tool error", "${decimal(solution.error)} mm", state_color), readout("base yaw", "${decimal(degrees(solution.base_angle))} deg", ink), readout("shoulder", "${decimal(degrees(solution.shoulder_angle))} deg", ink), readout("elbow", "${decimal(degrees(solution.elbow_angle))} deg", ink),
				])),
				card("TARGET / DRAG IN VIEWPORT", content_stack([
					control(theme, "X", target.x, -230, 230, 1, |value| SetTarget(Physics.point(value, target.y, target.z))),
					control(theme, "Y", target.y, 5, 285, 1, |value| SetTarget(Physics.point(target.x, value, target.z))),
					control(theme, "Z", target.z, -160, 160, 1, |value| SetTarget(Physics.point(target.x, target.y, value))),
				])),
				card("ARM CONFIGURATION", content_stack([
					control(theme, "upper link", robot.arm.upper_length, 60, 170, 1, |value| SetArm({ ..robot.arm, upper_length: value })),
					control(theme, "fore link", robot.arm.fore_length, 60, 170, 1, |value| SetArm({ ..robot.arm, fore_length: value })),
					Widget.checkbox(theme, robot.arm.elbow_up, "Elbow-up branch", |checked| SetArm({ ..robot.arm, elbow_up: checked })),
					Widget.checkbox(theme, robot.show_pga, "Show PGA construction", |checked| SetPgaVisible(checked)),
				])),
				pga_section,
			],
		)
	}

	pga_inspector = |solution| {
		target = solution.target.point_coeffs()
		upper = solution.upper_axis.line_coeffs()
		motor = solution.target_motor.motor_coeffs()
		plane = solution.ground.plane_coeffs()
		card("PGA LIVE COEFFICIENTS", content_stack([
			coefficient_readout("P target 032/013/021", "${decimal(target.e032)}  ${decimal(target.e013)}  ${decimal(target.e021)}", green),
			coefficient_readout("L upper 23/31/12", "${decimal(upper.e23)}  ${decimal(upper.e31)}  ${decimal(upper.e12)}", blue),
			coefficient_readout("T motor 01/02/03", "${decimal(motor.e01)}  ${decimal(motor.e02)}  ${decimal(motor.e03)}", cyan),
			coefficient_readout("plane 0/1/2/3", "${decimal(plane.e0)}  ${decimal(plane.e1)}  ${decimal(plane.e2)}  ${decimal(plane.e3)}", green),
		]))
	}
}

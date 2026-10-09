## Application-wide IDE theme.
import tc.Color
import tc.Theme

App := [].{
	## Seeded from the original IDE palette. The surface/text/primary
	## values are the most visible roles in Explorer and Topbar.
	theme = Theme.from_seed({
		background: 0x111318.Color,
		text: 0xd8dee9.Color,
		primary: 0x7aa2f7.Color,
		success: 0x9ece6a.Color,
		warning: 0xff9e64.Color,
		danger: 0xf7768e.Color,
	})
}

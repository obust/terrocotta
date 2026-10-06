## Shared building blocks for the tutorial shell and lesson pages.
import tc.Color
import tc.Element exposing [ElementId.*, box, style, text]
import tc.Program exposing [View]
import tc.Theme

Parts := [].{
	controls_shell : Theme, F32, List(View(msg)) -> View(msg)
	controls_shell = |theme, width, children| box(
		{
			style: |_| style
				.width(Fixed(width))
				.direction(Col)
				.gap(theme.gap)
				.pad(16, 16, 16, 16)
				.child_align({ x: Start, y: Start })
				.background(theme.palette.surface.subtle.fill)
				.border({ color: theme.palette.edge.border, left: 1, right: 0, top: 0, bottom: 0 })
				.overflow(Hidden, Scroll),
		},
		children,
	)

	## Styled, identified control group shared by the interactive lessons.
	controls_section : Theme, ElementId, List(View(msg)) -> View(msg)
	controls_section = |theme, id, children| box(
		{
			id,
			style: |_| style
				.width(Grow({}))
				.height(Fit({}))
				.direction(Col)
				.gap(theme.gap / 2)
				.pad(theme.gap, theme.gap, theme.gap, theme.gap)
				.child_align({ x: Start, y: Start })
				.background(theme.palette.surface.base.fill)
				.radius(theme.radius),
		},
		children,
	)

	## The ten-color sequence returned by seaborn's default `deep` palette.
	example_color : U64 -> Color
	example_color = |index| match index % 10 {
		0 => 0x4c72b0.Color
		1 => 0xdd8452.Color
		2 => 0x55a868.Color
		3 => 0xc44e52.Color
		4 => 0x8172b3.Color
		5 => 0x937860.Color
		6 => 0xda8bc3.Color
		7 => 0x8c8c8c.Color
		8 => 0xccb974.Color
		_ => 0x64b5cd.Color
	}

	transparent_example_fill : U64 -> Color
	transparent_example_fill = |index| Color.with_alpha(example_color(index), 0)

	title : Theme, Str -> View(msg)
	title = |theme, content| box(
		{ style: |_| style.width(Grow({})).height(Fit({})).font_size(24).font_color(theme.palette.primary.base.fill).child_align({ x: Start, y: Start }) },
		[text(content)],
	)

	heading : Theme, Str -> View(msg)
	heading = |theme, content| box(
		{ style: |_| style.width(Grow({})).height(Fit({})).font_size(20).font_color(theme.palette.primary.base.fill).child_align({ x: Start, y: Start }) },
		[text(content)],
	)

	copy : Str -> View(msg)
	copy = |content| box(
		{ style: |_| style.width(Grow({})).height(Fit({})).text_wrap(Words).child_align({ x: Start, y: Start }) },
		[text(content)],
	)

	## Render a compact inline code token, similar to Markdown backticks.
	code_text : Theme, Str -> View(msg)
	code_text = |theme, content| box(
		{
			style: |_| style
				.width(Fit({}))
				.height(Fit({}))
				.pad(theme.gap / 4, theme.gap / 2, theme.gap / 4, theme.gap / 2)
				.background(theme.palette.primary.weak.fill)
				.font_size(theme.font_size * 0.85)
				.font_color(theme.palette.primary.weak.content)
				.text_wrap(None)
				.child_align({ x: Start, y: Center })
				.radius(theme.radius),
		},
		[text(content)],
	)

}

## Shared colors for tutorial example boundaries and fills.
import tc.Color

ExampleColors := [].{
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
}

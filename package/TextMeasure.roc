## Public single-line text measurement API.
## The full Text layout module remains internal to the package.
import Text
import rr.Font

TextMeasure := [].{
	## Measure one rendered line with the canonical text metrics.
	measure_line : Str, { font_size : F32, spacing : F32 }, Font -> { width : F32, height : F32 }
	measure_line = |content, { font_size, spacing }, font| {
		Text.measure_line(
			content,
			{
				font_size,
				spacing,
				color: { r: 0, g: 0, b: 0, a: 255 },
				line_height: 0,
				align: Left,
				wrap: None,
			},
			font,
		)
	}
}

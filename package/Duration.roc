## Type-safe durations for frame timing and transitions.
##
## Static values use unit-qualified numerals and explicitly convert to
## `Duration`:
##
##     pause : Duration
##     pause = (5.Sec * 2).duration()
##
## Dynamic seconds, such as roc-ray's `Host.frame_time`, use
## `Duration.try_from_secs_f32`.
Duration := { seconds : F32 }.{

	## A numeral interpreted as seconds.
	Sec := { value : F32 }.{
		from_numeral : Numeral -> Try(Sec, [InvalidNumeral(Str)])
		from_numeral = |numeral| match F32.from_numeral(numeral) {
			Ok(value) => {
				if value < 0 or !value.is_finite() {
					Err(InvalidNumeral("duration must be finite and non-negative"))
				} else {
					Ok(Duration.Sec.{ value })
				}
			}
			Err(err) => Err(err)
		}

		## Scale seconds by a unitless, non-negative integer.
		times : Sec, U64 -> Sec
		times = |seconds, scale| {
			value = seconds.value * scale.to_f32()
			if value.is_finite() {
				Duration.Sec.{ value }
			} else {
				crash "Duration.Sec multiplication overflowed"
			}
		}

		## Convert unit-qualified seconds to a duration.
		duration : Sec -> Duration
		duration = |seconds| Duration.{ seconds: seconds.value }
	}

	## A numeral interpreted as milliseconds.
	Ms := { value : F32 }.{
		from_numeral : Numeral -> Try(Ms, [InvalidNumeral(Str)])
		from_numeral = |numeral| match F32.from_numeral(numeral) {
			Ok(value) => {
				if value < 0 or !value.is_finite() {
					Err(InvalidNumeral("duration must be finite and non-negative"))
				} else {
					Ok(Duration.Ms.{ value })
				}
			}
			Err(err) => Err(err)
		}

		## Scale milliseconds by a unitless, non-negative integer.
		times : Ms, U64 -> Ms
		times = |milliseconds, scale| {
			value = milliseconds.value * scale.to_f32()
			if value.is_finite() {
				Duration.Ms.{ value }
			} else {
				crash "Duration.Ms multiplication overflowed"
			}
		}

		## Convert unit-qualified milliseconds to a duration.
		duration : Ms -> Duration
		duration = |milliseconds| Duration.{ seconds: milliseconds.value / 1000 }
	}

	## Scale a duration by a unitless, non-negative integer.
	times : Duration, U64 -> Duration
	times = |duration, scale| {
		seconds = duration.seconds * scale.to_f32()
		if seconds.is_finite() {
			Duration.{ seconds }
		} else {
			crash "Duration multiplication overflowed"
		}
	}

	## A duration of zero time.
	zero : Duration
	zero = Duration.{ seconds: 0 }

	## Construct a duration from a whole number of seconds.
	from_secs : U64 -> Duration
	from_secs = |seconds| Duration.{ seconds: seconds.to_f32() }

	## Construct a duration from a whole number of milliseconds.
	from_millis : U64 -> Duration
	from_millis = |milliseconds| Duration.{ seconds: milliseconds.to_f32() / 1000 }

	## Try to construct a duration from dynamic fractional seconds.
	try_from_secs_f32 : F32 -> Try(Duration, [InvalidDuration(F32)])
	try_from_secs_f32 = |seconds| {
		if seconds < 0 or !seconds.is_finite() {
			Err(InvalidDuration(seconds))
		} else {
			Ok(Duration.{ seconds })
		}
	}

	## Return the total duration as fractional seconds.
	as_secs_f32 : Duration -> F32
	as_secs_f32 = |duration| duration.seconds

	## Return the total duration as fractional milliseconds.
	as_millis_f32 : Duration -> F32
	as_millis_f32 = |duration| duration.seconds * 1000

	## Return whether this duration spans no time.
	is_zero : Duration -> Bool
	is_zero = |duration| duration.seconds == 0

	## Return the absolute difference between two durations.
	abs_diff : Duration, Duration -> Duration
	abs_diff = |a, b| {
		if a.seconds >= b.seconds {
			Duration.{ seconds: a.seconds - b.seconds }
		} else {
			Duration.{ seconds: b.seconds - a.seconds }
		}
	}

	## Add two durations. Crashes if the F32 representation overflows.
	plus : Duration, Duration -> Duration
	plus = |a, b| {
		seconds = a.seconds + b.seconds
		if seconds.is_finite() {
			Duration.{ seconds }
		} else {
			crash "Duration addition overflowed"
		}
	}

	## Add two durations, returning None if the F32 representation overflows.
	checked_add : Duration, Duration -> [Some(Duration), None]
	checked_add = |a, b| {
		seconds = a.seconds + b.seconds
		if seconds.is_finite() {
			Some(Duration.{ seconds })
		} else {
			None
		}
	}

	## Subtract without permitting a negative duration.
	checked_sub : Duration, Duration -> [Some(Duration), None]
	checked_sub = |a, b| {
		if a.seconds >= b.seconds {
			Some(Duration.{ seconds: a.seconds - b.seconds })
		} else {
			None
		}
	}

	## Subtract, returning zero when the result would be negative.
	saturating_sub : Duration, Duration -> Duration
	saturating_sub = |a, b| {
		if a.seconds >= b.seconds {
			Duration.{ seconds: a.seconds - b.seconds }
		} else {
			Duration.zero
		}
	}

	## Multiply, returning None if the F32 representation overflows.
	checked_mul : Duration, U64 -> [Some(Duration), None]
	checked_mul = |duration, scale| {
		seconds = duration.seconds * scale.to_f32()
		if seconds.is_finite() {
			Some(Duration.{ seconds })
		} else {
			None
		}
	}

	## Divide by a unitless integer, returning None for zero.
	checked_div : Duration, U64 -> [Some(Duration), None]
	checked_div = |duration, divisor| {
		if divisor == 0 {
			None
		} else {
			Some(Duration.{ seconds: duration.seconds / divisor.to_f32() })
		}
	}

	is_eq : Duration, Duration -> Bool
	is_eq = |a, b| a.seconds == b.seconds

	is_lt : Duration, Duration -> Bool
	is_lt = |a, b| a.seconds < b.seconds

	is_lte : Duration, Duration -> Bool
	is_lte = |a, b| a.seconds <= b.seconds

	is_gt : Duration, Duration -> Bool
	is_gt = |a, b| a.seconds > b.seconds

	is_gte : Duration, Duration -> Bool
	is_gte = |a, b| a.seconds >= b.seconds
}

## Unit-qualified seconds scale before conversion to Duration.
expect {
	ten_seconds : Duration
	ten_seconds = (5.Sec * 2).duration()
	ten_seconds.as_secs_f32() == 10
}

## Unit-qualified milliseconds scale before conversion to Duration.
expect {
	three_hundred_ms : Duration
	three_hundred_ms = (150.Ms * 2).duration()
	three_hundred_ms.as_millis_f32() == 300
}

## Existing durations can be scaled by a unitless integer.
expect {
	base : Duration
	base = 2.Sec.duration()
	(base * 3).as_secs_f32() == 6
}

## Fractional unit-qualified seconds are supported.
expect {
	duration : Duration
	duration = 0.25.Sec.duration()
	duration.as_millis_f32() == 250
}

## Dynamic frame seconds are accepted.
expect {
	duration = Duration.try_from_secs_f32(0.016)?
	duration.as_millis_f32() == 16
}

## Negative dynamic seconds are rejected.
expect {
	match Duration.try_from_secs_f32(-0.5) {
		Err(InvalidDuration(value)) => value == -0.5
		Ok(_) => Bool.False
	}
}

## NaN dynamic seconds are rejected.
expect {
	match Duration.try_from_secs_f32(F32.nan) {
		Err(InvalidDuration(_)) => Bool.True
		Ok(_) => Bool.False
	}
}

## Infinite dynamic seconds are rejected.
expect {
	match Duration.try_from_secs_f32(F32.infinity) {
		Err(InvalidDuration(_)) => Bool.True
		Ok(_) => Bool.False
	}
}

## Zero construction and inspection agree.
expect Duration.zero.is_zero() and Duration.from_millis(0).is_zero()

## Whole-unit constructors convert to the shared seconds representation.
expect Duration.from_secs(2).as_millis_f32() == 2000 and Duration.from_millis(250).as_secs_f32() == 0.25

## Absolute difference is independent of operand order.
expect Duration.from_secs(5).abs_diff(Duration.from_secs(2)) == Duration.from_secs(2).abs_diff(Duration.from_secs(5))

## Checked subtraction rejects negative durations.
expect Duration.from_secs(2).checked_sub(Duration.from_secs(5)) == None

## Saturating subtraction returns zero for a negative result.
expect Duration.from_secs(2).saturating_sub(Duration.from_secs(5)).is_zero()

## Checked division rejects zero and preserves fractional results.
expect {
	duration = Duration.from_secs(1)
	duration.checked_div(0) == None and duration.checked_div(2) == Some(500.Ms.duration())
}

## Checked arithmetic reports representation overflow.
expect {
	highest = Duration.try_from_secs_f32(F32.highest)?
	highest.checked_add(highest) == None and highest.checked_mul(2) == None
}

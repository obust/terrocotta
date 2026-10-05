## The floor shader's GPU program and typed uniform bindings.
import rr.Draw

FloorMaterial := {
	shader : Draw.Shader,
	uniforms : {
		time : Draw.F32Uniform,
		target_uv : Draw.Vec2Uniform,
		reachable : Draw.F32Uniform,
		error_amount : Draw.F32Uniform,
	},
}.{

	Inputs : {
		seconds : F32,
		target_uv : { x : F32, y : F32 },
		reachable : Bool,
		error_amount : F32,
	}

	load! : Str => Try(FloorMaterial, [ShaderLoadFailed, UniformNotFound, ResourceLimit])
	load! = |fragment_source| {
		shader = Draw.Shader.from_source!({ vertex_source: "", fragment_source })?
		Ok({
			shader,
			uniforms: {
				time: shader.uniform_f32!("time")?,
				target_uv: shader.uniform_vec2!("targetUv")?,
				reachable: shader.uniform_f32!("reachable")?,
				error_amount: shader.uniform_f32!("errorAmount")?,
			},
		})
	}

	set! : FloorMaterial, Inputs => {}
	set! = |material, inputs| {
		material.uniforms.time.set!(inputs.seconds)
		material.uniforms.target_uv.set!(inputs.target_uv)
		material.uniforms.reachable.set!(if inputs.reachable 1 else 0)
		material.uniforms.error_amount.set!(inputs.error_amount)
	}
}

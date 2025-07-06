
#import bevy_pbr::mesh_functions
#import bevy_pbr::mesh_functions::get_world_from_local
#import bevy_pbr::mesh_functions::mesh_position_local_to_clip
//#import bevy_pbr::mesh_functions::{get_world_from_local, mesh_position_local_to_clip};
//#import bevy_pbr::forward_io::{Vertex,VertexOutput}
#import bevy_pbr::forward_io::Vertex

#import bevy_pbr::{
    pbr_fragment::pbr_input_from_standard_material,
    pbr_functions::alpha_discard,
  view_transformations::position_world_to_clip
}

#ifdef PREPASS_PIPELINE
#import bevy_pbr::{
    prepass_io::{VertexOutput, FragmentOutput},
    pbr_deferred_functions::deferred_output,
}
#else
#import bevy_pbr::{
    forward_io::{VertexOutput, FragmentOutput},
    pbr_functions::{apply_pbr_lighting, main_pass_post_lighting_processing},
}
#endif


struct TerrainMaterial {
    seed: f32,
    gradient_rotation: f32,
    offset: vec3<f32>,
    scale: f32,
    height: f32,
    lacunarity: f32,
    amplitude: f32,
    angular_variance: vec2<f32>,
    noise_rotation: f32,
    octave_count: u32,
    amplitude_decay: f32,
    frequency_variance: vec2<f32>,
}

@group(2) @binding(100)
var<uniform> terrain_material: TerrainMaterial;

/*
struct Vertex {
    @builtin(instance_index) instance_index: u32,
    @location(0) position: vec3<f32>,
    @location(1) blend_color: vec4<f32>,
};
*/

/*
struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) blend_color: vec4<f32>,
};
*/


const PI = 3.141592653589793238462;

// UE4's PseudoRandom function
// https://github.com/EpicGames/UnrealEngine/blob/release/Engine/Shaders/Private/Random.ush
fn pseudo(v: vec2<f32>) -> f32 {
    var out = fract(v / 128.) * 128. + vec2(-64.340622, -72.465622);

    return fract(dot(out.xyx * out.xyy, vec3(20.390625, 60.703125, 2.4281209)));
}


// Takes our xz positions and turns them into a random number between 0 and 1 using the above pseudo random function
fn HashPosition(pos: vec2<f32>) -> f32 {

    return pseudo(pos * vec2<f32>(terrain_material.seed, terrain_material.seed + 4.0));
}

// Generates a random gradient vector for the perlin noise lattice points, watch my perlin noise video for a more in depth explanation
fn RandVector(seed: f32) -> vec2<f32> {
    var theta = seed * 360.0 * 2.0 - 360.0;
    theta += terrain_material.gradient_rotation;
    theta = theta * PI / 180.0;
    return normalize(vec2(cos(theta), sin(theta)));
}

// Normal smoothstep is cubic -- to avoid discontinuities in the gradient, we use a quintic interpolation instead as explained in my perlin noise video
fn quinticInterpolation(t: vec2<f32>) -> vec2<f32> {
    return t * t * t * (t * (t * vec2(6.0) - vec2(15.0)) + vec2(10.0));
}

// Derivative of above function
fn quinticDerivative(t: vec2<f32>) -> vec2<f32> {
    return vec2(30.0) * t * t * (t * (t - vec2(2.0)) + vec2(1.0));
}

// it's perlin noise that returns the noise in the x component and the derivatives in the yz components as explained in my perlin noise video
fn perlin_noise2D(pos: vec2<f32>) -> vec3<f32> {
    var latticeMin = floor(pos);
    var latticeMax = ceil(pos);

    var remainder = fract(pos);

    // Lattice Corners
    var c00 = latticeMin;
    var c10 = vec2(latticeMax.x, latticeMin.y);
    var c01 = vec2(latticeMin.x, latticeMax.y);
    var c11 = latticeMax;

    // Gradient Vectors assigned to each corner
    var g00 = RandVector(HashPosition(c00));
    var g10 = RandVector(HashPosition(c10));
    var g01 = RandVector(HashPosition(c01));
    var g11 = RandVector(HashPosition(c11));

    // Directions to position from lattice corners
    var p0 = remainder;
    var p1 = p0 - vec2(1.0);

    var p00 = p0;
    var p10 = vec2(p1.x, p0.y);
    var p01 = vec2(p0.x, p1.y);
    var p11 = p1;

    var u = quinticInterpolation(remainder);
    var du = quinticDerivative(remainder);

    var a = dot(g00, p00);
    var b = dot(g10, p10);
    var c = dot(g01, p01);
    var d = dot(g11, p11);

    // Expanded interpolation freaks of nature from https://iquilezles.org/articles/gradientnoise/
    var noise = a + u.x * (b - a) + u.y * (c - a) + u.x * u.y * (a - b - c + d);

    var gradient = g00 + u.x * (g10 - g00) + u.y * (g01 - g00) + u.x * u.y * (g00 - g10 - g01 + g11) + du * (u.yx * (a - b - c + d) + vec2(b, c) - a);
    return vec3(noise, gradient);
}

// The fractional brownian motion that sums many noise values as explained in the video accompanying this project
fn fbm(pos_: vec2<f32>) -> vec3<f32> {
    var pos = pos_;
    var lacunarity = terrain_material.lacunarity;
    var amplitude = terrain_material.amplitude;

    // height sum
    var height = 0.0;

    // derivative sum
    var grad = vec2(0.0);

    // accumulated rotations
    var m = mat2x2<f32>(1.0, 0.0, 0.0, 1.0);

			// generate random angle variance if applicable
    var angle_variance = mix(terrain_material.angular_variance.x, terrain_material.angular_variance.y, HashPosition(vec2(terrain_material.seed, 827.0)));
    var theta = (terrain_material.noise_rotation + angle_variance) * PI / 180.0;

			// rotation matrix
    var m2 = mat2x2<f32>(cos(theta), -sin(theta), sin(theta), cos(theta));

    var m2i = inverse_mat2x2(m2);

    for (var i: u32 = u32(0); i < terrain_material.octave_count; i++) {
        var n = perlin_noise2D(pos);
				
				// add height scaled by current amplitude
        height += amplitude * n.x;	
				
				// add gradient scaled by amplitude and transformed by accumulated rotations
        grad += amplitude * m * n.yz;
				
				// apply amplitude decay to reduce impact of next noise layer
        amplitude *= terrain_material.amplitude_decay;
				
				// generate random angle variance if applicable
        angle_variance = mix(terrain_material.angular_variance.x, terrain_material.angular_variance.y, HashPosition(vec2(f32(i) * 419.0, terrain_material.seed)));
        theta = (terrain_material.noise_rotation + angle_variance) * PI / 180.0;

				// reconstruct rotation matrix, kind of a performance stink since this is technically expensive and doesn't need to be done if no random angle variance but whatever it's 2025
        m2 = mat2x2(cos(theta), -sin(theta),
            sin(theta), cos(theta));

        m2i = inverse_mat2x2(m2);

				// generate frequency variance if applicable
        var freq_variance = mix(terrain_material.frequency_variance.x, terrain_material.frequency_variance.y, HashPosition(vec2(f32(i) * 422.0, terrain_material.seed)));

				// apply frequency adjustment to sample position for next noise layer
        pos = (lacunarity + freq_variance) * m2 * pos;
        m = (lacunarity + freq_variance) * m2i * m;
    }

    return vec3(height, grad);
}


fn inverse_mat2x2(matrix: mat2x2<f32>) -> mat2x2<f32> {
    let a = matrix[0].x;
    let b = matrix[0].y;
    let c = matrix[1].x;
    let d = matrix[1].y;

    let determinant = a * d - b * c;

    if determinant == 0.0 {
        // Handle singular matrix (no inverse)
        return mat2x2(0.0, 0.0, 0.0, 0.0); // Or return some other error indicator
    }

    let inv_determinant = 1.0 / determinant;

    return mat2x2(
        d * inv_determinant, -b * inv_determinant,
        -c * inv_determinant, a * inv_determinant
    );
}


fn vertex_simple(vertex: Vertex) -> VertexOutput {
    var out: VertexOutput;
    out.position = mesh_position_local_to_clip(
        get_world_from_local(vertex.instance_index),
        vec4<f32>(vertex.position, 1.0),
    );
#ifdef VERTEX_COLOR
    out.color = vertex.color;
#endif
    return out;
}


  @vertex
fn vertex(vertex: Vertex) -> VertexOutput {


    var out: VertexOutput;

    let mesh_world_from_local = mesh_functions::get_world_from_local(vertex.instance_index);
    var world_from_local = mesh_world_from_local;

#ifdef VERTEX_NORMALS
    out.world_normal = mesh_functions::mesh_normal_local_to_world(
        vertex.normal,
        vertex.instance_index
    );
#endif
    var pos: vec3<f32> = vertex.position.xyz;
    //var noise_pos = (pos + terrain_material.offset);
    var noise_pos = (pos + terrain_material.offset) / terrain_material.scale;
    var n = fbm(noise_pos.xz);
    //var n = HashPosition(noise_pos.xy);

    pos.y += (n.x * terrain_material.height + terrain_material.height - terrain_material.offset.y) / terrain_material.scale;

    out.world_position = mesh_functions::mesh_position_local_to_world(world_from_local, vec4<f32>(pos, 1.0));
    out.position = position_world_to_clip(out.world_position.xyz);

#ifdef VERTEX_UVS_A
    out.uv = vertex.uv;
#endif
#ifdef VERTEX_UVS_B
    out.uv_b = vertex.uv_b;
#endif

#ifdef VERTEX_TANGENTS
    out.world_tangent = mesh_functions::mesh_tangent_local_to_world(
        world_from_local,
        vertex.tangent,
        // Use vertex_no_morph.instance_index instead of vertex.instance_index to work around a wgpu dx12 bug.
        // See https://github.com/gfx-rs/naga/issues/2416
        vertex.instance_index
    );
#endif

#ifdef VERTEX_COLOR
    out.color = vertex.color;
#endif

#ifdef VERTEX_OUTPUT_INSTANCE_INDEX
    // Use vertex_no_morph.instance_index instead of vertex.instance_index to work around a wgpu dx12 bug.
    // See https://github.com/gfx-rs/naga/issues/2416
    out.instance_index = vertex.instance_index;
#endif

#ifdef VISIBILITY_RANGE_DITHER
    out.visibility_range_dither = mesh_functions::get_visibility_range_dither_level(
        vertex.instance_index, mesh_world_from_local[3]
    );
#endif

    return out;
}

/*
struct FragmentInput {
    @location(0) blend_color: vec4<f32>,
};
*/

@fragment
fn fragment(in: VertexOutput,
    @builtin(front_facing) is_front: bool) -> FragmentOutput {
    // generate a PbrInput struct from the StandardMaterial bindings
    var pbr_input = pbr_input_from_standard_material(in, is_front);

    var pos: vec3<f32> = in.world_position.xyz;

    //var n = perlin_noise2D(pos.xz);

    //var base_color: vec4<f32> = mix(pbr_input.material.base_color, vec4(n, 1), 0.75);

    var base_color: vec4<f32> = pbr_input.material.base_color;
    // alpha discard
    pbr_input.material.base_color = alpha_discard(pbr_input.material, base_color);

#ifdef PREPASS_PIPELINE
    // in deferred mode we can't modify anything after that, as lighting is run in a separate fullscreen shader.
    let out = deferred_output(in, pbr_input);
#else
    var out: FragmentOutput;
    // apply lighting
    out.color = apply_pbr_lighting(pbr_input);
    // apply in-shader post processing (fog, alpha-premultiply, and also tonemapping, debanding if the camera is non-hdr)
    // note this does not include fullscreen postprocessing effects like bloom.
    out.color = main_pass_post_lighting_processing(pbr_input, out.color);
    var noise_pos = (pos + terrain_material.offset) / terrain_material.scale;
    var n = perlin_noise2D(noise_pos.xy);

    out.color = out.color * vec4(n, 1.0);
#endif

    return out;
}

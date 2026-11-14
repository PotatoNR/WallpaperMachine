// Dot argument conversions measured in Wallpaper Engine 2.8.0.42.
mod support;

use support::*;
use wm_shader::dialect::{ConvertOptions, convert_stage, convert_stage_with};
use wm_shader::StageKind;

#[test]
fn dot_accepts_mixed_vector_widths_and_scalar_arguments() {
    for expression in [
        "dot(color, weights)",
        "dot(weights, color)",
        "dot(color, weights.xy)",
        "dot(weights, 0.25)",
        "dot(0.25, weights)",
        "dot(0.25, 0.5)",
        "dot(int3(1, 2, 3), weights.xy)",
        "dot(1.0 - pow(color * 0.995, 2.2), weights)",
    ] {
        program_ok(&format!(
            "uniform vec4 color; uniform vec3 weights;
             void main() {{ float value = {expression}; gl_FragColor = CAST4(value); }}"
        ));
    }
}

#[test]
fn dot_uses_leading_components_broadcasts_scalars_and_evaluates_arguments_once() {
    let source = format!("{KERNEL_HEAD}
        int calls = 0;
        vec4 next_color() {{ calls++; return vec4(data[0], data[1], data[2], data[3]); }}
        void main() {{
            vec4 color = vec4(data[0], data[1], data[2], data[3]);
            vec3 weights = vec3(0.5, 0.25, 0.125);
            data[8] = dot(color, weights);
            data[9] = dot(weights, color);
            data[10] = dot(color, weights.xy);
            data[11] = dot(0.25, color.xyz);
            data[12] = dot(color.xyz, 0.25);
            data[13] = dot(data[0], data[1]);
            data[14] = dot(int3(1, 2, 99), weights.xy);
            data[15] = dot(next_color(), weights);
            data[16] = calls;
            data[17] = dot(int2(1, 2), int3(2, 3, 99));
        }}");
    let code = kernel(&source);
    let Some(out) = gpu_run(&code, &[0.2, 0.3, 0.4, 99.0]) else { return };
    for (index, expected) in [
        (8, 0.225), (9, 0.225), (10, 0.175), (11, 0.225), (12, 0.225),
        (13, 0.06), (14, 1.0), (15, 0.225), (16, 1.0), (17, 8.0),
    ] {
        assert!((out[index] - expected).abs() < 0.00001, "slot {index}: {} != {expected}", out[index]);
    }
}

#[test]
fn an_authored_dot_overload_keeps_its_own_behavior() {
    let source = format!("{KERNEL_HEAD}
        float dot(float a, float b) {{ return a + b; }}
        void main() {{ data[8] = dot(data[0], data[1]); }}");
    let code = kernel(&source);
    let Some(out) = gpu_run(&code, &[0.2, 0.3]) else { return };
    assert!((out[8] - 0.5).abs() < 0.00001);
}

#[test]
fn converted_dot_arguments_reconvert_unchanged() {
    let first = convert_stage(StageKind::Fragment,
        "uniform vec4 color; uniform vec3 weights;
         void main() { gl_FragColor = CAST4(dot(color, weights) + dot(0.25, weights)); }").unwrap();
    let second = convert_stage_with(StageKind::Fragment, &first.text,
        ConvertOptions { glsl_builtins: true, ..Default::default() }).unwrap();
    assert_eq!(first.text, second.text);
}

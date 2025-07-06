use std::f32::consts::TAU;

use bevy::{
    asset::RenderAssetUsages,
    color::palettes::css::POWDER_BLUE,
    pbr::{
        ExtendedMaterial, MaterialExtension,
        wireframe::{Wireframe, WireframePlugin},
    },
    prelude::*,
    render::{
        RenderPlugin,
        mesh::{Indices, MeshAabb, PrimitiveTopology},
        render_resource::{AsBindGroup, ShaderRef},
        settings::{RenderCreation, WgpuFeatures, WgpuSettings},
    },
    window::PrimaryWindow,
};
use bevy_inspector_egui::{
    DefaultInspectorConfigPlugin,
    bevy_egui::{EguiContextSettings, EguiPlugin},
    quick::{AssetInspectorPlugin, WorldInspectorPlugin},
};
use bevy_panorbit_camera::{EguiFocusIncludesHover, PanOrbitCamera, PanOrbitCameraPlugin};

fn main() {
    App::new()
        .register_type::<PanOrbitCamera>()
        .register_asset_reflect::<ExtendedMaterial<StandardMaterial, TerrainMaterial>>()
        .add_plugins((
            DefaultPlugins.set(RenderPlugin {
                render_creation: RenderCreation::Automatic(WgpuSettings {
                    // WARN this is a native only feature. It will not work with webgl or webgpu
                    features: WgpuFeatures::POLYGON_MODE_LINE,
                    ..default()
                }),
                ..default()
            }),
            // You need to add this plugin to enable wireframe rendering
            WireframePlugin::default(),
        ))
        .add_plugins(MaterialPlugin::<
            ExtendedMaterial<StandardMaterial, TerrainMaterial>,
        >::default())
        .add_plugins(EguiPlugin {
            enable_multipass_for_primary_context: true,
        })
        .add_plugins(DefaultInspectorConfigPlugin)
        .add_plugins(WorldInspectorPlugin::new())
        .add_plugins(AssetInspectorPlugin::<
            ExtendedMaterial<StandardMaterial, TerrainMaterial>,
        >::default())
        .add_plugins(PanOrbitCameraPlugin)
        .add_systems(Startup, update_ui_scale_factor)
        .add_systems(Startup, setup)
        .add_systems(Update, input_handler)
        .insert_resource(EguiFocusIncludesHover(true))
        .run();
}

fn input_handler(keyboard_input: Res<ButtonInput<KeyCode>>, mut exit: EventWriter<AppExit>) {
    if keyboard_input.just_released(KeyCode::Escape) {
        exit.write(AppExit::Success);
    }
}

fn update_ui_scale_factor(
    mut windows: Query<(&mut EguiContextSettings, &Window), With<PrimaryWindow>>,
) {
    if let Ok((mut egui_settings, window)) = windows.single_mut() {
        egui_settings.scale_factor = 2.0 / window.scale_factor();
    }
}

fn setup(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut terrain_materials: ResMut<Assets<ExtendedMaterial<StandardMaterial, TerrainMaterial>>>,
) {
    let mut pos = Vec::new();
    let side_length: i16 = 10;
    let mesh_scale = 2.0;

    let half_length = (f32::from(side_length) - 1.0) / 2.0;

    // rust is a little more fussy with numeric conversions
    for x in 0..side_length {
        for z in 0..side_length {
            let xz = Vec2::new(f32::from(x) - half_length, f32::from(z) - half_length) * mesh_scale;
            let xyz = Vec3::new(xz.x, 0.0, xz.y);
            pos.push(xyz);
        }
    }

    let mut index_buffer = Vec::new();
    // FIXME: I really don't like the name side_length its really the number of edges to
    // sub-divided the square into
    for row in (0..(side_length * side_length - side_length)).step_by(side_length as usize) {
        for i in 0..side_length - 1 {
            let v = i as u32 + row as u32; // offset to row

            let v0 = v;
            let v1 = v + side_length as u32;
            let v2 = v + side_length as u32 + 1;
            let v3 = v + 1;

            // clockwise winding order
            // index_buffer.append(&mut vec![v0, v1, v3, v1, v2, v3]);

            index_buffer.append(&mut vec![v3, v1, v0, v3, v2, v1]);
        }
    }

    /* TODO: put this behind a debug flag or something
    println!("number of verices: {}", pos.len());
    for (k, v) in pos.iter().enumerate() {
        println!("i: {}, vertex: {:?}", k, v)
    }
    println!("index buffer:  {:?}", index_buffer);
    */

    // keep the mesh around in the asset server in both render world and main world
    let mesh = Mesh::new(
        PrimitiveTopology::TriangleList,
        RenderAssetUsages::RENDER_WORLD | RenderAssetUsages::MAIN_WORLD,
    )
    .with_inserted_attribute(Mesh::ATTRIBUTE_POSITION, pos)
    .with_inserted_indices(Indices::U32(index_buffer))
    .with_computed_normals();

    mesh.compute_aabb();

    commands.spawn((
        Name::new("Terrain"),
        Wireframe,
        Mesh3d(meshes.add(mesh)),
        MeshMaterial3d(terrain_materials.add(ExtendedMaterial {
            base: StandardMaterial {
                base_color: POWDER_BLUE.into(),
                ..Default::default()
            },
            extension: TerrainMaterial {
                seed: 0f32,
                gradient_rotation: 0f32,
                scale: 500f32,
                ..Default::default()
            },
        })),
    ));

    commands.spawn((
        Name::new("Sphere"),
        Wireframe,
        Mesh3d(meshes.add(Sphere::new(2.0))),
        MeshMaterial3d(materials.add(StandardMaterial {
            base_color: POWDER_BLUE.into(),
            ..Default::default()
        })),
    ));

    // light
    commands.spawn((
        DirectionalLight::default(),
        Transform::from_xyz(1.0, 1.0, 1.0).looking_at(Vec3::ZERO, Vec3::Y),
    ));

    // camera
    commands.spawn((
        //Camera3d::default(),
        PanOrbitCamera {
            //axis: [Vec3::X, Vec3::Z, Vec3::Y],
            //focus: Vec3::new(0.0, 1.0, 0.0),

            // Set limits on rotation and zoom
            yaw_upper_limit: Some(TAU / 4.0),
            yaw_lower_limit: Some(-TAU / 4.0),
            pitch_upper_limit: Some(TAU / 3.0),
            pitch_lower_limit: Some(-TAU / 3.0),
            zoom_upper_limit: Some(20.0),
            zoom_lower_limit: 1.0,

            // Change the controls (these match Blender)
            //button_orbit: MouseButton::Middle,
            //button_pan: MouseButton::Middle,
            modifier_pan: Some(KeyCode::ShiftLeft),

            //orbit_sensitivity: 0.1,
            //pitch: Some(-45f32.to_radians()),
            //pan_sensitivity: 0.1,
            zoom_sensitivity: 0.1,
            allow_upside_down: true,
            touch_enabled: true,
            ..Default::default()
        },
        Transform::from_translation(Vec3::new(-20.0, 11.0, 0.0)), //Transform::from_xyz(-16.0, 11.0, 0.0).looking_at(Vec3::ZERO, Vec3::Y),
    ));
}

#[derive(Asset, Reflect, AsBindGroup, Clone, Default)]
struct TerrainMaterial {
    #[uniform(100)]
    seed: f32,
    #[uniform(100)]
    gradient_rotation: f32,
    #[uniform(100)]
    offset: Vec3,
    #[uniform(100)]
    scale: f32,
    #[uniform(100)]
    height: f32,
}

const TERRAIN_SHADER_ASSET_PATH: &str = "shaders/terrain.wgsl";

impl MaterialExtension for TerrainMaterial {
    fn vertex_shader() -> ShaderRef {
        TERRAIN_SHADER_ASSET_PATH.into()
    }

    fn fragment_shader() -> ShaderRef {
        TERRAIN_SHADER_ASSET_PATH.into()
    }
}

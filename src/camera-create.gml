vhr_theatre_boot();
vhr_active=false;vhr_last_error=0;vhr_body_yaw=0;
vhr_hud_surface=-1;vhr_chase_surface=-1;
vhr_body_x=0;vhr_body_y=0;vhr_body_z=0;
vhr_eye_views=array_create(4,matrix_build_identity());
vhr_eye_projections=array_create(4,matrix_build_identity());
vertex_format_begin();vertex_format_add_position_3d();vertex_format_add_colour();vertex_format_add_texcoord();
vhr_format=vertex_format_end();vhr_mesh=-1;
// Cockpit mesh: vhr_build_cockpit (cockpit-build.gml). Accents start in the classic purple/teal and
// switch to the player's car paint once the race car is known (vhr_cockpit_paint_update in the Step event).
vhr_paint_key="";
vhr_build_cockpit(-1);
show_debug_message("VHRVR: chassis cockpit v0.2 ready. F7 switches cockpit/chase in VR.");

vhr_steer_angle=0;
vhr_sky_mesh=-1;vhr_sky_key="";
vhr_driver_sprite=vhr_load_driver_art();
vhr_wheel_mesh=vertex_create_buffer();
vhr_arm_mesh=vertex_create_buffer();
vhr_build_driver();
vhr_crystal_mesh=vertex_create_buffer();vertex_begin(vhr_crystal_mesh,vhr_format);
vhr_crystal(vhr_crystal_mesh,2.5,7,-4.5,2.8,2.2,0.85);
vhr_crystal(vhr_crystal_mesh,2,7,-9,1.1,1.1,1.2);
vertex_end(vhr_crystal_mesh);vertex_freeze(vhr_crystal_mesh);


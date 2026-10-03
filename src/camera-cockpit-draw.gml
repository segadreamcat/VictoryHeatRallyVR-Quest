if(vhr_active && (view_current==view || (global.vhr_enabled && view_current==1))) {
    var _previous_world=matrix_get(matrix_world);
    shader_reset();gpu_set_fog(false,c_white,0,0);gpu_set_cullmode(cull_noculling);
    gpu_set_ztestenable(true);gpu_set_zwriteenable(true);
    var _cam=view_camera[view_current];
    camera_set_view_mat(_cam,vhr_eye_views[view_current]);camera_set_proj_mat(_cam,vhr_eye_projections[view_current]);camera_apply(_cam);
    // camera_apply handles the application surface's vertical orientation.
    // Writing the raw projection afterward bypasses that adjustment.
    matrix_set(matrix_world,matrix_build(vhr_body_x,vhr_body_y,vhr_body_z,0,0,vhr_body_yaw,1,1,1));
    vertex_submit(vhr_mesh,pr_trianglelist,-1);
    var _wheel_local=matrix_build(7.5,-4,-12,0,0,0,1,1,1);
    // Positive joystick input moves the top of the wheel toward +Y (right).
    var _wc=dcos(vhr_steer_angle),_ws=dsin(vhr_steer_angle);
    _wheel_local[5]=_wc;_wheel_local[6]=_ws;
    _wheel_local[9]=-_ws;_wheel_local[10]=_wc;
    var _chassis=matrix_build(vhr_body_x,vhr_body_y,vhr_body_z,0,0,vhr_body_yaw,1,1,1);
    matrix_set(matrix_world,matrix_multiply(_wheel_local,_chassis));
    gpu_set_alphatestenable(true);gpu_set_alphatestref(128);gpu_set_texfilter(false);
    vertex_submit(vhr_wheel_mesh,pr_trianglelist,sprite_get_texture(vhr_driver_sprite,0));
    matrix_set(matrix_world,_chassis);
    vertex_submit(vhr_arm_mesh,pr_trianglelist,sprite_get_texture(vhr_driver_sprite,0));
    gpu_set_alphatestenable(false);
        if(global.vhr_enabled && global.vhr_mirror_ready && surface_exists(global.vhr_mirror_surface)) {
        matrix_set(matrix_world,matrix_multiply(vhr_display_matrix(9,0,-27,0.015625),_chassis));
        draw_surface_ext(global.vhr_mirror_surface,512,0,-1,1,0,c_white,1);
        matrix_set(matrix_world,_chassis);
    }
    gpu_set_zwriteenable(false);
    vertex_submit(vhr_crystal_mesh,pr_trianglelist,-1);
    gpu_set_zwriteenable(true);
    matrix_set(matrix_world,_previous_world);
    draw_set_colour(c_white);
    if(obj_track.fog_enabled) gpu_set_fog(true,fog_color,fog_start,fog_end);
}

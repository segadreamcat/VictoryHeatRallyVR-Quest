function vhr_draw_chase_hud() {
    if(view_current>1 || !instance_exists(target)) return;
    var _c=obj_main.camera[view_current];
    if(!instance_exists(_c) || _c.target!=target) return;
    if(!surface_exists(_c.vhr_chase_surface)) _c.vhr_chase_surface=surface_create(512,288);
    if(!surface_exists(_c.vhr_chase_surface)) return;
    var _world=matrix_get(matrix_world);
    if(view_current==0) {
        surface_set_target(_c.vhr_chase_surface);
        shader_reset();matrix_set(matrix_world,matrix_build_identity());
        gpu_set_ztestenable(false);gpu_set_zwriteenable(false);
        d3d_set_projection_ortho(0,0,512,288,0);draw_clear_alpha(c_black,0);
        vhr_stock_hud();vhr_stock_map();surface_reset_target();
    }
    var _eye=view_camera[view_current];
    camera_set_view_mat(_eye,_c.vhr_eye_views[view_current]);
    camera_set_proj_mat(_eye,_c.vhr_eye_projections[view_current]);camera_apply(_eye);
    shader_reset();gpu_set_fog(false,c_white,0,0);gpu_set_cullmode(cull_noculling);
    gpu_set_ztestenable(false);gpu_set_zwriteenable(false);
    var _base=matrix_build(_c.cam.x,_c.cam.y,_c.cam.z,-_c.cam.roll,_c.cam.pitch,_c.cam.yaw,1,1,1);
    matrix_set(matrix_world,matrix_multiply(vhr_display_matrix(160,-64,-36,0.25),_base));
    draw_surface(_c.vhr_chase_surface,0,0);
    matrix_set(matrix_world,_world);gpu_set_ztestenable(true);gpu_set_zwriteenable(true);
    draw_set_colour(c_white);draw_set_alpha(1);
}


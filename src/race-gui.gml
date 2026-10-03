// GUI events run once per frame, including their animation and sound logic.
// Capture once, then project the same panel into both eye halves at six meters.
function vhr_race_gui(_draw) {
    if(!variable_global_exists("vhr_enabled") || !global.vhr_enabled) {_draw();return;}
    var _world=matrix_get(matrix_world),_view=matrix_get(matrix_view),_proj=matrix_get(matrix_projection);
    var _surf=surface_create(512,288);
    if(!surface_exists(_surf)) return;
    surface_set_target(_surf);
    shader_reset();matrix_set(matrix_world,matrix_build_identity());
    gpu_set_ztestenable(false);gpu_set_zwriteenable(false);gpu_set_alphatestenable(false);
    d3d_set_projection_ortho(0,0,512,288,0);draw_clear_alpha(c_black,0);
    _draw();
    surface_reset_target();
    shader_reset();matrix_set(matrix_world,matrix_build_identity());
    d3d_set_projection_ortho(0,0,512,288,0);
    gpu_set_ztestenable(false);gpu_set_zwriteenable(false);gpu_set_alphatestenable(false);
    draw_set_colour(c_white);draw_set_alpha(1);
    for(var _eye=0;_eye<2;_eye++) {
        var _l=external_call(global.vhr_value,_eye,20),_r=external_call(global.vhr_value,_eye,21);
        var _t=external_call(global.vhr_value,_eye,22),_b=external_call(global.vhr_value,_eye,23);
        if(_r<=_l || _b<=_t) continue;
        var _offset=external_call(global.vhr_value,_eye,30);
        var _left=_eye*256+256*((-1.4-_offset)/6-_l)/(_r-_l);
        var _right=_eye*256+256*((1.4-_offset)/6-_l)/(_r-_l);
        var _top=288*((-0.7875/6)-_t)/(_b-_t);
        var _bottom=288*((0.7875/6)-_t)/(_b-_t);
        draw_surface_stretched(_surf,_left,_top,_right-_left,_bottom-_top);
    }
    surface_free(_surf);
    matrix_set(matrix_world,_world);matrix_set(matrix_view,_view);matrix_set(matrix_projection,_proj);
    gpu_set_ztestenable(true);gpu_set_zwriteenable(true);
}


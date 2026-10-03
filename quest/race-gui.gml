// Quest: race overlays (countdown, lap counter, pause menu, continue screen, ...) are 2D GUI art.
// In VR they go on a panel fixed six meters ahead of you, painted into both eye images.
// vhr_gui_panel paints a captured 512x288 GUI image into both eye halves of the application surface.
function vhr_gui_panel(_surf) {
    if(!surface_exists(_surf) || !surface_exists(application_surface)) return;
    var _world=matrix_get(matrix_world),_view=matrix_get(matrix_view),_proj=matrix_get(matrix_projection);
    surface_set_target(application_surface);
    shader_reset();matrix_set(matrix_world,matrix_build_identity());
    // 512x288 GUI units span the whole side-by-side surface, 256 units per eye.
    d3d_set_projection_ortho(0,0,512,288,0);
    gpu_set_ztestenable(false);gpu_set_zwriteenable(false);gpu_set_alphatestenable(false);
    gpu_set_blendmode(bm_normal);draw_set_colour(c_white);draw_set_alpha(1);
    for(var _eye=0;_eye<2;_eye++) {
        // Tangents of the frustum this eye image actually covers.
        var _l=vhrq_value(_eye,24),_r=vhrq_value(_eye,25);
        var _t=vhrq_value(_eye,26),_b=vhrq_value(_eye,27);
        if(_r<=_l || _b<=_t) continue;
        var _offset=vhrq_value(_eye,30);
        var _left=_eye*256+256*((-1.4-_offset)/6-_l)/(_r-_l);
        var _right=_eye*256+256*((1.4-_offset)/6-_l)/(_r-_l);
        var _top=288*((-0.7875/6)-_t)/(_b-_t);
        var _bottom=288*((0.7875/6)-_t)/(_b-_t);
        draw_surface_stretched(_surf,_left,_top,_right-_left,_bottom-_top);
    }
    surface_reset_target();
    matrix_set(matrix_world,_world);matrix_set(matrix_view,_view);matrix_set(matrix_projection,_proj);
    gpu_set_ztestenable(true);gpu_set_zwriteenable(true);
}
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
    matrix_set(matrix_world,_world);matrix_set(matrix_view,_view);matrix_set(matrix_projection,_proj);
    vhr_gui_panel(_surf);
    surface_free(_surf);
}
// Everything else drawn in Draw GUI events while racing in VR (deferred shadow/outline text, the
// continue countdown and screen, messages, ...) would go to the phone-style window the headset never
// shows. Each of those events is wrapped (vhr_gui_event) so it draws into a shared 512x288 image for
// this frame; obj_vhrq's Draw GUI End puts it on the panel. Every wrapper sets and resets its own
// render target inside its own event, so a room change or deactivation mid-frame can never leave
// the surface stack unbalanced.
function vhr_gui_event(_draw) {
    if(!variable_global_exists("vhr_enabled") || !global.vhr_enabled) {_draw();return;}
    var _frame=variable_global_exists("vhrq_frame_no") ? global.vhrq_frame_no : 0;
    if(!variable_global_exists("vhr_gui_surf") || !surface_exists(global.vhr_gui_surf)) {global.vhr_gui_surf=surface_create(512,288);global.vhr_gui_frame=-1;}
    if(!surface_exists(global.vhr_gui_surf)) return;
    var _world=matrix_get(matrix_world),_view=matrix_get(matrix_view),_proj=matrix_get(matrix_projection);
    surface_set_target(global.vhr_gui_surf);
    if(global.vhr_gui_frame!=_frame) {draw_clear_alpha(c_black,0);global.vhr_gui_frame=_frame;}
    shader_reset();matrix_set(matrix_world,matrix_build_identity());
    gpu_set_ztestenable(false);gpu_set_zwriteenable(false);
    d3d_set_projection_ortho(0,0,512,288,0);
    _draw();
    surface_reset_target();
    matrix_set(matrix_world,_world);matrix_set(matrix_view,_view);matrix_set(matrix_projection,_proj);
}
// obj_vhrq Draw GUI End: this frame's Draw-event overlays, then its GUI image, onto the panel.
function vhr_gui_compose() {
    if(!variable_global_exists("vhr_enabled") || !global.vhr_enabled) return;
    var _frame=variable_global_exists("vhrq_frame_no") ? global.vhrq_frame_no : 0;
    if(variable_global_exists("vhr_ov_surf") && surface_exists(global.vhr_ov_surf) && global.vhr_ov_frame==_frame) vhr_gui_panel(global.vhr_ov_surf);
    if(variable_global_exists("vhr_gui_surf") && surface_exists(global.vhr_gui_surf) && global.vhr_gui_frame==_frame) vhr_gui_panel(global.vhr_gui_surf);
}
// 2D overlays the game draws in its Draw events (GOAL, pace notes, bonus banner, race texts, dialog):
// in VR those would land in one eye only or float huge in the world. Draw them once per frame into
// an overlay image, which goes onto the same floating panel as the GUI.
function vhr_overlay_2d(_draw) {
    if(!variable_global_exists("vhr_enabled") || !global.vhr_enabled) {_draw();return;}
    if(view_current!=0) return;
    var _frame=variable_global_exists("vhrq_frame_no") ? global.vhrq_frame_no : 0;
    if(!variable_global_exists("vhr_ov_surf") || !surface_exists(global.vhr_ov_surf)) {global.vhr_ov_surf=surface_create(512,288);global.vhr_ov_frame=-1;}
    if(!surface_exists(global.vhr_ov_surf)) return;
    var _world=matrix_get(matrix_world),_view=matrix_get(matrix_view),_proj=matrix_get(matrix_projection);
    surface_set_target(global.vhr_ov_surf);
    if(global.vhr_ov_frame!=_frame) {draw_clear_alpha(c_black,0);global.vhr_ov_frame=_frame;}
    shader_reset();matrix_set(matrix_world,matrix_build_identity());
    gpu_set_ztestenable(false);gpu_set_zwriteenable(false);gpu_set_alphatestenable(false);
    d3d_set_projection_ortho(0,0,512,288,0);
    _draw();
    surface_reset_target();
    matrix_set(matrix_world,_world);matrix_set(matrix_view,_view);matrix_set(matrix_projection,_proj);
    gpu_set_ztestenable(true);gpu_set_zwriteenable(true);
}

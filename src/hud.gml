// Convert a flat display's pixel axes into chassis axes: right=+Y, down=+Z.
function vhr_display_matrix(_x,_y,_z,_s) {
    var _m=matrix_build_identity();
    _m[0]=0;_m[1]=_s;_m[2]=0;
    _m[4]=0;_m[5]=0;_m[6]=_s;
    _m[8]=1;_m[9]=0;_m[10]=0;
    _m[12]=_x;_m[13]=_y;_m[14]=_z;
    return _m;
}
function vhr_draw_hud() {
    if(view_current>1 || !instance_exists(target)) return;
    var _cam=obj_main.camera[view_current];
    if(!instance_exists(_cam) || _cam.target!=target || !obj_main.showHUD) return;
    var _t=target.obj;
    var _world=matrix_get(matrix_world);
    var _font=draw_get_font(),_ha=draw_get_halign(),_va=draw_get_valign();
    var _colour=draw_get_colour(),_alpha=draw_get_alpha();
    shader_reset();gpu_set_fog(false,c_white,0,0);
    gpu_set_ztestenable(false);gpu_set_zwriteenable(false);
    gpu_set_alphatestenable(false);draw_set_alpha(1);draw_set_colour(c_white);
    if(!surface_exists(_cam.vhr_hud_surface)) _cam.vhr_hud_surface=surface_create(512,256);
    if(!surface_exists(_cam.vhr_hud_surface)) return;
    // Refresh once for the stereo pair. Surface loss is handled above.
    if(view_current==0) {
        surface_set_target(_cam.vhr_hud_surface);
        matrix_set(matrix_world,matrix_build_identity());
        d3d_set_projection_ortho(0,0,512,256,0);
        draw_clear_alpha(c_black,0);
        draw_set_colour(make_colour_rgb(12,18,31));
        draw_rectangle(0,0,255,127,false);draw_rectangle(256,0,511,255,false);
        draw_set_colour(make_colour_rgb(49,193,191));
        draw_rectangle(1,1,254,126,true);draw_rectangle(257,1,510,254,true);
        draw_set_colour(c_white);draw_set_font(hudnumbers);textAlign(0,0);
        // Original speedometer artwork and exact speed/unit conversion used by the game.
        draw_sprite(spr_speedometer,obj_main.kph,65,61);
        draw_sprite_ext(spr_speedometer,2,65,61,1,1,135-min(_t.gearSpdRatio*180,220),c_white,1);
        var _mph=round(_t.spd*7.2);
        draw_text(54,77,string_zero(floor(obj_main.kph ? _mph*1.60934 : _mph),3));
        draw_sprite_ext(spr_HUD_pos,0,132,50,0.65,0.65,0,c_white,1);
        if(_t.place>=1 && _t.place<=12) draw_sprite_ext(spr_HUD_positions,_t.place-1,177,37,0.65,0.65,0,c_white,1);
        else {draw_set_halign(fa_center);draw_text(196,42,string(_t.place));}
        draw_set_font(ft_VHRnew);draw_set_halign(fa_center);
        draw_text(183,94,frametime_to_string(obj.total_time));
        // Boost remains visible beside the instruments.
        draw_set_colour(make_colour_rgb(33,45,60));draw_rectangle(12,111,116,117,false);
        draw_set_colour(make_colour_rgb(81,231,163));draw_rectangle(12,111,12+104*clamp(_t.boost/3,0,1),117,false);
        draw_set_colour(c_white);draw_set_font(hudnumbers);textAlign(0,0);
        draw_sprite(spr_HUD_lapcounter,obj_track.rally,275,10);
        draw_text(337,14,string(clamp(_t.lap+1,0,global.maxLaps))+"/"+string(global.maxLaps));
        // Fit the actual course nodes to the GPS panel, including rally courses.
        var _nodes=obj_track.nodes,_count=ds_list_size(_nodes);
        if(_count>1) {
            var _first=ds_list_find_value(_nodes,0);
            var _xmin=_first[0],_xmax=_first[0],_ymin=_first[1],_ymax=_first[1];
            for(var _i=0;_i<_count;_i+=2) {
                var _n=ds_list_find_value(_nodes,_i);
                _xmin=min(_xmin,_n[0]);_xmax=max(_xmax,_n[0]);_ymin=min(_ymin,_n[1]);_ymax=max(_ymax,_n[1]);
            }
            var _s=min(206/max(1,_xmax-_xmin),168/max(1,_ymax-_ymin));
            var _cx=384-(_xmin+_xmax)*0.5*_s,_cy=148-(_ymin+_ymax)*0.5*_s;
            var _prev=_first;
            draw_set_colour(c_white);
            for(var _i=2;_i<_count;_i+=2) {
                var _n=ds_list_find_value(_nodes,_i);
                draw_line_width(_cx+_prev[0]*_s,_cy+_prev[1]*_s,_cx+_n[0]*_s,_cy+_n[1]*_s,3);
                _prev=_n;
            }
            if(!obj_track.rally) draw_line_width(_cx+_prev[0]*_s,_cy+_prev[1]*_s,_cx+_first[0]*_s,_cy+_first[1]*_s,3);
            // Leader and player markers use the same course-position indexing as stock HUD.
            if(instance_exists(global.leader)) {
                var _lead=ds_list_find_value(_nodes,clamp(floor(global.leader.obj.position),0,_count-1));
                draw_set_colour(c_yellow);draw_circle(_cx+_lead[0]*_s,_cy+_lead[1]*_s,4,false);
            }
            var _car=ds_list_find_value(_nodes,clamp(floor(_t.position),0,_count-1));
            var _px=_cx+_car[0]*_s,_py=_cy+_car[1]*_s,_dir=_t.facedir;
            draw_set_colour(c_red);
            draw_triangle(_px+lengthdir_x(7,_dir),_py+lengthdir_y(7,_dir),_px+lengthdir_x(6,_dir+135),_py+lengthdir_y(6,_dir+135),_px+lengthdir_x(6,_dir-135),_py+lengthdir_y(6,_dir-135),false);
        }
        draw_set_colour(c_white);surface_reset_target();
    }
    var _eye=view_camera[view_current];
    camera_set_view_mat(_eye,_cam.vhr_eye_views[view_current]);
    camera_set_proj_mat(_eye,_cam.vhr_eye_projections[view_current]);camera_apply(_eye);
    gpu_set_cullmode(cull_noculling);draw_set_colour(c_white);draw_set_alpha(1);
    if(_cam.vhr_active) {
        gpu_set_ztestenable(true);gpu_set_zwriteenable(true);
        var _body=matrix_build(_cam.vhr_body_x,_cam.vhr_body_y,_cam.vhr_body_z,0,0,_cam.vhr_body_yaw,1,1,1);
        matrix_set(matrix_world,matrix_multiply(vhr_display_matrix(12,-10.7,-15.6,0.05),_body));
        draw_surface_part_ext(_cam.vhr_hud_surface,0,0,256,128,0,0,1,1,c_white,1);
        matrix_set(matrix_world,matrix_multiply(vhr_display_matrix(8.3,4.1,-13.7,0.035),_body));
        draw_surface_part_ext(_cam.vhr_hud_surface,256,0,256,256,0,0,1,1,c_white,1);
    } else {
        // Comfortable fixed-distance HUD in the follow-camera frame; head pose stays in the view.
        gpu_set_ztestenable(false);gpu_set_zwriteenable(false);
        var _base=matrix_build(_cam.cam.x,_cam.cam.y,_cam.cam.z,-_cam.cam.roll,_cam.cam.pitch,_cam.cam.yaw,1,1,1);
        matrix_set(matrix_world,matrix_multiply(vhr_display_matrix(100,-26,5,0.10),_base));
        draw_surface_part_ext(_cam.vhr_hud_surface,0,0,256,128,0,64,1,1,c_white,1);
        draw_surface_part_ext(_cam.vhr_hud_surface,256,0,256,256,264,0,1,1,c_white,1);
    }
    matrix_set(matrix_world,_world);gpu_set_ztestenable(true);gpu_set_zwriteenable(true);
    draw_set_font(_font);draw_set_halign(_ha);draw_set_valign(_va);draw_set_colour(_colour);draw_set_alpha(_alpha);
}

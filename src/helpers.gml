function vhr_box(_buf,_x1,_y1,_z1,_x2,_y2,_z2,_col) {
    var _p=[[_x1,_y1,_z1],[_x2,_y1,_z1],[_x2,_y2,_z1],[_x1,_y2,_z1],[_x1,_y1,_z2],[_x2,_y1,_z2],[_x2,_y2,_z2],[_x1,_y2,_z2]];
    var _idx=[0,1,2,0,2,3,4,6,5,4,7,6,0,4,5,0,5,1,1,5,6,1,6,2,2,6,7,2,7,3,3,7,4,3,4,0];
    for(var _i=0;_i<36;_i++) {
        var _v=_p[_idx[_i]];
        vertex_position_3d(_buf,_v[0],_v[1],_v[2]);
        vertex_colour(_buf,_col,1);
        vertex_texcoord(_buf,0,0);
    }
}
function vhr_disable() {
    if(!global.vhr_enabled) return;
    external_call(global.vhr_mode,0);
    global.vhr_enabled=false;
    view_set_visible(1,false);
    view_set_visible(2,false);view_surface_id[2]=global.vhr_old_surface2;
    view_set_camera(2,global.vhr_old_camera2);
    camera_destroy(global.vhr_mirror_camera);
    if(surface_exists(global.vhr_mirror_surface)) surface_free(global.vhr_mirror_surface);
    global.vhr_mirror_surface=-1;global.vhr_mirror_ready=false;
    view_set_xport(2,global.vhr_old_view2[1]);view_set_yport(2,global.vhr_old_view2[2]);
    view_set_wport(2,global.vhr_old_view2[3]);view_set_hport(2,global.vhr_old_view2[4]);view_set_visible(2,global.vhr_old_view2[0]);
    view_set_xport(0,0); view_set_yport(0,0);
    view_set_wport(0,global.vhr_old_port_w);view_set_hport(0,global.vhr_old_port_h);
    view_set_camera(1,global.vhr_old_camera1);
    if(global.vhr_eye_camera!=-1) {camera_destroy(global.vhr_eye_camera);global.vhr_eye_camera=-1;}
    if(instance_exists(obj_main)) obj_main.camera=global.vhr_old_cameras;
    window_set_size(global.vhr_old_w,global.vhr_old_h);
    window_set_fullscreen(global.vhr_old_fullscreen);
    if(surface_exists(application_surface)) surface_resize(application_surface,global.vhr_old_surface_w,global.vhr_old_surface_h);
    show_debug_message("VHRVR: VR disabled; original view restored.");
}
function vhr_ring(_buf,_x,_y,_z,_outer,_inner,_col) {
    for(var _i=0;_i<48;_i++) {
        var _a=2*pi*_i/48,_b=2*pi*(_i+1)/48;
        var _p=[[_y+cos(_a)*_outer,_z+sin(_a)*_outer],[_y+cos(_b)*_outer,_z+sin(_b)*_outer],[_y+cos(_b)*_inner,_z+sin(_b)*_inner],[_y+cos(_a)*_inner,_z+sin(_a)*_inner]];
        var _ix=[0,1,2,0,2,3];
        for(var _j=0;_j<6;_j++) {
            var _v=_p[_ix[_j]];
            vertex_position_3d(_buf,_x,_v[0],_v[1]);vertex_colour(_buf,_col,1);vertex_texcoord(_buf,0,0);
        }
    }
}
function vhr_gauge(_buf,_x,_y,_z,_radius) {
    vhr_ring(_buf,_x,_y,_z,_radius,0,make_colour_rgb(8,12,20));
    vhr_ring(_buf,_x-0.04,_y,_z,_radius,_radius-0.16,make_colour_rgb(133,145,162));
    for(var _i=0;_i<11;_i++) {
        var _a=pi*0.15+pi*1.7*_i/10;
        var _yy=_y+cos(_a)*(_radius-0.45),_zz=_z+sin(_a)*(_radius-0.45);
        vhr_box(_buf,_x-0.08,_yy-0.12,_zz-0.12,_x-0.06,_yy+0.12,_zz+0.12,_i<8 ? make_colour_rgb(182,231,196) : make_colour_rgb(237,84,89));
    }
    vhr_box(_buf,_x-0.12,_y-0.1,_z-_radius+0.7,_x-0.1,_y+0.1,_z,make_colour_rgb(234,70,83));
    vhr_ring(_buf,_x-0.15,_y,_z,0.25,0,make_colour_rgb(165,178,185));
}

// Chamfered cross section keeps deliberate flat retro facets instead of box corners.
function vhr_softbox(_buf,_x1,_y1,_z1,_x2,_y2,_z2,_col) {
    var _r=min((_y2-_y1)*0.15,(_z2-_z1)*0.22);
    var _p=[[_y1+_r,_z1],[_y2-_r,_z1],[_y2,_z1+_r],[_y2,_z2-_r],[_y2-_r,_z2],[_y1+_r,_z2],[_y1,_z2-_r],[_y1,_z1+_r]];
    for(var _i=0;_i<8;_i++) {
        var _a=_p[_i],_b=_p[(_i+1)%8];
        var _shade=0.75+0.25*abs(dcos(_i*45));
        var _c=make_colour_rgb(colour_get_red(_col)*_shade,colour_get_green(_col)*_shade,colour_get_blue(_col)*_shade);
        var _v=[[_x1,_a[0],_a[1]],[_x2,_a[0],_a[1]],[_x2,_b[0],_b[1]],[_x1,_b[0],_b[1]]];
        var _ix=[0,1,2,0,2,3];
        for(var _j=0;_j<6;_j++) {var _t=_v[_ix[_j]];vertex_position_3d(_buf,_t[0],_t[1],_t[2]);vertex_colour(_buf,_c,1);vertex_texcoord(_buf,0,0);}
        for(var _end=0;_end<2;_end++) {
            var _x=_end==0 ? _x1 : _x2;
            var _cap=[[_x,(_y1+_y2)/2,(_z1+_z2)/2],[_x,_a[0],_a[1]],[_x,_b[0],_b[1]]];
            for(var _j=0;_j<3;_j++) {var _t=_cap[_j];vertex_position_3d(_buf,_t[0],_t[1],_t[2]);vertex_colour(_buf,_col,1);vertex_texcoord(_buf,0,0);}
        }
    }
}
// Faceted rounded forms for padded gloves and the curved nose of the hood.
function vhr_oval(_buf,_x,_y,_z,_rx,_ry,_rz,_col) {
    for(var _i=0;_i<12;_i++) for(var _j=0;_j<6;_j++) {
        var _a0=_i*30,_a1=(_i+1)*30,_b0=-90+_j*30,_b1=_b0+30;
        var _p=[[_a0,_b0],[_a1,_b0],[_a1,_b1],[_a0,_b1]],_ix=[0,1,2,0,2,3];
        var _f=0.72+0.28*abs(dsin((_b0+_b1)/2));
        var _c=make_colour_rgb(colour_get_red(_col)*_f,colour_get_green(_col)*_f,colour_get_blue(_col)*_f);
        for(var _k=0;_k<6;_k++) {var _q=_p[_ix[_k]];vertex_position_3d(_buf,_x+_rx*dcos(_q[1])*dcos(_q[0]),_y+_ry*dcos(_q[1])*dsin(_q[0]),_z+_rz*dsin(_q[1]));vertex_colour(_buf,_c,1);vertex_texcoord(_buf,0,0);}
    }
}

// Slanted A-pillar: base at the cowl, upper end rearward at the roof header.
function vhr_pillar(_buf,_y,_width,_col) {
    var _p=[[25,_y-_width,-13],[27,_y-_width,-13],[27,_y+_width,-13],[25,_y+_width,-13],[11,_y-_width,-31],[13,_y-_width,-31],[13,_y+_width,-31],[11,_y+_width,-31]];
    var _ix=[0,1,2,0,2,3,4,6,5,4,7,6,0,4,5,0,5,1,1,5,6,1,6,2,2,6,7,2,7,3,3,7,4,3,4,0];
    for(var _i=0;_i<36;_i++){var _v=_p[_ix[_i]];vertex_position_3d(_buf,_v[0],_v[1],_v[2]);vertex_colour(_buf,_col,1);vertex_texcoord(_buf,0,0);}
}

function vhr_pixel_wheel(_buf) {
    var _ink=make_colour_rgb(12,14,25),_grey=make_colour_rgb(70,75,94),_light=make_colour_rgb(177,193,206);
    var _pink=make_colour_rgb(235,46,141),_teal=make_colour_rgb(5,161,170);
    // Twice the pixel density, with curved silhouettes and individually shaded fingers.
    for(var _py=0;_py<152;_py++) for(var _px=0;_px<160;_px++) {
        var _u=_px*0.5,_v=_py*0.5,_dx=_u-40,_dy=_v-32,_r=sqrt(_dx*_dx+_dy*_dy),_c=-1;
        if(_r>=22 && _r<=29) _c=_ink;
        if(_r>=23.5 && _r<=27.5) _c=merge_colour(_grey,_light,clamp((27.5-_r)/4+max(0,-_dy)*0.018,0,1));
        if(abs(_r-25.5)<0.3 && (_px+_py) mod 7<2) _c=make_colour_rgb(205,130,175);
        if((abs(_dy)<2 && abs(_dx)<24) || (abs(_dx)<2 && _dy>0 && _dy<24)) _c=_light;
        if((_dx*_dx)/196+(_dy*_dy)/121<1) _c=_ink;
        if((_dx*_dx)/144+(_dy*_dy)/81<1) _c=merge_colour(_dx<0 ? _pink : _teal,c_black,clamp((_dy+9)/28,0,0.45));
        for(var _side=-1;_side<=1;_side+=2) {
            var _hx=40+_side*25,_lx=_u-_hx,_ly=_v-29;
            var _shape=(_lx*_lx)/49+(_ly*_ly)/121;
            var _armx=_hx+_side*max(0,_v-37)*0.27,_ax=abs(_u-_armx);
            var _arm=_v>=35 && _v<44 && _ax<6.5;
            var _thumbx=_hx-_side*5.4;
            var _thumb=((_u-_thumbx)*(_u-_thumbx))/9+((_v-35)*(_v-35))/25;
            if(_shape<1 || _arm || _thumb<1) {
                var _edge=(_shape>0.82 && !_arm && _thumb>0.75) || (_arm && _ax>5.7 && _shape>0.85);
                var _base=(_lx*_side+(_v-26)*0.24>1) ? _pink : _teal;
                var _shade=clamp((_lx+6)/20+(_v-20)*0.005,0.05,0.5);
                _c=_edge ? _ink : merge_colour(_base,c_black,_shade);
                if(!_edge && _shape<0.7 && _lx<-1) _c=merge_colour(_base,c_white,0.22);
                // Four bent, separated finger pads, with bright seams and dark creases.
                if(_shape<0.82 && _v>=23 && _v<34 && abs(_lx)<4.5) {
                    var _finger=(_v-23) mod 2.8;
                    _c=_finger<0.45 ? make_colour_rgb(103,54,48) : merge_colour(make_colour_rgb(190,116,82),make_colour_rgb(255,211,161),clamp(1-abs(_lx)/6-(_finger-0.8)*0.13,0,1));
                }
                if(_thumb<0.65 && _v>=32) _c=merge_colour(make_colour_rgb(192,117,85),make_colour_rgb(255,213,167),clamp(1-abs(_u-_thumbx)/3,0,1));
                if(_arm && _v>=40 && _v<=44) _c=_v<41 || _v>43 ? _ink : _light;
                if(_arm && _v>46 && _ax>4.5 && _ax<5.2 && _py mod 5<3) _c=merge_colour(_base,c_white,0.55);
                if(_shape<0.6 && _v>34 && _v<37 && abs(_lx)<2) _c=make_colour_rgb(244,224,100);
            }
        }
        if(_c!=-1) {
            var _y=(_u-40)*0.16,_z=(_v-32)*0.16;
            var _q=[[_y,_z],[_y+0.08,_z],[_y+0.08,_z+0.08],[_y,_z+0.08]],_ix=[0,1,2,0,2,3];
            for(var _j=0;_j<6;_j++){var _p=_q[_ix[_j]];vertex_position_3d(_buf,-0.65,_p[0],_p[1]);vertex_colour(_buf,_c,1);vertex_texcoord(_buf,0,0);}
        }
    }
}
function vhr_crystal(_buf,_x,_y,_z,_rx,_ry,_rz) {
    var _p=[[_x-_rx,_y-_ry,_z],[_x+_rx,_y-_ry,_z],[_x+_rx,_y+_ry,_z],[_x-_rx,_y+_ry,_z],[_x,_y,_z-_rz],[_x,_y,_z+_rz]];
    var _ix=[0,1,4,1,2,4,2,3,4,3,0,4,1,0,5,2,1,5,3,2,5,0,3,5];
    var _col=[make_colour_rgb(37,229,247),make_colour_rgb(187,66,244),make_colour_rgb(254,90,199),make_colour_rgb(103,249,215)];
    for(var _i=0;_i<24;_i++){var _v=_p[_ix[_i]];vertex_position_3d(_buf,_v[0],_v[1],_v[2]);vertex_colour(_buf,_col[(_i div 3) mod 4],0.58);vertex_texcoord(_buf,0,0);}
}

function vhr_wheel_racing() {
    return room==rm_main && instance_exists(obj_main) && instance_exists(obj_race_manager) && !obj_race_manager.attract && !obj_main.pause && !global.finished && !global.stop;
}
function vhr_menu_wheel_release() {
    if(!variable_global_exists("vhr_wheel") || !global.vhr_wheel || vhr_wheel_racing()) return;
    external_call(global.vhr_wstop);
    global.vhr_wheel=false;global.vhr_wheel_retry=0;
    global.vhr_drift_prev=false;global.vhr_view_prev=false;
    show_debug_message("VHRVR: released G29 to normal menu controls.");
}

// Tapered eight-sided sleeve, modeled between two chassis-local joint positions.
function vhr_sleeve(_buf,_a,_b,_r1,_r2,_col) {
    var _dx=_b[0]-_a[0],_dy=_b[1]-_a[1],_dz=_b[2]-_a[2];
    var _len=max(0.001,sqrt(_dx*_dx+_dy*_dy+_dz*_dz));_dx/=_len;_dy/=_len;_dz/=_len;
    var _h=max(0.001,sqrt(_dx*_dx+_dy*_dy));
    var _ux=-_dy/_h,_uy=_dx/_h,_uz=0;
    var _vx=-_dz*_uy,_vy=_dz*_ux,_vz=_dx*_uy-_dy*_ux;
    for(var _i=0;_i<8;_i++) {
        var _p=[];
        for(var _j=0;_j<4;_j++) {
            var _end=(_j==1 || _j==2),_theta=(_i+(_j>=2))*45;
            var _c=_end ? _b : _a,_r=_end ? _r2 : _r1;
            array_push(_p,[_c[0]+_r*(_ux*dcos(_theta)+_vx*dsin(_theta)),_c[1]+_r*(_uy*dcos(_theta)+_vy*dsin(_theta)),_c[2]+_r*(_uz*dcos(_theta)+_vz*dsin(_theta))]);
        }
        var _ix=[0,1,2,0,2,3];
        var _shade=merge_colour(_col,c_black,0.1+0.35*abs(dsin(_i*45)));
        if(_i==1 || _i==5) _shade=make_colour_rgb(239,65,152);
        for(var _k=0;_k<6;_k++){var _v=_p[_ix[_k]];vertex_position_3d(_buf,_v[0],_v[1],_v[2]);vertex_colour(_buf,_shade,1);vertex_texcoord(_buf,0,0);}
    }
}
function vhr_build_arms() {
    vertex_begin(vhr_arm_mesh,vhr_format);
    var _c=dcos(vhr_steer_angle),_s=dsin(vhr_steer_angle);
    for(var _side=-1;_side<=1;_side+=2) {
        var _hand_y=_side*4,_hand_z=1.55;
        var _wrist=[6.85,-4+_hand_y*_c-_hand_z*_s,-12+_hand_y*_s+_hand_z*_c];
        var _shoulder=[-12,-4+_side*6.2,-16.5];
        var _elbow=[-5,-4+_side*6.7,-6.5];
        // Elbow shifts partially with the wrist, while the shoulder stays at the seat.
        _elbow[1]+=(_wrist[1]-(-4+_side*4))*0.28;
        _elbow[2]+=(_wrist[2]+10.45)*0.3;
        vhr_sleeve(vhr_arm_mesh,_shoulder,_elbow,1.65,1.35,make_colour_rgb(21,94,115));
        vhr_sleeve(vhr_arm_mesh,_elbow,_wrist,1.35,0.85,make_colour_rgb(13,174,172));
    }
    vertex_end(vhr_arm_mesh);
}

function vhr_load_driver_art() {
    var _pre=vhr_driver_clean_prebaked();
    if(_pre!=-1 && sprite_exists(_pre)) return _pre;
    var _spr=sprite_add("VHR-driver.png",1,false,false,0,0);
    if(!sprite_exists(_spr)) return _spr;
    // The supplied image has compression variations in its gray background.
    // Remove that color with tolerance at load time, preserving the original art file.
    var _surf=surface_create(1024,559);
    surface_set_target(_surf);
    draw_clear_alpha(c_black,0);
    draw_sprite_ext(_spr,0,0,0,1,1,0,c_white,1);
    surface_reset_target();
    var _pixels=buffer_create(1024*559*4,buffer_fixed,1);
    buffer_get_surface(_pixels,_surf,0);
    for(var _i=0;_i<1024*559*4;_i+=4) {
        var _r=buffer_peek(_pixels,_i,buffer_u8),_g=buffer_peek(_pixels,_i+1,buffer_u8),_b=buffer_peek(_pixels,_i+2,buffer_u8);
        if(abs(_r-114)<=24 && abs(_g-130)<=24 && abs(_b-143)<=24) buffer_poke(_pixels,_i+3,buffer_u8,0);
    }
    buffer_set_surface(_pixels,_surf,0);
    var _result=sprite_create_from_surface(_surf,0,0,1024,559,false,false,0,0);
    buffer_delete(_pixels);surface_free(_surf);sprite_delete(_spr);
    return _result;
}
function vhr_art_vertex(_buf,_px,_py,_arm,_uv) {
    var _y=(_px-512)*0.023,_z=(_py-230)*0.023,_x=-0.65;
    if(_arm) {
        var _t=clamp((_py-245)/(559-245),0,1);
        var _angle=vhr_steer_angle*(1-_t);
        var _c=dcos(_angle),_s=dsin(_angle),_ry=_y*_c-_z*_s,_rz=_y*_s+_z*_c;
        // Quest: the arm runs from the wheel down and back to the sleeves just in front of and below
        // your chest (sleeves show when you look down), instead of stretching back past your head.
        _x=lerp(6.85,-4,_t);
        _y=-4+_ry;_z=-12+_rz;
    }
    vertex_position_3d(_buf,_x,_y,_z);
    vertex_colour(_buf,c_white,1);
    vertex_texcoord(_buf,lerp(_uv[0],_uv[2],_px/1024),lerp(_uv[1],_uv[3],_py/559));
}
function vhr_art_quad(_buf,_x1,_y1,_x2,_y2,_arm,_uv) {
    var _v=[[_x1,_y1],[_x2,_y1],[_x2,_y2],[_x1,_y2]],_ix=[0,1,2,0,2,3];
    for(var _i=0;_i<6;_i++){var _p=_v[_ix[_i]];vhr_art_vertex(_buf,_p[0],_p[1],_arm,_uv);}
}
function vhr_build_driver() {
    if(!sprite_exists(vhr_driver_sprite)) return;
    var _uv=sprite_get_uvs(vhr_driver_sprite,0);
    vertex_begin(vhr_wheel_mesh,vhr_format);
    vhr_art_quad(vhr_wheel_mesh,0,0,1024,245,false,_uv);
    vhr_art_quad(vhr_wheel_mesh,350,245,674,559,false,_uv);
    vertex_end(vhr_wheel_mesh);
    vertex_begin(vhr_arm_mesh,vhr_format);
    var _rows=[245,285,325,365,405,425,465,505,559];
    for(var _i=0;_i<array_length(_rows)-1;_i++) {
        vhr_art_quad(vhr_arm_mesh,0,_rows[_i],350,_rows[_i+1],true,_uv);
        vhr_art_quad(vhr_arm_mesh,674,_rows[_i],1024,_rows[_i+1],true,_uv);
    }
    vertex_end(vhr_arm_mesh);
}

// Rooms and overlays that create a background obj_camera but are menus, not races.
function vhr_menu_scene() {
    return room==rm_options || instance_exists(obj_character_scene) || instance_exists(obj_track_menu) || instance_exists(obj_arcade_backdrop)
        || !instance_exists(obj_race_manager) || obj_race_manager.attract;
}
// Standalone options screen: plain black backdrop instead of the demo car driving behind the text.
function vhr_options_backdrop() {
    if(room!=rm_options) return;
    draw_set_alpha(1);draw_set_colour(c_black);
    draw_rectangle(-16,-16,display_get_gui_width()+16,display_get_gui_height()+16,false);
    draw_set_colour(c_white);
}

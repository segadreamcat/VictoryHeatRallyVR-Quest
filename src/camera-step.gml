if (view == 0) {
    // Press edge only: holding L3 does not repeatedly switch the camera.
    if(keyboard_check_pressed(vk_f7) || gamepad_button_check_pressed_any(gp_stickl)) global.vhr_cockpit=!global.vhr_cockpit;
    if(keyboard_check_pressed(vk_pageup)) global.vhr_seat_height=min(28,global.vhr_seat_height+1);
    if(keyboard_check_pressed(vk_pagedown)) global.vhr_seat_height=max(8,global.vhr_seat_height-1);
    if(keyboard_check_pressed(vk_f6) && global.vhr_enabled) external_call(global.vhr_recenter);
    // Menus (options, character/track select, arcade backdrop) also spawn an obj_camera: keep them on the flat screen.
    var _vhr_menu=vhr_menu_scene();
    if(_vhr_menu && global.vhr_enabled) vhr_disable();
    var _start_ok=!_vhr_menu && instance_exists(target) && state<0 && obj.mode==0 && obj_main.players==1;
    if(keyboard_check_pressed(vk_f8)) global.vhr_auto=!global.vhr_enabled;
    var _auto_start=global.vhr_auto && !global.vhr_enabled && _start_ok && current_time>=global.vhr_retry_at;
    if(keyboard_check_pressed(vk_f8) || _auto_start) {
        global.vhr_retry_at=current_time+5000;
        if(global.vhr_enabled) vhr_disable();
        else if(_start_ok) {
            try {
                if(global.vhr_init==-1) {
                    global.vhr_init=external_define("VHRVR.dll","vhr_init",dll_cdecl,ty_real,0);
                    global.vhr_stop=external_define("VHRVR.dll","vhr_stop",dll_cdecl,ty_real,0);
                    global.vhr_poll=external_define("VHRVR.dll","vhr_poll",dll_cdecl,ty_real,0);
                    global.vhr_recenter=external_define("VHRVR.dll","vhr_recenter",dll_cdecl,ty_real,0);
                    global.vhr_value=external_define("VHRVR.dll","vhr_value",dll_cdecl,ty_real,2,ty_real,ty_real);
                }
                var _err=external_call(global.vhr_init);
                if(_err==0) {
                    global.vhr_old_w=window_get_width();global.vhr_old_h=window_get_height();
                    global.vhr_old_fullscreen=window_get_fullscreen();
                    global.vhr_old_port_w=view_get_wport(0);global.vhr_old_port_h=view_get_hport(0);
                    global.vhr_old_surface_w=surface_get_width(application_surface);global.vhr_old_surface_h=surface_get_height(application_surface);
                    global.vhr_old_cameras=obj_main.camera;
                    global.vhr_old_camera1=view_get_camera(1);
                    global.vhr_eye_camera=camera_create();
                    view_set_camera(1,global.vhr_eye_camera);
                    obj_main.camera=array_create(array_length(global.vhr_old_cameras),noone);
                    array_copy(obj_main.camera,0,global.vhr_old_cameras,0,array_length(global.vhr_old_cameras));
                    obj_main.camera[1]=id;
                    global.vhr_old_camera2=view_get_camera(2);global.vhr_old_surface2=view_surface_id[2];
                    global.vhr_old_view2=[view_get_visible(2),view_get_xport(2),view_get_yport(2),view_get_wport(2),view_get_hport(2)];
                    global.vhr_mirror_camera=camera_create();camera_set_view_size(global.vhr_mirror_camera,512,160);
                    global.vhr_mirror_surface=-1;global.vhr_mirror_ready=false;
                    view_set_camera(2,global.vhr_mirror_camera);obj_main.camera[2]=id;
                    window_set_fullscreen(false);window_set_size(3072,1536);
                    external_call(global.vhr_mode,1);global.vhr_theatre_ready=true;global.vhr_enabled=true;
                    show_debug_message("VHRVR: SteamVR initialized. F8 stops, F6 recenters.");
                } else show_debug_message("VHRVR: SteamVR initialization failed: "+string(_err));
            } catch(_error) {show_debug_message("VHRVR: "+_error.message);}
        } else show_debug_message("VHRVR: enable VR during a single-player race after the starting camera sequence.");
    }
    if(global.vhr_enabled) {
        {
            if(surface_exists(application_surface) && (surface_get_width(application_surface)!=3072 || surface_get_height(application_surface)!=1536)) surface_resize(application_surface,3072,1536);
            view_enabled=true;
            for(var _eye=0;_eye<2;_eye++) {
                view_set_visible(_eye,true);view_set_xport(_eye,_eye*1536);view_set_yport(_eye,0);
                view_set_wport(_eye,1536);view_set_hport(_eye,1536);
            }
                        if(!surface_exists(global.vhr_mirror_surface)){global.vhr_mirror_surface=surface_create(512,160);global.vhr_mirror_ready=false;}
            view_surface_id[2]=global.vhr_mirror_surface;
            view_set_visible(2,global.vhr_cockpit && surface_exists(global.vhr_mirror_surface));
            view_set_xport(2,0);view_set_yport(2,0);view_set_wport(2,512);view_set_hport(2,160);
            external_call(global.vhr_poll);
            var _submit_error=external_call(global.vhr_value,0,99);
            if(_submit_error!=0 && _submit_error!=vhr_last_error) {
                vhr_last_error=_submit_error;
                show_debug_message("VHRVR: compositor error "+string(_submit_error));
            }
        }
    }
}
// Optional G29 controls, independent of whether SteamVR is enabled.
if(view==0) {
    if(keyboard_check_pressed(vk_f9)) global.vhr_wheel_auto=!global.vhr_wheel;
    vhr_menu_wheel_release();
    var _wheel_allowed=vhr_wheel_racing();
    var _wheel_try=_wheel_allowed && global.vhr_wheel_auto && !global.vhr_wheel && instance_exists(target) && current_time>=global.vhr_wheel_retry;
    if((keyboard_check_pressed(vk_f9) || _wheel_try) && (_wheel_allowed || global.vhr_wheel)) {
        global.vhr_wheel_retry=current_time+10000;
        if(global.vhr_wheel) {external_call(global.vhr_wstop);global.vhr_wheel=false;global.vhr_ffb=false;}
        else {
            if(global.vhr_wheel_api==-1) {
                global.vhr_wheel_api=external_define("VHRVR.dll","vhr_wheel_init",dll_cdecl,ty_real,0);
                global.vhr_wstop=external_define("VHRVR.dll","vhr_wheel_stop",dll_cdecl,ty_real,0);
                global.vhr_wpoll=external_define("VHRVR.dll","vhr_wheel_poll",dll_cdecl,ty_real,0);
                global.vhr_wvalue=external_define("VHRVR.dll","vhr_wheel_value",dll_cdecl,ty_real,1,ty_real);
                global.vhr_wforce=external_define("VHRVR.dll","vhr_wheel_force",dll_cdecl,ty_real,3,ty_real,ty_real,ty_real);
            }
            var _result=external_call(global.vhr_wheel_api);
            global.vhr_wheel=(_result==0); global.vhr_ffb=global.vhr_wheel && global.vhr_ffb_requested && external_call(global.vhr_wvalue,99)>0.5;
            show_debug_message("VHRVR: G29 toggle result "+string(_result)+" (0=enabled). F10 toggles feedback.");
        }
    }
    if(keyboard_check_pressed(vk_f10) && global.vhr_wheel) {
        if(external_call(global.vhr_wvalue,99)>0.5) {global.vhr_ffb=!global.vhr_ffb;global.vhr_ffb_requested=global.vhr_ffb;}
        if(!global.vhr_ffb) external_call(global.vhr_wforce,0,0,0);
        show_debug_message("VHRVR: G29 feedback "+string(global.vhr_ffb)+"; available="+string(external_call(global.vhr_wvalue,99)));
    }
    if(global.vhr_wheel && (obj_main.pause || !instance_exists(target) || state>=0)) external_call(global.vhr_wforce,0,0,0);
}


function vhr_theatre_boot() {
if (!variable_global_exists("vhr_cockpit")) {
    global.vhr_wheel_auto=true;global.vhr_wheel_retry=0;global.vhr_auto=true;global.vhr_retry_at=0;global.vhr_wheel=false;global.vhr_ffb=false;global.vhr_ffb_requested=true;global.vhr_hit_until=0;global.vhr_hit_level=0;global.vhr_wheel_api=-1;global.vhr_drift_prev=false;global.vhr_view_prev=false;global.vhr_cockpit=true;global.vhr_enabled=false;
    global.vhr_seat_height=19;global.vhr_units=16;
    global.vhr_eye_camera=-1;global.vhr_init=-1;
}
    if(!variable_global_exists("vhr_theatre_ready")){global.vhr_theatre_ready=false;global.vhr_boot_retry=0;}
    if(global.vhr_theatre_ready || current_time<global.vhr_boot_retry) return;
    global.vhr_boot_retry=current_time+5000;
    if(global.vhr_init==-1) {
        global.vhr_init=external_define("VHRVR.dll","vhr_init",dll_cdecl,ty_real,0);
        global.vhr_stop=external_define("VHRVR.dll","vhr_stop",dll_cdecl,ty_real,0);
        global.vhr_poll=external_define("VHRVR.dll","vhr_poll",dll_cdecl,ty_real,0);
        global.vhr_recenter=external_define("VHRVR.dll","vhr_recenter",dll_cdecl,ty_real,0);
        global.vhr_value=external_define("VHRVR.dll","vhr_value",dll_cdecl,ty_real,2,ty_real,ty_real);
        global.vhr_mpoll=external_define("VHRVR.dll","vhr_menu_poll",dll_cdecl,ty_real,1,ty_real);
        global.vhr_mkey=external_define("VHRVR.dll","vhr_menu_key",dll_cdecl,ty_real,2,ty_real,ty_real);
        global.vhr_mode=external_define("VHRVR.dll","vhr_mode",dll_cdecl,ty_real,1,ty_real);
    }
    var _result=external_call(global.vhr_init);
    if(_result==0){global.vhr_theatre_ready=true;external_call(global.vhr_mode,0);}
    else show_debug_message("VHRVR: theatre initialization result "+string(_result));
}

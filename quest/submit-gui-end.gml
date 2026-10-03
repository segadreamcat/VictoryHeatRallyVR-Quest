// obj_vhrq Draw GUI End. This instance has the lowest depth, so it runs after every other
// GUI draw: the frame is complete. Hand it to the headset and end the OpenXR frame.
if(vhrq_active()) {
    if(variable_global_exists("vhr_enabled") && global.vhr_enabled && surface_exists(application_surface)) {
        // Racing: both eyes are side by side in the application surface.
        surface_set_target(application_surface);
        vhrq_submit(1,surface_get_width(application_surface),surface_get_height(application_surface));
        surface_reset_target();
    } else {
        // Menus: the finished back buffer goes on a flat screen floating in front of you.
        if(surface_exists(application_surface)) {surface_set_target(application_surface);surface_reset_target();}
        vhrq_submit(0,window_get_width(),window_get_height());
    }
}

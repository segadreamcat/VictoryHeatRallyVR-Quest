if(view==0 && global.vhr_enabled) vhr_disable();
if(surface_exists(vhr_hud_surface)) surface_free(vhr_hud_surface);
vertex_delete_buffer(vhr_mesh);
vertex_delete_buffer(vhr_wheel_mesh);
if(vhr_sky_mesh!=-1) vertex_delete_buffer(vhr_sky_mesh);
vertex_format_delete(vhr_format);
if(surface_exists(vhr_chase_surface)) surface_free(vhr_chase_surface);
if(view==0 && global.vhr_wheel) { external_call(global.vhr_wstop); global.vhr_wheel=false;global.vhr_ffb=false; }
vertex_delete_buffer(vhr_crystal_mesh);
vertex_delete_buffer(vhr_arm_mesh);
if(sprite_exists(vhr_driver_sprite)) sprite_delete(vhr_driver_sprite);

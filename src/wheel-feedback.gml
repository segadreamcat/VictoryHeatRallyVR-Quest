function vhr_wheel_impact(_player,_strength,_frames) {
    if(!variable_global_exists("vhr_wheel") || !global.vhr_wheel || !vhr_wheel_racing()) return;
    if(!instance_exists(obj_main.camera[0].target) || obj_main.camera[0].target.playernum!=_player) return;
    var _level=clamp(_strength*0.75,0,0.60);
    if(current_time>=global.vhr_hit_until) global.vhr_hit_level=0;
    global.vhr_hit_level=max(global.vhr_hit_level,_level);
    global.vhr_hit_until=max(global.vhr_hit_until,current_time+clamp(_frames*1000/60,50,600));
}
// Called after car physics, when this frame's rumble and wall contact are known.
function vhr_wheel_feedback() {
    if(!variable_global_exists("vhr_wheel") || !global.vhr_wheel || parent!=obj_main.camera[0].target) return;
    if(!vhr_wheel_racing()) {global.vhr_hit_until=0;external_call(global.vhr_wforce,0,0,0);return;}
    var _load=clamp(abs(spd)/20,0,1);
    var _torque=-hstick*(0.035+0.09*_load)+clamp(angle_difference(facedir,dir)/90,-1,1)*0.035;
    if(abs(wallhit)>0) vhr_wheel_impact(playernum,0.8,12);
    var _pulse=current_time<global.vhr_hit_until ? global.vhr_hit_level*min(1,(global.vhr_hit_until-current_time)/80) : 0;
    var _road=inair ? 0 : min(0.28,abs(rumble)*0.13);
    external_call(global.vhr_wforce,_torque,max(_road,_pulse),global.vhr_ffb);
}

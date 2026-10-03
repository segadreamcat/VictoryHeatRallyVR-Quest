// Quest rumble while driving (strong by default; haptic_scale in vhrq.txt tunes it).
// One-off hits (crashes, boosts, landings) already come through controller_vibrate. This adds the
// continuous feel: rumble strips and rough ground, and scraping along a wall.
function vhr_quest_rumble() {
    if(!variable_global_exists("vhrq_on") || !global.vhrq_on || !obj_main.controllerVibrate) return;
    if(!instance_exists(obj_main.camera[0].target) || parent!=obj_main.camera[0].target || !vhr_wheel_racing()) return;
    var _road=inair ? 0 : min(0.5,abs(rumble)*0.25);
    var _wall=abs(wallhit)>0 ? 0.9 : 0;
    var _amp=max(_road,_wall);
    if(_amp>0.02) vhrq_haptic(_amp,2);
}

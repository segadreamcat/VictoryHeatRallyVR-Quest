// obj_vhrq Begin Step. Created before the player controllers, so this runs first each step:
// wait for the headset frame, read Touch controllers, locate the eyes.
global.vhrq_eye=vhrq_get(0);
vhrq_frame();
global.vhrq_frame_no=(variable_global_exists("vhrq_frame_no") ? global.vhrq_frame_no : 0)+1;

// Breadcrumbs for the log file: every room change.
if(!variable_global_exists("vhrq_last_room") || global.vhrq_last_room!=room) {global.vhrq_last_room=room;vhrq_log("room "+room_get_name(room));}

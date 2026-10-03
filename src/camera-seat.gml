vhr_active = global.vhr_cockpit && view==0 && instance_exists(target) && ((state<0 && obj.mode==0) || global.vhr_enabled);
if(vhr_active) {
    // Read the game's processed steering axis, including its remapped controls.
    // Updated once per game step, never once per eye.
    vhr_steer_angle=clamp(target.obj.hstick,-1,1)*100;
    vhr_build_driver();
    vhr_body_x=target.obj.x; vhr_body_y=target.obj.y; vhr_body_z=target.obj.z;
    vhr_body_yaw=target.obj.facedir;
    var _seat_rot=matrix_build(0,0,0,0,0,vhr_body_yaw,1,1,1);
    var _seat=matrix_transform_vertex(_seat_rot,-7,-4,-global.vhr_seat_height);
    cam.x=vhr_body_x+_seat[0];cam.y=vhr_body_y+_seat[1];cam.z=vhr_body_z+_seat[2];
    cam.yaw=vhr_body_yaw;cam.pitch=0;cam.roll=0;cam.fov=90;camyoff=0;
    x=cam.x;y=cam.y;z=cam.z;
}
else if(global.vhr_enabled && view==0 && instance_exists(target)) {
    // Back off the rendered chase camera without feeding this offset into smoothing.
    var _back=matrix_transform_vertex(matrix_build(0,0,0,-cam.roll,cam.pitch,cam.yaw,1,1,1),-48,0,0);
    cam.x+=_back[0];cam.y+=_back[1];cam.z+=_back[2];
}

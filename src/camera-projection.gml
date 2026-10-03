if(global.vhr_enabled && view==0 && view_current<2) {
    var _eye=view_current;
    var _p=array_create(12,0);
    for(var _j=0;_j<12;_j++) _p[_j]=external_call(global.vhr_value,_eye,_j);
    // Cockpit follows the chassis; chase view retains the game's follow-camera rotation.
    var _body=vhr_active ? matrix_build(0,0,0,0,0,vhr_body_yaw,1,1,1) : _rotmatrix;
    var _off=matrix_transform_vertex(_body,-_p[11]*global.vhr_units,_p[3]*global.vhr_units,-_p[7]*global.vhr_units);
    var _fwd=matrix_transform_vertex(_body,_p[10],-_p[2],_p[6]);
    var _upvr=matrix_transform_vertex(_body,_p[9],-_p[1],_p[5]);
    var _ex=cam.x+_off[0],_ey=cam.y+_off[1],_ez=cam.z+camyoff+_off[2];
    // Invalid initial poses retain the ordinary driver-seat camera.
    if(abs(_p[0])+abs(_p[5])+abs(_p[10])>0.01) {
        lookat=matrix_build_lookat(_ex,_ey,_ez,_ex+_fwd[0],_ey+_fwd[1],_ez+_fwd[2],_upvr[0],_upvr[1],_upvr[2]);
        var _l=external_call(global.vhr_value,_eye,20),_r=external_call(global.vhr_value,_eye,21);
        var _t=external_call(global.vhr_value,_eye,22),_b=external_call(global.vhr_value,_eye,23);
        if(_r>_l && _b>_t) {
            var _vfov=radtodeg(2*arctan((_b-_t)/2));
            perspective=matrix_build_projection_perspective_fov(_vfov,(_r-_l)/(_b-_t),0.5,20000);
            perspective[8]=((_l+_r)/(_l-_r))*sign(perspective[11]);
            perspective[9]=((_t+_b)/(_b-_t))*sign(perspective[5])*sign(perspective[11]);
        }
    }
}
if(global.vhr_enabled && view==0 && view_current==2) {
    var _rear_rot=matrix_build(0,0,0,0,0,vhr_body_yaw,1,1,1);
    var _rear=matrix_transform_vertex(_rear_rot,-1,0,0);
    var _mx=vhr_body_x+_rear[0]*23,_my=vhr_body_y+_rear[1]*23,_mz=vhr_body_z-18;
    lookat=matrix_build_lookat(_mx,_my,_mz,_mx+_rear[0],_my+_rear[1],_mz,0,0,1);
    perspective=matrix_build_projection_perspective_fov(30,512/160,0.5,20000);
}
// Preserve the exact eye matrices, independent of later background/HUD camera changes.
vhr_eye_views[view_current]=lookat;
vhr_eye_projections[view_current]=perspective;

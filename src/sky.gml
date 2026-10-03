// A panorama at optical infinity: both eyes share a center, retain their own
// orientation and asymmetric projection, and receive no positional parallax.
function vhr_draw_sky(_bg,_offset) {
    if(_bg==0) return;
    var _owner=obj_main.camera[view_current];
    var _frame=obj_track.timeofday;
    var _key=string(_bg)+":"+string(_frame)+":"+string(_offset);
    if(_owner.vhr_sky_mesh==-1 || _owner.vhr_sky_key!=_key) {
        if(_owner.vhr_sky_mesh!=-1) vertex_delete_buffer(_owner.vhr_sky_mesh);
        _owner.vhr_sky_key=_key;
        _owner.vhr_sky_mesh=vertex_create_buffer();
        var _buf=_owner.vhr_sky_mesh;
        vertex_begin(_buf,_owner.vhr_format);
        var _uv=sprite_get_uvs(_bg,_frame);
        var _height=sprite_get_height(_bg);
        for(var _row=0;_row<32;_row++) {
            var _p0=-90+180*_row/32,_p1=-90+180*(_row+1)/32;
            for(var _col=0;_col<96;_col++) {
                var _a0=360*_col/96,_a1=360*(_col+1)/96;
                var _corners=[[_a0,_p0],[_a1,_p0],[_a1,_p1],[_a0,_p1]];
                var _indices=[0,1,2,0,2,3];
                for(var _j=0;_j<6;_j++) {
                    var _point=_corners[_indices[_j]],_a=_point[0],_p=_point[1];
                    var _v=clamp((144*dtan(clamp(_p,-89.9,89.9))-_offset)/max(1,_height),0,1);
                    // Inset vertical samples to avoid bleeding out of packed texture edges.
                    _v=clamp(_v,0.5/max(1,_height),1-0.5/max(1,_height));
                    vertex_position_3d(_buf,1000*dcos(_p)*dcos(_a),1000*dcos(_p)*dsin(_a),1000*dsin(_p));
                    vertex_colour(_buf,c_white,1);
                    vertex_texcoord(_buf,lerp(_uv[0],_uv[2],_a/360),lerp(_uv[1],_uv[3],_v));
                }
            }
        }
        vertex_end(_buf);vertex_freeze(_buf);
    }
    var _camera=view_camera[view_current];
    // array_copy prevents zeroing translation in the world-view matrix itself.
    var _rotation=array_create(16,0);
    array_copy(_rotation,0,_owner.vhr_eye_views[view_current],0,16);
    _rotation[12]=0;_rotation[13]=0;_rotation[14]=0;
    var _world=matrix_get(matrix_world);
    shader_reset();gpu_set_fog(false,c_white,0,0);gpu_set_cullmode(cull_noculling);
    gpu_set_ztestenable(false);gpu_set_zwriteenable(false);
    matrix_set(matrix_world,matrix_build_identity());
    camera_set_view_mat(_camera,_rotation);
    camera_set_proj_mat(_camera,_owner.vhr_eye_projections[view_current]);camera_apply(_camera);
    vertex_submit(_owner.vhr_sky_mesh,pr_trianglelist,sprite_get_texture(_bg,_frame));
    camera_set_view_mat(_camera,_owner.vhr_eye_views[view_current]);
    camera_set_proj_mat(_camera,_owner.vhr_eye_projections[view_current]);camera_apply(_camera);
    matrix_set(matrix_world,_world);
    gpu_set_ztestenable(true);gpu_set_zwriteenable(true);
}

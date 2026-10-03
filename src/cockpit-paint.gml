// Cockpit paint: the interior trim, stripes, driving gloves and the hood you see through the windshield take the
// colours of the car you are driving. The car's body sprite (the selected car and skin) is drawn to
// a small surface and its most common strong colours are measured once per car, then cached.
// Byte order of surface readback (RGBA on GLES, BGRA on some desktop targets): checked once.
function vhr_red_byte() {
    if(!variable_global_exists("vhr_red_byte_idx")) {
        var _t=surface_create(1,1);surface_set_target(_t);draw_clear_alpha(make_colour_rgb(255,0,0),1);surface_reset_target();
        var _tb=buffer_create(4,buffer_fixed,1);buffer_get_surface(_tb,_t,0);
        global.vhr_red_byte_idx=(buffer_peek(_tb,0,buffer_u8)>200) ? 0 : 2;
        buffer_delete(_tb);surface_free(_t);
    }
    return global.vhr_red_byte_idx;
}
function vhr_paint_colours(_spr) {
    var _w=sprite_get_width(_spr),_h=sprite_get_height(_spr),_n=sprite_get_number(_spr);
    if(_w<=0 || _h<=0 || _n<=0) return -1;
    var _rb=vhr_red_byte(),_bb=2-_rb;
    var _s=surface_create(_w,_h),_buf=buffer_create(_w*_h*4,buffer_fixed,1);
    var _cnt=array_create(24,0),_sr=array_create(24,0),_sg=array_create(24,0),_sb=array_create(24,0);
    var _gn=0,_gr=0,_gg=0,_gb=0,_opaque=0;
    var _frames=[0,_n div 4,_n div 2,(_n*3) div 4];
    for(var _fi=0;_fi<4;_fi++) {
        if(_fi>0 && _frames[_fi]==_frames[_fi-1]) continue;
        surface_set_target(_s);draw_clear_alpha(c_black,0);
        draw_sprite(_spr,_frames[_fi],sprite_get_xoffset(_spr),sprite_get_yoffset(_spr));
        surface_reset_target();
        buffer_get_surface(_buf,_s,0);
        for(var _y=0;_y<_h;_y+=2) for(var _x=(_y div 2) mod 2;_x<_w;_x+=2) {
            var _o=(_y*_w+_x)*4;
            if(buffer_peek(_buf,_o+3,buffer_u8)<200) continue;
            var _r=buffer_peek(_buf,_o+_rb,buffer_u8),_g=buffer_peek(_buf,_o+1,buffer_u8),_b=buffer_peek(_buf,_o+_bb,buffer_u8);
            var _mx=max(_r,_g,_b),_mn=min(_r,_g,_b);
            _opaque++;
            if(_mx<55) continue; // outlines, tyres, shadow
            if(_mx-_mn<_mx*0.15) {if(_mx>=110){_gn++;_gr+=_r;_gg+=_g;_gb+=_b;} continue;} // white/silver/grey paint
            var _bin=floor(colour_get_hue(make_colour_rgb(_r,_g,_b))*24/256) mod 24;
            _cnt[_bin]++;_sr[_bin]+=_r;_sg[_bin]+=_g;_sb[_bin]+=_b;
        }
    }
    buffer_delete(_buf);surface_free(_s);
    if(_opaque<20) return -1;
    // Main colour: the strongest hue (with its neighbours, so a hue on a bin edge is not split).
    var _best=-1,_bestv=0,_total=0;
    for(var _i=0;_i<24;_i++) {
        _total+=_cnt[_i];
        if(_cnt[_i]==0) continue;
        var _v=_cnt[_i]+0.5*(_cnt[(_i+23) mod 24]+_cnt[(_i+1) mod 24]);
        if(_v>_bestv){_bestv=_v;_best=_i;}
    }
    var _grey=_gn>0 ? make_colour_rgb(_gr/_gn,_gg/_gn,_gb/_gn) : c_white;
    if(_best<0) {
        if(_gn==0) return -1;
        return [_grey,merge_colour(_grey,c_white,0.4)];
    }
    var _main=make_colour_rgb(_sr[_best]/_cnt[_best],_sg[_best]/_cnt[_best],_sb[_best]/_cnt[_best]);
    // White, silver or grey body with coloured trim: the body is the main colour, the trim the second.
    if(_gn>0 && _gn>=_cnt[_best]*0.85) return [_grey,_main];
    // Second colour: the next strong hue at least 45 degrees away, else white/grey striping, else a lighter main.
    var _sec=-1,_secv=0;
    for(var _i=0;_i<24;_i++) {
        var _d=abs(_i-_best);_d=min(_d,24-_d);
        if(_d>=3 && _cnt[_i]>_secv && _cnt[_i]>=_cnt[_best]*0.12){_secv=_cnt[_i];_sec=_i;}
    }
    var _second;
    if(_sec>=0) _second=make_colour_rgb(_sr[_sec]/_cnt[_sec],_sg[_sec]/_cnt[_sec],_sb[_sec]/_cnt[_sec]);
    else if(_gn>0 && _gn>=_cnt[_best]*0.25) _second=_grey;
    else _second=merge_colour(_main,c_white,0.35);
    return [_main,_second];
}
// obj_camera Step (view 0): rebuild the cockpit when the player's car, skin or the option changes.
function vhr_cockpit_paint_update() {
    var _on=!variable_global_exists("vhr_cockpit_paint") || global.vhr_cockpit_paint;
    var _key="classic";
    if(_on && instance_exists(target) && variable_instance_exists(target,"spritebody") && sprite_exists(target.spritebody)) _key=string(target.spritebody);
    if(_key==vhr_paint_key) return;
    vhr_paint_key=_key;
    if(_key=="classic"){vhr_build_cockpit(-1);vhr_driver_paint(-1);return;}
    if(!variable_global_exists("vhr_paint_cache")) global.vhr_paint_cache=ds_map_create();
    var _p=ds_map_find_value(global.vhr_paint_cache,_key);
    var _name=sprite_get_name(target.spritebody);
    if(is_undefined(_p)) _p=vhr_paint_prebaked(_name);
    if(is_undefined(_p)) {
        _p=vhr_paint_colours(target.spritebody);
        ds_map_set(global.vhr_paint_cache,_key,_p);
        if(is_array(_p)) show_debug_message("VHRVR: cockpit paint from "+sprite_get_name(target.spritebody)+": "+string(_p[0])+" / "+string(_p[1]));
    }
    vhr_build_cockpit(_p);
    var _pre=vhr_driver_prebaked(_name);
    if(_pre!=-1 && sprite_exists(_pre)) vhr_driver_use(_pre); else vhr_driver_paint(_p);
}
function vhr_driver_use(_spr) {
    if(!variable_instance_exists(id,"vhr_driver_base")) vhr_driver_base=vhr_driver_sprite;
    if(_spr!=vhr_driver_sprite){vhr_driver_sprite=_spr;vhr_build_driver();}
}
// Driving gloves and sleeves: the pink takes the car's main colour and the teal trim its second colour.
// Only the glove and sleeve areas of the driver art are touched (not the wheel or skin).
function vhr_glove_sprite(_base,_paint) {
    var _w=sprite_get_width(_base),_h=sprite_get_height(_base);
    var _surf=surface_create(_w,_h);
    surface_set_target(_surf);draw_clear_alpha(c_black,0);
    gpu_set_blendenable(false);draw_sprite(_base,0,sprite_get_xoffset(_base),sprite_get_yoffset(_base));gpu_set_blendenable(true);
    surface_reset_target();
    var _buf=buffer_create(_w*_h*4,buffer_fixed,1);buffer_get_surface(_buf,_surf,0);
    var _rb=vhr_red_byte(),_bb=2-_rb,_sx=_w/1024,_sy=_h/559;
    var _cols=[[colour_get_red(_paint[0]),colour_get_green(_paint[0]),colour_get_blue(_paint[0]),0.71],
               [colour_get_red(_paint[1]),colour_get_green(_paint[1]),colour_get_blue(_paint[1]),0.4]];
    var _rects=[[255,55,445,285],[575,55,765,285]];
    for(var _ri=0;_ri<2;_ri++) {
        var _rc=_rects[_ri];
        var _x0=floor(_rc[0]*_sx),_x1=min(_w,ceil(_rc[2]*_sx)),_y0=floor(_rc[1]*_sy),_y1=min(_h,ceil(_rc[3]*_sy));
        for(var _y=_y0;_y<_y1;_y++) for(var _x=_x0;_x<_x1;_x++) {
            var _o=(_y*_w+_x)*4;
            if(buffer_peek(_buf,_o+3,buffer_u8)<16) continue;
            var _r=buffer_peek(_buf,_o+_rb,buffer_u8),_g=buffer_peek(_buf,_o+1,buffer_u8),_b=buffer_peek(_buf,_o+_bb,buffer_u8);
            var _mx=max(_r,_g,_b),_mn=min(_r,_g,_b);
            if(_mx<31 || _mx-_mn<_mx*0.3) continue;
            var _hue=colour_get_hue(make_colour_rgb(_r,_g,_b)),_t;
            if(_hue>=200 && _hue<=250) _t=_cols[0];      // pink glove
            else if(_hue>=95 && _hue<=150) _t=_cols[1];  // teal trim
            else continue;
            var _f=(_mx/255)/_t[3],_up=_f>1 ? min(1,(_f-1)*0.5) : 0;
            var _nr=min(255,_t[0]*_f),_ng=min(255,_t[1]*_f),_nb=min(255,_t[2]*_f);
            _nr+=(255-_nr)*_up;_ng+=(255-_ng)*_up;_nb+=(255-_nb)*_up;
            buffer_poke(_buf,_o+_rb,buffer_u8,_nr);buffer_poke(_buf,_o+1,buffer_u8,_ng);buffer_poke(_buf,_o+_bb,buffer_u8,_nb);
        }
    }
    if(_w==1024 && _h==559) vhr_sleeves(_buf,_w,_h,_rb,_bb,_paint);
    buffer_set_surface(_buf,_surf,0);
    var _spr=sprite_create_from_surface(_surf,0,0,_w,_h,false,false,0,0);
    buffer_delete(_buf);surface_free(_surf);
    return _spr;
}
// obj_camera: switch the driver art to gloves in the car's colours (-1: the original pink/teal).
function vhr_driver_paint(_paint) {
    if(!variable_instance_exists(id,"vhr_driver_base")) vhr_driver_base=vhr_driver_sprite;
    if(!sprite_exists(vhr_driver_base)) return;
    var _target=vhr_driver_base;
    if(is_array(_paint)) {
        if(!variable_global_exists("vhr_glove_cache")) global.vhr_glove_cache=ds_map_create();
        var _k=string(_paint[0])+"_"+string(_paint[1]);
        var _s=ds_map_find_value(global.vhr_glove_cache,_k);
        if(is_undefined(_s) || !sprite_exists(_s)){_s=vhr_glove_sprite(vhr_driver_base,_paint);ds_map_set(global.vhr_glove_cache,_k,_s);}
        _target=_s;
    }
    if(_target!=vhr_driver_sprite){vhr_driver_sprite=_target;vhr_build_driver();}
}

// Racing sleeves: longer (down past the elbow) and with a design that suits the car's main colour:
// red/orange flames, yellow or white/grey checkered band, green lightning bolt, blue/cyan racing
// stripes, purple/pink chevrons. Worked out in arm coordinates: _a runs from the hem toward the
// shoulder, _u across the arm (-1..1). The original art's shading is kept.
function vhr_sleeve_design(_main) {
    if(colour_get_saturation(_main)<38) return 1;
    var _h=colour_get_hue(_main);
    if(_h<24 || _h>=240) return 0; // flames
    if(_h<50) return 1;            // checkered
    if(_h<110) return 2;           // lightning bolt
    if(_h<180) return 3;           // racing stripes
    return 4;                      // chevrons
}
function vhr_sleeve_colour(_d,_a,_u,_m,_s) {
    static _ink=[20,20,30],_white=[245,245,245];
    if(_a<7) return _a>=2 ? _s : _ink; // hem trim
    switch(_d) {
        case 0: {
            var _fh=95+38*sin(_u*7.3+1)+22*sin(_u*17.1)+12*sin(_u*31.7),_dd=233-_a;
            if(_dd<_fh) {
                var _t=_dd/max(1,_fh);
                if(_t<0.55) {
                    var _k=0.55*(1-min(1,_t*1.6));
                    return [_s[0]+(255-_s[0])*_k,_s[1]+(240-_s[1])*_k,_s[2]+(120-_s[2])*_k];
                }
                return _s;
            }
            return _m;
        }
        case 1:
            if(_a>60 && _a<108) {
                if(_a<64 || _a>104) return _s;
                return ((floor((_a-64)/11)+floor((_u+1)*6.5)) mod 2) ? _ink : _white;
            }
            return _m;
        case 2: {
            var _z=(_a/38) mod 2,_c=((_z<1 ? _z : 2-_z)*2-1)*0.45,_du=abs(_u-_c);
            if(_du<0.11) return _s;
            if(_du<0.16) return _ink;
            return _m;
        }
        case 3: {
            var _au=abs(_u);
            if(_au>0.14 && _au<0.32) return _s;
            if(_au>0.34 && _au<0.39) return _white;
            return _m;
        }
        case 4:
            if(_a>20 && (floor((_a-abs(_u)*55)/26) mod 2)==0) return _s;
            return _m;
    }
    return _m;
}
function vhr_sleeves(_buf,_w,_h,_rb,_bb,_paint) {
    var _m=[colour_get_red(_paint[0]),colour_get_green(_paint[0]),colour_get_blue(_paint[0])];
    var _s=[colour_get_red(_paint[1]),colour_get_green(_paint[1]),colour_get_blue(_paint[1])];
    var _d=vhr_sleeve_design(_paint[0]);
    for(var _y=340;_y<_h;_y++) for(var _xm=0;_xm<=360;_xm++) {
        var _along=-0.53*_xm+0.848*_y;
        if(_along<228) continue;
        for(var _side=0;_side<2;_side++) {
            var _x=_side ? _w-1-_xm : _xm,_o=(_y*_w+_x)*4;
            if(buffer_peek(_buf,_o+3,buffer_u8)<16) continue;
            var _r=buffer_peek(_buf,_o+_rb,buffer_u8),_g=buffer_peek(_buf,_o+1,buffer_u8),_b=buffer_peek(_buf,_o+_bb,buffer_u8);
            var _mx=max(_r,_g,_b),_mn=min(_r,_g,_b);
            if(_mx<70) {
                // Keep the arm's outline; a dark line inside the sleeve (the old cuff edge) becomes fabric.
                var _edge=false;
                for(var _k=1;_k<=2 && !_edge;_k++) {
                    if(_x-_k<0 || buffer_peek(_buf,((_y*_w)+_x-_k)*4+3,buffer_u8)<16) _edge=true;
                    else if(_x+_k>=_w || buffer_peek(_buf,((_y*_w)+_x+_k)*4+3,buffer_u8)<16) _edge=true;
                    else if(_y-_k<0 || buffer_peek(_buf,(((_y-_k)*_w)+_x)*4+3,buffer_u8)<16) _edge=true;
                    else if(_y+_k>=_h || buffer_peek(_buf,(((_y+_k)*_w)+_x)*4+3,buffer_u8)<16) _edge=true;
                }
                if(_edge) continue;
            }
            var _c=vhr_sleeve_colour(_d,_along-228,((0.848*_xm+0.53*_y)-396)/72,_m,_s);
            var _pink=_mx-_mn>_mx*0.3 && colour_get_hue(make_colour_rgb(_r,_g,_b))>=200;
            var _f=_mx>=70 ? (_mx/255)/(_pink ? 0.85 : 0.94) : 0.8;
            _f=clamp(_f,0.55,1.12);
            var _up=max(0,_f-1),_nr=min(255,_c[0]*_f),_ng=min(255,_c[1]*_f),_nb=min(255,_c[2]*_f);
            _nr+=(255-_nr)*_up;_ng+=(255-_ng)*_up;_nb+=(255-_nb)*_up;
            buffer_poke(_buf,_o+_rb,buffer_u8,_nr);buffer_poke(_buf,_o+1,buffer_u8,_ng);buffer_poke(_buf,_o+_bb,buffer_u8,_nb);
        }
    }
}

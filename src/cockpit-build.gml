// Builds the cockpit mesh. _paint: -1 for the classic purple/teal interior, or [main, second] car colours.
function vhr_build_cockpit(_paint) {
    if(variable_instance_exists(id,"vhr_mesh") && vhr_mesh!=-1) vertex_delete_buffer(vhr_mesh);
    vhr_mesh=vertex_create_buffer();vertex_begin(vhr_mesh,vhr_format);
    // All coordinates are chassis-local: +X forward, +Y passenger side, -Z up.
    // Solid stylized geometry, inspired by the supplied purple/teal rally interior.
    var _ink=make_colour_rgb(14,15,25),_dash=make_colour_rgb(43,42,64),_panel=make_colour_rgb(65,59,89);
    var _purple=make_colour_rgb(97,54,129),_teal=make_colour_rgb(48,172,173),_metal=make_colour_rgb(145,156,164);
        var _hood=_teal,_stripe=make_colour_rgb(235,101,68);
        if(is_array(_paint)) {
            // Trim takes the main paint (a little darker, it is inside the car); strips take the second colour.
            _purple=merge_colour(_paint[0],c_black,0.18);_teal=_paint[1];_hood=_paint[0];_stripe=_paint[1];
        }
    vhr_box(vhr_mesh,-23,-19,-2,27,19,1,_ink);
    vhr_box(vhr_mesh,-23,-20,-14,26,-18,0,_purple);
    vhr_box(vhr_mesh,-23,18,-14,26,20,0,_purple);
    // Door cards, contrasting strips, armrests and handles.
    for(var _side=-1;_side<=1;_side+=2) {
        var _yy=_side*17.8;
        vhr_box(vhr_mesh,-17,_yy-0.4,-12,17,_yy+0.4,-3,_dash);
        vhr_box(vhr_mesh,-18,_yy-0.5,-13.5,22,_yy+0.5,-12.6,_teal);
        vhr_softbox(vhr_mesh,-7,_yy-1,-8,9,_yy+1,-6.8,_panel);
        vhr_box(vhr_mesh,5,_yy-0.6,-11,9,_yy+0.6,-10.3,_metal);
        vhr_box(vhr_mesh,-23,_side*19-0.7,-32,12,_side*19+0.7,-30.8,_teal);
        // Windshield pillars stay attached to the body when the head turns.
        vhr_pillar(vhr_mesh,_side*18,0.85,_ink);
        vhr_pillar(vhr_mesh,_side*18,0.55,_purple);
    }
    vhr_box(vhr_mesh,-23,-19,-34,13,19,-32.5,_dash);
    vhr_box(vhr_mesh,10,-19,-32,13,19,-29.5,_ink);
    vhr_box(vhr_mesh,9.8,-18,-31.4,10,18,-30.3,_teal);
    // Windshield mirror bezel and roof stem.
    vhr_softbox(vhr_mesh,9.1,-0.3,-27.3,9.7,8.3,-24.2,_ink);
    vhr_box(vhr_mesh,9.5,3.7,-30.5,10.1,4.3,-27,_metal);
    // Deep dashboard and raised instrument binnacle below the windshield.
    vhr_softbox(vhr_mesh,14,-18,-13.7,27,18,-5.5,_ink);
    vhr_softbox(vhr_mesh,14.1,-17.6,-13.2,26.8,17.6,-6,_dash);
    vhr_softbox(vhr_mesh,12.5,-11,-15.8,19,3,-9.4,_ink);
    vhr_box(vhr_mesh,12.3,-10.6,-15.4,12.5,2.6,-9.7,_panel);
    vhr_gauge(vhr_mesh,12.2,-5.4,-12.5,2.65);
    vhr_gauge(vhr_mesh,12.2,0,-12.4,1.5);
    // Vents at both ends and passenger side, with slats.
    for(var _vent=0;_vent<3;_vent++) {
        var _vy=-15+_vent*14;
        vhr_box(vhr_mesh,13.7,_vy-1.8,-12.5,14,_vy+1.8,-9,_ink);
        for(var _slat=0;_slat<5;_slat++) vhr_box(vhr_mesh,13.5,_vy-1.5,-12.1+_slat*0.55,13.7,_vy+1.5,-11.95+_slat*0.55,_metal);
    }
    // Center stack, stereo slot, switches, center tunnel and gear lever.
    // Frame for the live GPS/lap display, facing the driver.
    vhr_box(vhr_mesh,8.4,3.8,-14,9,13.4,-4.4,_ink);
    vhr_softbox(vhr_mesh,9,4,-10.5,15,10,-1.7,_ink);
    vhr_box(vhr_mesh,8.8,4.3,-10.1,9,9.7,-3,_panel);
    vhr_box(vhr_mesh,8.6,4.8,-9.4,8.8,9.2,-7.6,_ink);
    vhr_box(vhr_mesh,8.5,5.2,-9,8.6,8.8,-8.6,_teal);
    vhr_box(vhr_mesh,8.4,5.1,-8.2,8.5,8.9,-7.9,_metal);
    vhr_softbox(vhr_mesh,-9,4,-4,10,10,0,_dash);
    // Translucent crystal gear-lever base is drawn in a separate pass.
    vhr_box(vhr_mesh,1.8,6.8,-8.5,2.2,7.2,-4,_metal);


    for(var _switch=0;_switch<4;_switch++) vhr_box(vhr_mesh,12.1,-10+_switch*1.1,-8.7,12.5,-9.5+_switch*1.1,-8.1,_switch==3 ? make_colour_rgb(226,65,79) : _metal);
    // Fixed steering column; the wheel itself is a separate rotating mesh.
    vhr_box(vhr_mesh,8,-4.6,-12.6,13,-3.4,-11.4,_ink);
    // Hood glimpse through windshield; no flat image attached to the headset.
    vhr_oval(vhr_mesh,33,-0.0,-10.8,12,17,2.4,_hood);
    vhr_oval(vhr_mesh,33,0,-10.9,11.8,5,2.4,_stripe);
    vertex_end(vhr_mesh);vertex_freeze(vhr_mesh);
}

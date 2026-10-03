// Victory Heat Rally VR, Quest standalone data patch (UndertaleModTool CLI script).
// Input: the ORIGINAL Steam data.win. Output: data for the GameMaker Android runner (game.droid).
// Reuses the PC mod's GML (../src) and swaps the Windows bridge for libvhrvr.so (OpenXR).
using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using UndertaleModLib.Models;
using UndertaleModLib.Compiler;
EnsureDataLoaded();
if(Data.IsYYC()) throw new Exception("VM GameMaker data required.");
string pkg=Environment.GetEnvironmentVariable("VHRVR_PACKAGE") ?? Environment.CurrentDirectory;
string src=Path.Combine(pkg,"src"), quest=Path.Combine(pkg,"quest");
string Read(string name)=>File.ReadAllText(File.Exists(Path.Combine(quest,name))?Path.Combine(quest,name):Path.Combine(src,name));
// PC bridge calls -> Quest extension functions with the same meaning.
string Q(string s){
    s=Regex.Replace(s,@"external_define\([^;]*?\)(?=;)","0");
    s=Regex.Replace(s,@"external_call\(global\.vhr_(\w+)\s*\)","vhrq_$1()");
    s=Regex.Replace(s,@"external_call\(global\.vhr_(\w+)\s*,\s*","vhrq_$1(");
    if(s.Contains("external_call")||s.Contains("external_define")) throw new Exception("Unconverted bridge call left in GML.");
    return s;
}
string R(string name)=>Q(Read(name));

// ------------------------------------------------------------- 0. GLES3 strictness: the ColMesh debug shader puts an
// #extension line after GameMaker's shader header, which Quest's compiler rejects. It only writes debug depth.
foreach(var sh in Data.Shaders){
    var f=sh.GLSL_ES_Fragment?.Content;
    if(f!=null && f.Contains("GL_EXT_frag_depth"))
        sh.GLSL_ES_Fragment=Data.Strings.MakeString(Regex.Replace(f.Replace("#extension GL_EXT_frag_depth : enable",""),@"gl_FragDepthEXT\s*=[^;]*;",""));
}

// ------------------------------------------------------------- 1. extension for libvhrvr.so
UndertaleString S(string s)=>Data.Strings.MakeString(s);
var oldExts=Data.Extensions.ToList();
uint dllKind=11;
var api=new (string name,int args)[]{
    ("vhrq_init",0),("vhrq_stop",0),("vhrq_recenter",0),("vhrq_mode",1),("vhrq_frame",0),("vhrq_poll",0),("vhrq_active",0),
    ("vhrq_value",2),("vhrq_submit",3),("vhrq_verb",2),("vhrq_axis",1),("vhrq_wheel_deg",0),("vhrq_grip",0),("vhrq_btn",1),
    ("vhrq_haptic",2),("vhrq_get",1),("vhrq_mpoll",1),("vhrq_mkey",2),("vhrq_wheel_api",0),("vhrq_wstop",0),("vhrq_wpoll",0),
    ("vhrq_wvalue",1),("vhrq_wforce",3),("vhrq_input",0),("vhrq_set",2)};
// Android runner: every non-.gml extension function is a Java call to <package>.<ClassName>.<ExtName>
// (native extension libraries are not loadable there). VHRQuest.java forwards to libvhrvr.so via JNI.
var qext=new UndertaleExtension{Name=S("VHRQuest"),ClassName=S("VHRQuest"),FolderName=S(""),Version=S("1.0.0")};
var qfile=new UndertaleExtensionFile{Filename=S("VHRQuest.ext"),Kind=UndertaleExtensionKind.Generic,InitScript=S(""),CleanupScript=S("")};
uint nextId=5000;
foreach(var (name,args) in api){
    var fn=new UndertaleExtensionFunction{Name=S(name),ExtName=S(name),ID=nextId++,Kind=dllKind,RetType=UndertaleExtensionVarType.Double};
    for(int i=0;i<args;i++) fn.Arguments.Add(new UndertaleExtensionFunctionArg(UndertaleExtensionVarType.Double));
    qfile.Functions.Add(fn);
}
// vhrq_log(string): GML breadcrumbs and errors into the bridge's log file.
{var lf=new UndertaleExtensionFunction{Name=S("vhrq_log"),ExtName=S("vhrq_log"),ID=nextId++,Kind=dllKind,RetType=UndertaleExtensionVarType.Double};
 lf.Arguments.Add(new UndertaleExtensionFunctionArg(UndertaleExtensionVarType.String));qfile.Functions.Add(lf);}
qext.Files.Add(qfile);
Data.Extensions.Add(qext);
// The compiler treats names already in the FUNC table as builtins; register ours, then rebuild its table.
foreach(var (name,_) in api) if(Data.Functions.ByName(name)==null) Data.Functions.Add(new UndertaleFunction{Name=S(name)});
if(Data.Functions.ByName("vhrq_log")==null) Data.Functions.Add(new UndertaleFunction{Name=S("vhrq_log")});
Data.BuiltinList=new BuiltinList(Data);
if(Data.BuiltinList.LookupBuiltinFunction("vhrq_submit")==null) throw new Exception("Compiler does not see the Quest extension functions.");

// ------------------------------------------------------------- 2. frame/submit object
var qobj=new UndertaleGameObject{Name=S("obj_vhrq"),Visible=true,Persistent=true,Depth=-15999};
Data.GameObjects.Add(qobj);

// ------------------------------------------------------------- 3. stubs for Windows-only extensions
var stubNames=new List<string>();
string stubs="";
foreach(var e in oldExts) foreach(var f in e.Files) foreach(var fn in f.Functions){
    string n=fn.Name.Content;stubNames.Add(n);
    string ret=fn.RetType==UndertaleExtensionVarType.String ? "\"\"" : "0";
    if(n=="steam_current_game_language"||n=="steam_get_current_game_language") ret="\"english\"";
    stubs+="function vhrq_stub_"+n+"() { return "+ret+"; }\n";
}

// ------------------------------------------------------------- 4. game code (PC mod GML, Quest bridge)
string Stock(string entry,string function) {
    string body=GetDecompiledText("gml_Object_"+entry, null, new Underanalyzer.Decompiler.DecompileSettings());
    body=Regex.Replace(body,@"UnknownEnum\.Value_(\d+)","$1");
    body=Regex.Replace(body,@"enum UnknownEnum\s*\{[^}]*\}","");
    if(entry=="obj_HUD_Draw_0") body=body.Replace("view_current != target.view_num","false");
    if(entry=="parent_pausemenu_Draw_74") body=body.Replace("options_display_menu(42,","options_display_menu((global.vhr_enabled ? 154 : 42),");
    return "function "+function+"() {\n"+body+"\n}\n";
}
string RaceStock() {
    string result="";
    foreach(string entry in new[]{"obj_count_Draw_64","obj_gameovertext_Draw_64","parent_pausemenu_Draw_74","obj_options_menu_Draw_74","obj_lapcount_Draw_64"})
        result+=Stock(entry,"vhr_gui_"+entry);
    return result;
}
// Draw-event 2D overlays shown on the VR panel (see vhr_overlay_2d).
string[] overlayEvents={"obj_goal_Draw_0","obj_pacenote_Draw_0","obj_goforbonus_Draw_0","obj_text_Draw_0","obj_dialog_box_Draw_73"};
string overlayStock="";foreach(var ev in overlayEvents) overlayStock+=Stock(ev,"vhr_ov_"+ev);
// Draw GUI events that can show while racing: drawn into the panel image (see vhr_gui_event).
string[] guiEvents={"obj_shadow_text_drawer_Draw_64","obj_continue_countdown_Draw_64","obj_gameoverlay_Draw_64","obj_OK_Draw_64","obj_autosave_complete_Draw_64","obj_car_Draw_64","obj_chief_Draw_64","obj_chief_tutorial_Draw_64","obj_confetti_Draw_64","obj_cup_fail_standings_Draw_64","obj_cup_ranking_Draw_64","obj_endoverlay_Draw_64","obj_fadetransition_Draw_64","obj_doortransition_Draw_64","obj_transition_Draw_64","obj_heat_message_Draw_64","obj_name_entry_Draw_64","obj_newchallenger_Draw_64","obj_objective_text_Draw_64","obj_race_manager_Draw_64","obj_rival_intro_Draw_64","obj_score_text_Draw_64","obj_timer_Draw_64","obj_tutorialHUD_Draw_64","obj_unlock_message_Draw_64","obj_fx_shiny_Draw_64"};
foreach(var ev in guiEvents) overlayStock+=Stock(ev,"vhr_ge_"+ev);
string stockMap=Stock("obj_HUD_Draw_64","vhr_stock_map"), stockHud=Stock("obj_HUD_Draw_0","vhr_stock_hud"), stockRace=RaceStock();
string theatre=R("theatre.gml").Replace("global.vhr_wheel_auto=true","global.vhr_wheel_auto=false");
string cameraStep=R("camera-step.gml").Replace("3072","(global.vhrq_eye*2)").Replace("1536","global.vhrq_eye")
    .Replace("gamepad_button_check_pressed_any(gp_stickl)","gamepad_button_check_pressed_any(gp_stickl) || vhrq_btn(1)")
    // Rear-view mirror: render it every other frame (30 Hz). It is a third full scene render, and the
    // game is CPU-bound on Quest; a mirror at 30 Hz looks the same.
    .Replace("view_set_visible(2,global.vhr_cockpit && surface_exists(global.vhr_mirror_surface));","view_set_visible(2,global.vhr_cockpit && surface_exists(global.vhr_mirror_surface) && (!variable_global_exists(\"vhr_mirror_ready\") || !global.vhr_mirror_ready || (obj_main.n mod 2)==0));")
    +"\nif (view == 0) vhr_cockpit_paint_update();\n";

string verbHook="if (variable_global_exists(\"vhrq_on\") && global.vhrq_on)\n    {\n        var _qv = -1;\n        switch (arg1)\n        {\n"
    +string.Join("",new[]{"accept","back","up","down","left","right","pause","gas","brake","drift","lookback"}.Select((v,i)=>"            case \""+v+"\": _qv = "+i+"; break;\n"))
    +"        }\n        // Touch controllers also show up as Android gamepads; ignore that second copy of every press.\n        if (vhrq_active())\n            return (_qv >= 0) ? (vhrq_verb(arg0, _qv) > 0) : false;\n        if (_qv >= 0 && vhrq_verb(arg0, _qv))\n            return true;\n    }\n    ";

// Decompiled event bodies can each carry the same enum declaration (e.g. e__VW); one global script
// may declare each enum only once, so keep the first.
string DedupeEnums(string code){
    var seen=new HashSet<string>();
    return Regex.Replace(code,@"enum\s+(\w+)\s*\{[^}]*\}",m=>seen.Add(m.Groups[1].Value)?m.Value:"");
}
CodeImportGroup group=new(Data){ MainThreadAction=MainThreadAction };
group.QueueReplace("gml_GlobalScript_vhrq_stubs",stubs);
group.QueueReplace("gml_GlobalScript_vhr_helpers",DedupeEnums(R("helpers.gml")+"\n"+R("sky.gml")+"\n"+R("hud.gml")+"\n"+stockMap+"\n"+stockHud+"\n"+R("chase-hud.gml")+"\n"+theatre+"\n"+R("race-gui.gml")+stockRace+"\n"+R("wheel-feedback.gml")+"\n"+R("cockpit-build.gml")+"\n"+R("cockpit-paint.gml")+"\n"+R("rumble.gml")+"\n"+R("paint-table.gml")+"\n"+overlayStock));
group.QueuePrepend("gml_Object_obj_HUD_Draw_0","if(global.vhr_enabled) { if(global.vhr_cockpit) vhr_draw_hud(); else vhr_draw_chase_hud(); exit; }");
group.QueuePrepend("gml_Object_obj_HUD_Draw_64","if(variable_global_exists(\"vhr_enabled\") && global.vhr_enabled) exit;");
group.QueueFindReplace("gml_GlobalScript_draw_parallax","var _cam = obj_main.camera[view_current];","if(variable_global_exists(\"vhr_enabled\") && global.vhr_enabled) { vhr_draw_sky(arg0,arg1); return; }\n    var _cam = obj_main.camera[view_current];");
group.QueueAppend("gml_Object_obj_camera_Create_0",R("camera-create.gml"));
group.QueueAppend("gml_Object_obj_camera_Step_0",cameraStep);
group.QueueAppend("gml_Object_obj_camera_Step_2",R("camera-seat.gml"));
group.QueueFindReplace("gml_Object_obj_camera_Draw_0","if (view_current == view)","if (view_current == view || (global.vhr_enabled && view == 0 && view_current < 3))");
group.QueueFindReplace("gml_Object_obj_camera_Draw_0","var perspective = matrix_build_projection_perspective_fov(cam.fov, aspect, 1, 20000);","var perspective = matrix_build_projection_perspective_fov(cam.fov, aspect, 1, 20000);\n"+R("camera-projection.gml"));
group.QueuePrepend("gml_Object_obj_camera_Draw_0","if(global.vhr_enabled && view!=0) exit;");
group.QueueAppend("gml_Object_obj_camera_Draw_0",R("camera-cockpit-draw.gml"));
group.QueuePrepend("gml_Object_obj_camera_Draw_73","if(global.vhr_enabled && view!=0) exit;");
// Recoloured glove sprites are shared (cached per paint); the camera frees only its own original driver art.
// Driver art sprites are shared for the whole session (prebaked, loaded once): never freed here.
group.QueuePrepend("gml_Object_obj_camera_CleanUp_0","vhr_driver_sprite=-1;\n"+R("camera-cleanup.gml"));
string hideLocal="\n    if (variable_global_exists(\"vhr_cockpit\") && global.vhr_cockpit && instance_exists(obj_camera) && obj_camera.vhr_active && instance_exists(obj_camera.target) && parent == obj_camera.target) return;";
group.QueueFindReplace("gml_GlobalScript_draw_car","function draw_car()\n{","function draw_car()\n{"+hideLocal);
group.QueueFindReplace("gml_GlobalScript_draw_car","function draw_car2()\n{","function draw_car2()\n{"+hideLocal);
group.QueuePrepend("gml_Object_obj_main_Alarm_10","if(variable_global_exists(\"vhr_enabled\") && global.vhr_enabled) exit;");
// Quest: the frame object must exist before the player controllers read input.
// GameMaker's own vsync (Choreographer) fights the headset's frame timing: 60 fps game on a 72 Hz
// display ended up at 36 fps. The headset paces frames instead.
group.QueueFindReplace("gml_Object_obj_main_Create_0","display_reset(0, 1);","display_reset(0, 0);");
group.QueueFindReplace("gml_Object_obj_options_menu_Create_0","display_reset(0, obj_main.vsync);","display_reset(0, 0);");
// Options > Video > Cockpit Colors: interior accents and hood follow your car's paint, or the classic purple/teal.
group.QueueFindReplace("gml_Object_obj_options_menu_Create_0","{\n            label: \"VSYNC\",",
    "{\n            label: \"Cockpit Colors\",\n            type: \"toggle\",\n            options: [\"Car Paint\", \"Classic\"],\n            val: global.vhr_cockpit_paint ? 0 : 1,\n            set: function()\n            {\n                global.vhr_cockpit_paint = !self.val;\n                vhrq_set(3, global.vhr_cockpit_paint);\n            },\n            cond: noone\n        }, \n        {\n            label: \"VSYNC\",");
// Options > Video: Fullscreen/Window Size mean nothing on Quest; they become Lens Fit and Foveation.
group.QueueFindReplace("gml_Object_obj_options_menu_Create_0","{\n            label: \"Fullscreen\",\n            type: \"toggle\",\n            options: [\"Off\", \"On\"],\n            val: window_get_fullscreen(),\n            \n            set: function()\n            {\n                if (!self.val)\n                {\n                    window_set_size(512 * obj_main.windowScale, 288 * obj_main.windowScale);\n                }\n                window_set_fullscreen(self.val);\n                obj_main.fullScreen = self.val;\n            },\n            \n            cond: noone\n        }, \n        {\n            label: \"Window Size\",\n            type: \"option\",\n            options: [\"512X288\", \"1024X576\", \"1536X864\"],\n            values: [1, 2, 3],\n            val: floor(clamp(obj_main.windowScale, 1, 3)),\n            \n            set: function()\n            {\n                obj_main.windowScale = self.values[self.val];\n                window_set_size(512 * obj_main.windowScale, 288 * obj_main.windowScale);\n            },\n            \n            cond: function()\n            {\n                return !window_get_fullscreen();\n            }\n        }, \n        ",
    "{\n            label: \"Lens Fit\",\n            type: \"option\",\n            options: [\"Sharp\", \"Medium\", \"Safe\"],\n            values: [2, 1, 0],\n            val: vhrq_get(4),\n            set: function()\n            {\n                vhrq_set(4, self.values[self.val]);\n            },\n            cond: noone\n        }, \n        {\n            label: \"Foveation\",\n            type: \"option\",\n            options: [\"Off\", \"Low\", \"Medium\", \"High\"],\n            values: [0, 1, 2, 3],\n            val: vhrq_get(5),\n            set: function()\n            {\n                vhrq_set(5, self.values[self.val]);\n            },\n            cond: noone\n        }, \n        ");
// Options > Controls > Steering: grab the cockpit wheel with the grips, or steer with the thumbstick.
group.QueueFindReplace("gml_Object_obj_options_menu_Create_0","{\n            label: \"Configure Controls\",",
    "{\n            label: \"Steering\",\n            type: \"toggle\",\n            options: [\"Virtual Wheel\", \"Thumbstick\"],\n            val: vhrq_get(2),\n            set: function()\n            {\n                vhrq_set(2, self.val);\n            },\n            cond: noone\n        }, \n        {\n            label: \"Configure Controls\",");
group.QueuePrepend("gml_Object_obj_main_Create_0","exception_unhandled_handler(function(_e) { vhrq_log(\"GML ERROR: \" + string(_e.longMessage) + \" | \" + string(_e.stacktrace)); return 0; }); vhrq_log(\"game start\"); global.vhrq_on = true; global.vhr_cockpit_paint = vhrq_get(3) > 0.5; global.vhrq_eye = vhrq_get(0); if(!instance_exists(obj_vhrq)) instance_create_depth(0,0,-15999,obj_vhrq);");
group.QueueAppend("gml_Object_obj_main_Create_0","vhr_theatre_boot();");
group.QueueAppend("gml_Object_obj_main_Step_0","vhr_theatre_boot();");
group.QueuePrepend("gml_Object_obj_main_CleanUp_0","if(variable_global_exists(\"vhr_theatre_ready\") && global.vhr_theatre_ready) { vhrq_stop();global.vhr_theatre_ready=false; }");
group.QueueFindReplace("gml_Object_obj_main_Draw_64","if (!global.stop && !global.finished","if (!global.vhr_enabled && !global.stop && !global.finished");
group.QueueAppend("gml_Object_obj_camera_Draw_73","if(global.vhr_enabled && view==0 && view_current==2) global.vhr_mirror_ready=true;");
group.QueueReplace("gml_Object_obj_count_Draw_64","vhr_race_gui(vhr_gui_obj_count_Draw_64);");
group.QueueReplace("gml_Object_obj_gameovertext_Draw_64","vhr_race_gui(vhr_gui_obj_gameovertext_Draw_64);");
group.QueueReplace("gml_Object_parent_pausemenu_Draw_74","vhr_race_gui(vhr_gui_parent_pausemenu_Draw_74);");
group.QueueReplace("gml_Object_obj_options_menu_Draw_74","vhr_options_backdrop(); vhr_race_gui(vhr_gui_obj_options_menu_Draw_74);");
group.QueueReplace("gml_Object_obj_lapcount_Draw_64","vhr_race_gui(vhr_gui_obj_lapcount_Draw_64);");
foreach(var ev in overlayEvents) group.QueueReplace("gml_Object_"+ev,"vhr_overlay_2d(vhr_ov_"+ev+");");
foreach(var ev in guiEvents) group.QueueReplace("gml_Object_"+ev,"vhr_gui_event(vhr_ge_"+ev+");");
// Touch controllers: game verbs (menus, pedals, drift), steering axis, rumble.
group.QueueFindReplace("gml_GlobalScript_input_check","if (steam_is_overlay_activated())",verbHook+"if (steam_is_overlay_activated())");
group.QueueFindReplace("gml_GlobalScript_input_check_axis","var _s = ds_map_find_value(obj_main.input_axis_map, arg0);","if (arg0 == \"hstick\" && variable_global_exists(\"vhrq_on\") && global.vhrq_on && vhrq_active())\n        return vhrq_axis(0);\n    var _s = ds_map_find_value(obj_main.input_axis_map, arg0);");
group.QueueFindReplace("gml_GlobalScript_controller_vibrate","var controller = global.controller[arg0];","if (arg0 == 0 && variable_global_exists(\"vhrq_on\") && global.vhrq_on && obj_main.controllerVibrate)\n        vhrq_haptic(arg1, arg2);\n    var controller = global.controller[arg0];");
group.QueueAppend("gml_Object_obj_car_Step_0","with(obj) vhr_quest_rumble();");
group.QueueReplace("gml_Object_obj_vhrq_Step_1",Read("frame-begin-step.gml"));
group.QueueReplace("gml_Object_obj_vhrq_Step_2",Read("input-end-step.gml"));
group.QueueReplace("gml_Object_obj_vhrq_Draw_75","vhr_gui_compose();\n"+Read("submit-gui-end.gml"));
group.Import();

// ------------------------------------------------------------- 5. point Steam/ImGui calls at the stubs, drop the DLLs
var redirect=new Dictionary<UndertaleFunction,UndertaleFunction>();
foreach(var n in stubNames){
    var oldF=Data.Functions.ByName(n);var newF=Data.Functions.ByName("gml_Script_vhrq_stub_"+n);
    if(oldF!=null && newF!=null) redirect[oldF]=newF;
}
int patched=0;
foreach(var code in Data.Code) foreach(var ins in code.Instructions)
    if(ins.ValueFunction!=null && redirect.TryGetValue(ins.ValueFunction,out var nf)){ins.ValueFunction=nf;patched++;}
foreach(var f in redirect.Keys) Data.Functions.Remove(f);
foreach(var e in oldExts) Data.Extensions.Remove(e);
uint id=1;foreach(var e in Data.Extensions) foreach(var f in e.Files) foreach(var fn in f.Functions) fn.ID=id++;
var extn=Data.FORM.EXTN;
if(extn.productIdData!=null){extn.productIdData.Clear();foreach(var e in Data.Extensions) extn.productIdData.Add(new byte[16]);}
var leftover=Data.Functions.Where(f=>stubNames.Contains(f.Name.Content)).Select(f=>f.Name.Content).ToList();
ScriptMessage("Quest patch: "+patched+" Steam/ImGui call sites stubbed, "+redirect.Count+" functions, leftovers: "+string.Join(",",leftover));

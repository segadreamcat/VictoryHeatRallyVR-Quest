// VHRQ: Victory Heat Rally VR, Quest standalone bridge.
// Loaded by the GameMaker Android runner as a native extension (libvhrvr.so).
// Every exported function is called on the runner's GL thread, once per game frame.
//
// Frame contract (one OpenXR frame per game step):
//   vhrq_frame()              Begin Step: begin frame (waiting first if needed), locate views
//   vhrq_input()              End Step: sync Touch input once per game step
//   vhrq_poll()/vhrq_value()  camera code reads recentered eye poses (same layout as VHRVR.dll)
//   vhrq_submit(stereo,w,h)   Draw GUI End: copy the bound framebuffer into swapchains, end frame,
//                             then wait for the next headset frame (early_wait)

#define XR_USE_PLATFORM_ANDROID 1
#define XR_USE_GRAPHICS_API_OPENGL_ES 1
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <math.h>
#include <dlfcn.h>
#include <jni.h>
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <openxr/openxr.h>
#include <openxr/openxr_platform.h>
#include <openxr/openxr_loader_negotiation.h>
#include <elf.h>
#include <link.h>

#define API static double
#define TAG "VHRQ"
extern int __android_log_print(int prio, const char* tag, const char* fmt, ...);
extern int snprintf(char* s, size_t n, const char* fmt, ...);
extern int open(const char* path, int flags, ...);
extern long read(int fd, void* buf, size_t n);
extern int close(int fd);
extern long write(int fd, const void* buf, size_t n);
struct timespec_q{long tv_sec;long tv_nsec;};
extern int clock_gettime(int clk, struct timespec_q* ts);
extern int dl_iterate_phdr(int (*cb)(struct dl_phdr_info*,size_t,void*),void* data);
extern int mprotect(void* addr,size_t len,int prot);
static double nowMs(void){struct timespec_q t;clock_gettime(1,&t);return t.tv_sec*1000.0+t.tv_nsec/1e6;}
// Everything logged also goes to <external files>/vhrq-log.txt (get-log.bat pulls it): Horizon OS
// may hide third-party app output from logcat.
static void fileLog(int prio,const char* fmt,...);
#define LOGI(...) do{__android_log_print(4, TAG, __VA_ARGS__);fileLog(4,__VA_ARGS__);}while(0)
#define LOGW(...) do{__android_log_print(5, TAG, __VA_ARGS__);fileLog(5,__VA_ARGS__);}while(0)
#define LOGE(...) do{__android_log_print(6, TAG, __VA_ARGS__);fileLog(6,__VA_ARGS__);}while(0)

#ifndef GL_FRAMEBUFFER_SRGB_EXT
#define GL_FRAMEBUFFER_SRGB_EXT 0x8DB9
#endif

// ---------------------------------------------------------------- config
static struct {
    int eye_size;          // per-eye render size the GML side-by-side surface uses
    float wheel_lock;      // wheel degrees for full steering lock (cockpit art turns hstick*100)
    float wheel_x, wheel_y, wheel_z; // one-hand wheel center, meters from recentered head
    float wheel_return;    // seconds for the released wheel to return to center
    int flip_stereo, flip_theatre;
    float theatre_dist, theatre_width;
    float trigger_on;      // trigger travel that counts as pressed
    int haptics, stick_steer;
    float haptic_scale;
    int theatre_bound;     // 0: menus come from the window framebuffer (0); 1: whatever GameMaker has bound
    float refresh;         // display refresh rate to request (0 = headset default)
    int perf;              // ask for sustained-high CPU/GPU clocks
    int early_wait;        // wait for the next headset frame right after submitting (overlaps GameMaker's own frame limiter)
    int swap_interval;     // eglSwapInterval for GameMaker's (invisible) window surface; -1 leaves it alone
    int swap_skip;         // GameMaker's window swap while in VR: 0 keep, 1 skip, 2 skip if it blocks (auto)
    int steer_mode;        // 0 virtual wheel (grab it with the grips), 1 thumbstick (options menu: Controls > Steering).
                           // Every launch starts on the thumbstick; the menu choice lasts until the game closes.
    int sharpen;           // compositor sharpening: 0 off, 1 eyes normal + menus quality, 2 quality everywhere
    int pace_60;           // hold the game at exactly 60 steps/s (GameMaker's own vsync pacing is switched off in VR)
    int cockpit_paint;     // cockpit accents follow the car's paint (options menu: Video > Cockpit Colors)
    int pace_overlap;      // 120 Hz: game logic runs during the repeat frame, drawing during the real one
    int fov_symmetric;     // lens fit (options menu: Video > Lens Fit): 0 Safe (centred frustum), 1 Medium (off-centre
                           // left/right only), 2 Sharp (off-centre both ways, GameMaker's GL vertical flip corrected)
    int foveation;         // fixed foveated rendering of the game image (GL_QCOM_texture_foveated): 0 off .. 3 high
    int dyn_res;           // lower/raise the render size every few seconds to hold 60 game frames a second
    int eye_min;           // smallest render size dynamic resolution may use
} cfg = {0, 100.f, 0.f, -0.32f, -0.42f, 0.12f, 1, 0, 4.0f, 3.2f, 0.30f, 1, 1, 1.6f, 0, 120.f, 1, 1, 0, 2, 1, 1, 1, 1, 1, 1, 2, 1, 1152};

static int parse_int(const char* s){int v=0,neg=0;while(*s==' ')s++;if(*s=='-'){neg=1;s++;}while(*s>='0'&&*s<='9')v=v*10+(*s++-'0');return neg?-v:v;}
static float parse_float(const char* s){
    float v=0,f=0.1f;int neg=0;while(*s==' ')s++;if(*s=='-'){neg=1;s++;}
    while(*s>='0'&&*s<='9')v=v*10+(*s++-'0');
    if(*s=='.'){s++;while(*s>='0'&&*s<='9'){v+=(*s++-'0')*f;f*=0.1f;}}
    return neg?-v:v;
}
static void set_key(const char* k,const char* v){
    if(!strcmp(k,"eye_size")) cfg.eye_size=parse_int(v);
    else if(!strcmp(k,"wheel_lock")) cfg.wheel_lock=parse_float(v);
    else if(!strcmp(k,"wheel_x")) cfg.wheel_x=parse_float(v);
    else if(!strcmp(k,"wheel_y")) cfg.wheel_y=parse_float(v);
    else if(!strcmp(k,"wheel_z")) cfg.wheel_z=parse_float(v);
    else if(!strcmp(k,"wheel_return")) cfg.wheel_return=parse_float(v);
    else if(!strcmp(k,"flip_stereo")) cfg.flip_stereo=parse_int(v);
    else if(!strcmp(k,"flip_theatre")) cfg.flip_theatre=parse_int(v);
    else if(!strcmp(k,"theatre_dist")) cfg.theatre_dist=parse_float(v);
    else if(!strcmp(k,"theatre_width")) cfg.theatre_width=parse_float(v);
    else if(!strcmp(k,"trigger_on")) cfg.trigger_on=parse_float(v);
    else if(!strcmp(k,"haptics")) cfg.haptics=parse_int(v);
    else if(!strcmp(k,"haptic_scale")) cfg.haptic_scale=parse_float(v);
    else if(!strcmp(k,"stick_steer")) cfg.stick_steer=parse_int(v);
    else if(!strcmp(k,"theatre_bound")) cfg.theatre_bound=parse_int(v);
    else if(!strcmp(k,"refresh")) cfg.refresh=parse_float(v);
    else if(!strcmp(k,"perf")) cfg.perf=parse_int(v);
    else if(!strcmp(k,"early_wait")) cfg.early_wait=parse_int(v);
    else if(!strcmp(k,"swap_interval")) cfg.swap_interval=parse_int(v);
    else if(!strcmp(k,"swap_skip")) cfg.swap_skip=parse_int(v);
    else if(!strcmp(k,"steer_mode")) cfg.steer_mode=parse_int(v)?1:0;
    else if(!strcmp(k,"sharpen")) cfg.sharpen=parse_int(v);
    else if(!strcmp(k,"pace_60")) cfg.pace_60=parse_int(v);
    else if(!strcmp(k,"dyn_res")) cfg.dyn_res=parse_int(v);
    else if(!strcmp(k,"eye_min")) cfg.eye_min=parse_int(v);
    else if(!strcmp(k,"fov_symmetric")||!strcmp(k,"lens_fit")) cfg.fov_symmetric=parse_int(v);
    else if(!strcmp(k,"foveation")) cfg.foveation=parse_int(v);
    else if(!strcmp(k,"pace_overlap")) cfg.pace_overlap=parse_int(v);
    else if(!strcmp(k,"cockpit_paint")) cfg.cockpit_paint=parse_int(v)?1:0;
    else { LOGW("unknown config key %s",k); return; }
    LOGI("config %s=%s",k,v);
}
static char cfgDir[256];
#include <stdarg.h>
extern int vsnprintf(char* s,size_t n,const char* fmt,va_list ap);
static int logFd=-1;
static void fileLog(int prio,const char* fmt,...){
    if(!cfgDir[0])return;
    if(logFd<0){
        char path[320],prev[320];snprintf(path,sizeof path,"%s/vhrq-log.txt",cfgDir);snprintf(prev,sizeof prev,"%s/vhrq-log-previous.txt",cfgDir);
        extern int rename(const char*,const char*);rename(path,prev); // keep the last launch's log (crash reports survive a relaunch)
        logFd=open(path,0x241,0644); // O_WRONLY|O_CREAT|O_TRUNC: one log per launch
        if(logFd<0)return;
    }
    char line[1024];struct timespec_q t;clock_gettime(1,&t);
    int n=snprintf(line,sizeof line,"%ld.%03ld %c ",t.tv_sec,t.tv_nsec/1000000,prio>=6?'E':prio==5?'W':'I');
    va_list a;va_start(a,fmt);int m=vsnprintf(line+n,sizeof(line)-n-2,fmt,a);va_end(a);
    if(m<0)m=0;n+=m;if(n>(int)sizeof(line)-2)n=sizeof(line)-2;line[n++]='\n';
    write(logFd,line,n);
}
static void load_file(const char* name){
    char path[320];snprintf(path,sizeof path,"%s/%s",cfgDir,name);
    int fd=open(path,0);
    if(fd<0){LOGI("no config at %s (defaults)",path);return;}
    static char buf[4096];long n=read(fd,buf,sizeof(buf)-1);close(fd);if(n<=0)return;buf[n]=0;
    char* line=buf;
    while(*line){
        char* end=line;while(*end && *end!='\n' && *end!='\r')end++;
        char save=*end;*end=0;
        char* eq=strchr(line,'=');
        if(line[0]!='#' && eq){*eq=0;char* k=line;while(*k==' ')k++;char* ke=eq-1;while(ke>k && *ke==' ')*ke--=0;set_key(k,eq+1);}
        *end=save;line=end;while(*line=='\n'||*line=='\r')line++;
    }
}
static int cfgLoaded=0;
static void load_config(void){
    if(cfgLoaded)return;cfgLoaded=1;
    char pkg[128]={0};
    int fd=open("/proc/self/cmdline",0);
    if(fd>=0){read(fd,pkg,sizeof(pkg)-1);close(fd);}
    for(char*p=pkg;*p;p++) if(*p==':'){*p=0;break;}
    snprintf(cfgDir,sizeof cfgDir,"/sdcard/Android/data/%s/files",pkg);
    load_file("vhrq.txt");
    load_file("vhrq-theatre.txt"); // menu screen distance picked in the headset (grip + stick)
    int keepSteer=cfg.steer_mode;
    load_file("vhrq-settings.txt"); // choices made in the game's options menu
    cfg.steer_mode=keepSteer;       // older builds saved the steering choice there; launches now start on the thumbstick
}
static void save_theatre(void){
    char path[320],line[64];snprintf(path,sizeof path,"%s/vhrq-theatre.txt",cfgDir);
    int fd=open(path,0x241,0644);if(fd<0){LOGW("cannot save %s",path);return;}
    int n=snprintf(line,sizeof line,"theatre_dist=%.2f\n",cfg.theatre_dist);write(fd,line,n);close(fd);
    LOGI("saved theatre_dist=%.2f",cfg.theatre_dist);
}
static void save_settings(void){
    char path[320],line[64];snprintf(path,sizeof path,"%s/vhrq-settings.txt",cfgDir);
    int fd=open(path,0x241,0644);if(fd<0){LOGW("cannot save %s",path);return;}
    char big[160];int n=snprintf(big,sizeof big,"cockpit_paint=%d\nlens_fit=%d\nfoveation=%d\n",cfg.cockpit_paint,cfg.fov_symmetric,cfg.foveation);(void)line;write(fd,big,n);close(fd);
    LOGI("saved cockpit_paint=%d",cfg.cockpit_paint);
}

// ---------------------------------------------------------------- OpenXR state
static PFN_xrGetInstanceProcAddr gipa;
#define XRFN(name) static PFN_##name p_##name
XRFN(xrCreateInstance);XRFN(xrDestroyInstance);XRFN(xrGetSystem);XRFN(xrEnumerateInstanceExtensionProperties);
XRFN(xrCreateSession);XRFN(xrDestroySession);XRFN(xrBeginSession);XRFN(xrEndSession);XRFN(xrRequestExitSession);
XRFN(xrPollEvent);XRFN(xrWaitFrame);XRFN(xrBeginFrame);XRFN(xrEndFrame);XRFN(xrLocateViews);XRFN(xrLocateSpace);
XRFN(xrCreateReferenceSpace);XRFN(xrCreateSwapchain);XRFN(xrEnumerateSwapchainFormats);XRFN(xrEnumerateSwapchainImages);
XRFN(xrAcquireSwapchainImage);XRFN(xrWaitSwapchainImage);XRFN(xrReleaseSwapchainImage);XRFN(xrEnumerateViewConfigurationViews);
XRFN(xrCreateActionSet);XRFN(xrCreateAction);XRFN(xrStringToPath);XRFN(xrSuggestInteractionProfileBindings);
XRFN(xrCreateActionSpace);XRFN(xrAttachSessionActionSets);XRFN(xrSyncActions);XRFN(xrGetActionStateFloat);
XRFN(xrGetActionStateBoolean);XRFN(xrGetActionStateVector2f);XRFN(xrApplyHapticFeedback);XRFN(xrGetOpenGLESGraphicsRequirementsKHR);
XRFN(xrInitializeLoaderKHR);
XRFN(xrDestroySwapchain);XRFN(xrPerfSettingsSetPerformanceLevelEXT);XRFN(xrEnumerateDisplayRefreshRatesFB);XRFN(xrRequestDisplayRefreshRateFB);XRFN(xrGetDisplayRefreshRateFB);

static XrInstance inst;static XrSystemId sysId;static XrSession sess;
static XrSpace localSpace,viewSpace;
static XrSessionState sstate=XR_SESSION_STATE_UNKNOWN;
static int running=0,frameBegun=0,shouldRender=0,sceneMode=0,exitRequested=0;
static XrTime predicted=0;
static XrView views[2],headViews[2];
static int poseValid=0;
static int lastError=0;

typedef struct {XrSwapchain sc;uint32_t n;uint32_t tex[4];int w,h;} Chain;
static Chain eyeChain[2],quadChain;
static int64_t scFormat=0;static int srgbControl=0;
static GLuint blitFbo=0;

// recentered pose exposed to GML (OpenVR 3x4 row-major layout)
static float eyePose[2][12],center[3],yawCenter;static int recenter=1,quadRecenter=1;
static XrPosef quadPose;static float quadYaw,quadOrigin[3];static int theatreAdjusting=0;
// frame timing (logged every few seconds)
static double tBegin,tSubmitEnd,accWait,accGame,accRunner,accSwap,accSleep,statStart;static int statFrames;
// frame pacing: at 120 Hz each game step is shown for two headset frames (exactly 60 steps/s)
static int repeatN=1,hasLayerSettings=0;
// Overlapped 120 Hz pacing: the last real frame's layers are re-submitted for the in-between headset frame.
static XrCompositionLayerProjectionView lastPv[2];static XrCompositionLayerProjection lastProj;static XrCompositionLayerQuad lastQuad;
static XrCompositionLayerSettingsFB lastEyeSet,lastQuadSet;static const XrCompositionLayerBaseHeader* lastLayer=0;static int lastValid=0,repeatPending=0,overlapStep=0;
static GLuint fovTex=0;static int fovSupported=-1;
typedef void (*PFN_fovQCOM)(GLuint,GLuint,GLuint,GLfloat,GLfloat,GLfloat,GLfloat,GLfloat);static PFN_fovQCOM p_fovParams=0;
static XrFovf renderFov[2]; // frustum the game is told to render (may differ in sign handling from the submitted one)
static int renderEye=0,goodWindows=0,badWindows=0; // dynamic resolution: current render size per eye (swapchains stay at cfg.eye_size)
static int hitches=0;static double maxStep=0,prevBegin=0;static XrTime locateTime=0;static float displayHz=0;static double lastBeginMs=0;static unsigned long glThread=0;static int waited=0,nextShouldRender=0;static XrTime nextPredicted=0;

// ---------------------------------------------------------------- input
static XrActionSet aset;
static XrAction aGrip,aTrigger,aStick,aPose,aHaptic,aA,aB,aX,aY,aMenu,aStickClickL,aStickClickR;
static XrPath hand[2];static XrSpace gripSpace[2];
enum {V_ACCEPT,V_BACK,V_UP,V_DOWN,V_LEFT,V_RIGHT,V_PAUSE,V_GAS,V_BRAKE,V_DRIFT,V_LOOKBACK,V_COUNT};
static int verbNow[V_COUNT],verbPrev[V_COUNT];
static int viewTogglePressed=0;
static float steer=0,wheelDeg=0,prevHands=0;static int gripMode=0; // bit0 left, bit1 right
static int stickDir[4]; // hysteresis state for up/down/left/right

static float wrapf(float a){while(a>3.14159265f)a-=6.2831853f;while(a<-3.14159265f)a+=6.2831853f;return a;}

// ---------------------------------------------------------------- loader
static void* openRuntimeFromJson(void){
    static const char* files[]={"/product/etc/openxr/1/active_runtime.arm64-v8a.json","/product/etc/openxr/1/active_runtime.json",
        "/odm/etc/openxr/1/active_runtime.arm64-v8a.json","/odm/etc/openxr/1/active_runtime.json",
        "/oem/etc/openxr/1/active_runtime.arm64-v8a.json","/oem/etc/openxr/1/active_runtime.json",
        "/vendor/etc/openxr/1/active_runtime.arm64-v8a.json","/vendor/etc/openxr/1/active_runtime.json",
        "/system/etc/openxr/1/active_runtime.arm64-v8a.json","/system/etc/openxr/1/active_runtime.json",0};
    static char buf[2048];
    for(int i=0;files[i];i++){
        int fd=open(files[i],0);if(fd<0)continue;
        long n=read(fd,buf,sizeof(buf)-1);close(fd);if(n<=0)continue;buf[n]=0;
        char* p=strstr(buf,"\"library_path\"");if(!p)continue;
        p=strchr(p+14,'"');if(!p)continue;p++;char* e=strchr(p,'"');if(!e)continue;*e=0;
        void* h=dlopen(p,2);
        LOGI("runtime json %s -> %s : %s",files[i],p,h?"loaded":dlerror());
        if(h)return h;
    }
    return 0;
}
static int loadLoader(void){
    if(gipa)return 1;
    void* h=dlopen("libopenxr_loader.so",2);
    if(h){gipa=(PFN_xrGetInstanceProcAddr)dlsym(h,"xrGetInstanceProcAddr");LOGI("using bundled libopenxr_loader.so");}
    if(!gipa){
        // No bundled loader: negotiate with the system runtime directly, as a loader would.
        static const char* names[]={"libopenxr_forwardloader.oculus.so",0};
        for(int i=0;!h && names[i];i++){h=dlopen(names[i],2);if(h){void* g=dlsym(h,"xrGetInstanceProcAddr");if(g){gipa=(PFN_xrGetInstanceProcAddr)g;LOGI("using %s",names[i]);}}}
        if(!gipa){
            void* rt=openRuntimeFromJson();
            if(rt){
                PFN_xrNegotiateLoaderRuntimeInterface neg=(PFN_xrNegotiateLoaderRuntimeInterface)dlsym(rt,"xrNegotiateLoaderRuntimeInterface");
                if(neg){
                    XrNegotiateLoaderInfo li={XR_LOADER_INTERFACE_STRUCT_LOADER_INFO,XR_LOADER_INFO_STRUCT_VERSION,sizeof(XrNegotiateLoaderInfo),1,XR_CURRENT_LOADER_RUNTIME_VERSION,XR_MAKE_VERSION(1,0,0),XR_MAKE_VERSION(1,0x3ff,0xfff)};
                    XrNegotiateRuntimeRequest rr={XR_LOADER_INTERFACE_STRUCT_RUNTIME_REQUEST,XR_RUNTIME_INFO_STRUCT_VERSION,sizeof(XrNegotiateRuntimeRequest),0,0,0};
                    if(neg(&li,&rr)==XR_SUCCESS)gipa=rr.getInstanceProcAddr;
                    LOGI("runtime negotiation %s",gipa?"ok":"failed");
                }
            }
        }
    }
    if(!gipa){LOGE("no OpenXR loader or runtime found");return 0;}
    return 1;
}
#define LOAD(name) gipa(inst,#name,(PFN_xrVoidFunction*)&p_##name)

// ---------------------------------------------------------------- JNI
typedef jint (*GetVMs)(JavaVM**,jsize,jsize*);
static JavaVM* jvm;static jobject jctx;
static int findJava(void){
    if(jvm && jctx)return 1;
    // Normally both arrive from Java (JNI_OnLoad + VHRQuest.vhrq_init passing the activity).
    const char* libs[]={"libnativehelper.so","libart.so",0};
    for(int i=0;!jvm && libs[i];i++){
        void* h=dlopen(libs[i],2);GetVMs f=h?(GetVMs)dlsym(h,"JNI_GetCreatedJavaVMs"):0;
        if(!f)f=(GetVMs)dlsym(RTLD_DEFAULT,"JNI_GetCreatedJavaVMs");
        jsize n=0;if(f)f(&jvm,1,&n);if(n<1)jvm=0;
    }
    if(!jvm){LOGE("no JavaVM");return 0;}
    JNIEnv* env=0;
    if((*jvm)->GetEnv(jvm,(void**)&env,JNI_VERSION_1_6)!=JNI_OK) (*jvm)->AttachCurrentThread(jvm,(void**)&env,0);
    if(!env)return 0;
    jobject ctx=0;
    jclass c=(*env)->FindClass(env,"com/yoyogames/runner/RunnerJNILib");
    if(c){jfieldID f=(*env)->GetStaticFieldID(env,c,"ms_context","Landroid/content/Context;");if(f)ctx=(*env)->GetStaticObjectField(env,c,f);}
    if((*env)->ExceptionCheck(env))(*env)->ExceptionClear(env);
    if(!ctx){
        jclass at=(*env)->FindClass(env,"android/app/ActivityThread");
        if(at){jmethodID m=(*env)->GetStaticMethodID(env,at,"currentApplication","()Landroid/app/Application;");if(m)ctx=(*env)->CallStaticObjectMethod(env,at,m);}
        if((*env)->ExceptionCheck(env))(*env)->ExceptionClear(env);
        LOGW("RunnerJNILib.ms_context missing; using Application context");
    }
    if(!ctx){LOGE("no Android context");return 0;}
    jctx=(*env)->NewGlobalRef(env,ctx);
    return 1;
}

// ---------------------------------------------------------------- setup
static int hasExt(XrExtensionProperties* e,uint32_t n,const char* name){for(uint32_t i=0;i<n;i++)if(!strcmp(e[i].extensionName,name))return 1;return 0;}
static XrPath P(const char* s){XrPath p=XR_NULL_PATH;p_xrStringToPath(inst,s,&p);return p;}
static XrAction mkAction(const char* name,XrActionType t,int bothHands){
    XrActionCreateInfo ai={XR_TYPE_ACTION_CREATE_INFO};ai.actionType=t;
    strncpy(ai.actionName,name,XR_MAX_ACTION_NAME_SIZE-1);strncpy(ai.localizedActionName,name,XR_MAX_LOCALIZED_ACTION_NAME_SIZE-1);
    if(bothHands){ai.countSubactionPaths=2;ai.subactionPaths=hand;}
    XrAction a=XR_NULL_HANDLE;p_xrCreateAction(aset,&ai,&a);return a;
}
static int makeChain(Chain* c,int w,int h){
    XrSwapchainCreateInfo ci={XR_TYPE_SWAPCHAIN_CREATE_INFO};
    ci.usageFlags=XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT|XR_SWAPCHAIN_USAGE_TRANSFER_DST_BIT;
    ci.format=scFormat;ci.sampleCount=1;ci.width=w;ci.height=h;ci.faceCount=1;ci.arraySize=1;ci.mipCount=1;
    XrResult r=p_xrCreateSwapchain(sess,&ci,&c->sc);
    if(r!=XR_SUCCESS){LOGE("xrCreateSwapchain %dx%d format 0x%llx -> %d",w,h,(long long)scFormat,r);return 0;}
    uint32_t n=0;p_xrEnumerateSwapchainImages(c->sc,0,&n,0);if(n>4)n=4;
    XrSwapchainImageOpenGLESKHR img[4];for(int i=0;i<4;i++){img[i].type=XR_TYPE_SWAPCHAIN_IMAGE_OPENGL_ES_KHR;img[i].next=0;}
    p_xrEnumerateSwapchainImages(c->sc,n,&n,(XrSwapchainImageBaseHeader*)img);
    c->n=n;for(uint32_t i=0;i<n;i++)c->tex[i]=img[i].image;c->w=w;c->h=h;return n>0;
}
static void teardown(void){
    renderEye=0;fovTex=0;goodWindows=0;
    running=0;repeatN=1;displayHz=0;lastValid=0;repeatPending=0;overlapStep=0;lastLayer=0;frameBegun=0;poseValid=0;
    if(sess){p_xrDestroySession(sess);sess=XR_NULL_HANDLE;}
    if(inst){p_xrDestroyInstance(inst);inst=XR_NULL_HANDLE;}
    memset(eyeChain,0,sizeof eyeChain);memset(&quadChain,0,sizeof quadChain);
    sstate=XR_SESSION_STATE_UNKNOWN;
}
static void installHooks(void);
static int setup(void){
    if(sess)return 0;
    load_config();
    if(!loadLoader())return lastError=-1;
    if(!findJava())return lastError=-2;
    if(gipa(XR_NULL_HANDLE,"xrInitializeLoaderKHR",(PFN_xrVoidFunction*)&p_xrInitializeLoaderKHR)==XR_SUCCESS && p_xrInitializeLoaderKHR){
        XrLoaderInitInfoAndroidKHR li={XR_TYPE_LOADER_INIT_INFO_ANDROID_KHR};li.applicationVM=jvm;li.applicationContext=jctx;
        XrResult r=p_xrInitializeLoaderKHR((XrLoaderInitInfoBaseHeaderKHR*)&li);LOGI("xrInitializeLoaderKHR %d",r);
    }
    gipa(XR_NULL_HANDLE,"xrEnumerateInstanceExtensionProperties",(PFN_xrVoidFunction*)&p_xrEnumerateInstanceExtensionProperties);
    gipa(XR_NULL_HANDLE,"xrCreateInstance",(PFN_xrVoidFunction*)&p_xrCreateInstance);
    if(!p_xrCreateInstance)return lastError=-3;
    static XrExtensionProperties ext[128];uint32_t ne=0;
    for(int i=0;i<128;i++){ext[i].type=XR_TYPE_EXTENSION_PROPERTIES;ext[i].next=0;}
    if(p_xrEnumerateInstanceExtensionProperties){p_xrEnumerateInstanceExtensionProperties(0,0,&ne,0);if(ne>128)ne=128;p_xrEnumerateInstanceExtensionProperties(0,ne,&ne,ext);}
    if(!hasExt(ext,ne,XR_KHR_OPENGL_ES_ENABLE_EXTENSION_NAME)){LOGE("runtime lacks OpenGL ES");return lastError=-4;}
    const char* want[8];uint32_t nw=0;want[nw++]=XR_KHR_OPENGL_ES_ENABLE_EXTENSION_NAME;
    XrInstanceCreateInfoAndroidKHR ai={XR_TYPE_INSTANCE_CREATE_INFO_ANDROID_KHR};ai.applicationVM=jvm;ai.applicationActivity=jctx;
    XrInstanceCreateInfo ci={XR_TYPE_INSTANCE_CREATE_INFO};
    if(hasExt(ext,ne,XR_KHR_ANDROID_CREATE_INSTANCE_EXTENSION_NAME)){want[nw++]=XR_KHR_ANDROID_CREATE_INSTANCE_EXTENSION_NAME;ci.next=&ai;}
    int hasPerf=hasExt(ext,ne,XR_EXT_PERFORMANCE_SETTINGS_EXTENSION_NAME),hasRefresh=hasExt(ext,ne,XR_FB_DISPLAY_REFRESH_RATE_EXTENSION_NAME);
    if(hasPerf)want[nw++]=XR_EXT_PERFORMANCE_SETTINGS_EXTENSION_NAME;
    if(hasRefresh)want[nw++]=XR_FB_DISPLAY_REFRESH_RATE_EXTENSION_NAME;
    hasLayerSettings=hasExt(ext,ne,XR_FB_COMPOSITION_LAYER_SETTINGS_EXTENSION_NAME);
    if(hasLayerSettings)want[nw++]=XR_FB_COMPOSITION_LAYER_SETTINGS_EXTENSION_NAME;
    ci.enabledExtensionCount=nw;ci.enabledExtensionNames=want;
    strcpy(ci.applicationInfo.applicationName,"Victory Heat Rally VR");ci.applicationInfo.applicationVersion=1;
    strcpy(ci.applicationInfo.engineName,"GameMaker");ci.applicationInfo.apiVersion=XR_MAKE_VERSION(1,0,0);
    XrResult r=p_xrCreateInstance(&ci,&inst);
    if(r!=XR_SUCCESS){LOGE("xrCreateInstance %d",r);inst=XR_NULL_HANDLE;return lastError=-5;}
    LOAD(xrDestroyInstance);LOAD(xrGetSystem);LOAD(xrCreateSession);LOAD(xrDestroySession);LOAD(xrBeginSession);LOAD(xrEndSession);
    LOAD(xrRequestExitSession);LOAD(xrPollEvent);LOAD(xrWaitFrame);LOAD(xrBeginFrame);LOAD(xrEndFrame);LOAD(xrLocateViews);LOAD(xrLocateSpace);
    LOAD(xrCreateReferenceSpace);LOAD(xrCreateSwapchain);LOAD(xrEnumerateSwapchainFormats);LOAD(xrEnumerateSwapchainImages);
    LOAD(xrAcquireSwapchainImage);LOAD(xrWaitSwapchainImage);LOAD(xrReleaseSwapchainImage);LOAD(xrEnumerateViewConfigurationViews);
    LOAD(xrCreateActionSet);LOAD(xrCreateAction);LOAD(xrStringToPath);LOAD(xrSuggestInteractionProfileBindings);LOAD(xrCreateActionSpace);
    LOAD(xrAttachSessionActionSets);LOAD(xrSyncActions);LOAD(xrGetActionStateFloat);LOAD(xrGetActionStateBoolean);LOAD(xrGetActionStateVector2f);
    LOAD(xrApplyHapticFeedback);LOAD(xrGetOpenGLESGraphicsRequirementsKHR);LOAD(xrDestroySwapchain);
    if(hasPerf){LOAD(xrPerfSettingsSetPerformanceLevelEXT);}
    if(hasRefresh){LOAD(xrEnumerateDisplayRefreshRatesFB);LOAD(xrRequestDisplayRefreshRateFB);LOAD(xrGetDisplayRefreshRateFB);}
    XrSystemGetInfo sg={XR_TYPE_SYSTEM_GET_INFO};sg.formFactor=XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY;
    if(p_xrGetSystem(inst,&sg,&sysId)!=XR_SUCCESS){LOGE("no HMD system");teardown();return lastError=-6;}

    // Actions: steering from grips, pedals from triggers, face buttons for drift/look/back.
    hand[0]=P("/user/hand/left");hand[1]=P("/user/hand/right");
    XrActionSetCreateInfo as={XR_TYPE_ACTION_SET_CREATE_INFO};strcpy(as.actionSetName,"driving");strcpy(as.localizedActionSetName,"Driving");
    p_xrCreateActionSet(inst,&as,&aset);
    aGrip=mkAction("grip",XR_ACTION_TYPE_FLOAT_INPUT,1);aTrigger=mkAction("trigger",XR_ACTION_TYPE_FLOAT_INPUT,1);
    aStick=mkAction("stick",XR_ACTION_TYPE_VECTOR2F_INPUT,1);aPose=mkAction("hand_pose",XR_ACTION_TYPE_POSE_INPUT,1);
    aHaptic=mkAction("rumble",XR_ACTION_TYPE_VIBRATION_OUTPUT,1);
    aA=mkAction("button_a",XR_ACTION_TYPE_BOOLEAN_INPUT,0);aB=mkAction("button_b",XR_ACTION_TYPE_BOOLEAN_INPUT,0);
    aX=mkAction("button_x",XR_ACTION_TYPE_BOOLEAN_INPUT,0);aY=mkAction("button_y",XR_ACTION_TYPE_BOOLEAN_INPUT,0);
    aMenu=mkAction("menu",XR_ACTION_TYPE_BOOLEAN_INPUT,0);
    aStickClickL=mkAction("stick_click_left",XR_ACTION_TYPE_BOOLEAN_INPUT,0);aStickClickR=mkAction("stick_click_right",XR_ACTION_TYPE_BOOLEAN_INPUT,0);
    XrActionSuggestedBinding b[]={
        {aGrip,P("/user/hand/left/input/squeeze/value")},{aGrip,P("/user/hand/right/input/squeeze/value")},
        {aTrigger,P("/user/hand/left/input/trigger/value")},{aTrigger,P("/user/hand/right/input/trigger/value")},
        {aStick,P("/user/hand/left/input/thumbstick")},{aStick,P("/user/hand/right/input/thumbstick")},
        {aPose,P("/user/hand/left/input/grip/pose")},{aPose,P("/user/hand/right/input/grip/pose")},
        {aHaptic,P("/user/hand/left/output/haptic")},{aHaptic,P("/user/hand/right/output/haptic")},
        {aA,P("/user/hand/right/input/a/click")},{aB,P("/user/hand/right/input/b/click")},
        {aX,P("/user/hand/left/input/x/click")},{aY,P("/user/hand/left/input/y/click")},
        {aMenu,P("/user/hand/left/input/menu/click")},
        {aStickClickL,P("/user/hand/left/input/thumbstick/click")},{aStickClickR,P("/user/hand/right/input/thumbstick/click")}};
    XrInteractionProfileSuggestedBinding sb={XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING};
    sb.interactionProfile=P("/interaction_profiles/oculus/touch_controller");sb.countSuggestedBindings=sizeof(b)/sizeof(b[0]);sb.suggestedBindings=b;
    r=p_xrSuggestInteractionProfileBindings(inst,&sb);if(r!=XR_SUCCESS)LOGW("touch bindings %d",r);

    // Session on GameMaker's own GL context (we are on its GL thread).
    XrGraphicsRequirementsOpenGLESKHR req={XR_TYPE_GRAPHICS_REQUIREMENTS_OPENGL_ES_KHR};p_xrGetOpenGLESGraphicsRequirementsKHR(inst,sysId,&req);
    EGLDisplay dpy=eglGetCurrentDisplay();EGLContext ctx=eglGetCurrentContext();
    if(ctx==EGL_NO_CONTEXT){LOGE("no current EGL context: not called from the GL thread");teardown();return lastError=-7;}
    EGLint cfgId=0,nc=0;eglQueryContext(dpy,ctx,EGL_CONFIG_ID,&cfgId);
    EGLint attr[]={EGL_CONFIG_ID,cfgId,EGL_NONE};EGLConfig config=0;eglChooseConfig(dpy,attr,&config,1,&nc);
    XrGraphicsBindingOpenGLESAndroidKHR gb={XR_TYPE_GRAPHICS_BINDING_OPENGL_ES_ANDROID_KHR};gb.display=dpy;gb.config=config;gb.context=ctx;
    XrSessionCreateInfo sc={XR_TYPE_SESSION_CREATE_INFO};sc.next=&gb;sc.systemId=sysId;
    r=p_xrCreateSession(inst,&sc,&sess);
    if(r!=XR_SUCCESS){LOGE("xrCreateSession %d",r);sess=XR_NULL_HANDLE;teardown();return lastError=-8;}
    if(cfg.swap_interval>=0){eglSwapInterval(dpy,cfg.swap_interval);LOGI("eglSwapInterval %d",cfg.swap_interval);}
    installHooks();
    if(p_xrPerfSettingsSetPerformanceLevelEXT && cfg.perf){
        XrResult a=p_xrPerfSettingsSetPerformanceLevelEXT(sess,XR_PERF_SETTINGS_DOMAIN_CPU_EXT,XR_PERF_SETTINGS_LEVEL_SUSTAINED_HIGH_EXT);
        XrResult g=p_xrPerfSettingsSetPerformanceLevelEXT(sess,XR_PERF_SETTINGS_DOMAIN_GPU_EXT,XR_PERF_SETTINGS_LEVEL_SUSTAINED_HIGH_EXT);
        LOGI("perf levels cpu %d gpu %d",a,g);
    }
    if(p_xrEnumerateDisplayRefreshRatesFB){
        float rr[16];uint32_t nr=0;p_xrEnumerateDisplayRefreshRatesFB(sess,16,&nr,rr);
        char list[128];int o=0;for(uint32_t i=0;i<nr&&i<16&&o<110;i++)o+=snprintf(list+o,sizeof(list)-o,"%.0f ",rr[i]);
        float cur=0;if(p_xrGetDisplayRefreshRateFB)p_xrGetDisplayRefreshRateFB(sess,&cur);
        LOGI("refresh rates: %s(current %.0f)",list,cur);
        if(cfg.refresh>0){
            // Only ask for a rate the headset offers (Quest 2/3/3S: 120; Quest Pro tops out at 90).
            float best=0;for(uint32_t i=0;i<nr&&i<16;i++)if(rr[i]<=cfg.refresh+0.5f&&rr[i]>best)best=rr[i];
            if(best>0){XrResult rq=p_xrRequestDisplayRefreshRateFB(sess,best);LOGI("request refresh %.0f: %d",best,rq);}
        }
    }
    XrReferenceSpaceCreateInfo rs={XR_TYPE_REFERENCE_SPACE_CREATE_INFO};rs.poseInReferenceSpace.orientation.w=1;
    rs.referenceSpaceType=XR_REFERENCE_SPACE_TYPE_LOCAL;p_xrCreateReferenceSpace(sess,&rs,&localSpace);
    rs.referenceSpaceType=XR_REFERENCE_SPACE_TYPE_VIEW;p_xrCreateReferenceSpace(sess,&rs,&viewSpace);
    for(int h=0;h<2;h++){XrActionSpaceCreateInfo ac={XR_TYPE_ACTION_SPACE_CREATE_INFO};ac.action=aPose;ac.subactionPath=hand[h];ac.poseInActionSpace.orientation.w=1;p_xrCreateActionSpace(sess,&ac,&gripSpace[h]);}
    XrSessionActionSetsAttachInfo at={XR_TYPE_SESSION_ACTION_SETS_ATTACH_INFO};at.countActionSets=1;at.actionSets=&aset;p_xrAttachSessionActionSets(sess,&at);

    // Swapchain format: raw copies of GameMaker's gamma-space pixels.
    const char* glext=(const char*)glGetString(GL_EXTENSIONS);
    srgbControl=glext && strstr(glext,"GL_EXT_sRGB_write_control");
    int64_t fm[64];memset(fm,0,sizeof fm);uint32_t nf=0;
    XrResult rf1=p_xrEnumerateSwapchainFormats(sess,0,&nf,0);uint32_t fcap=nf>64?64:nf;
    XrResult rf2=p_xrEnumerateSwapchainFormats(sess,fcap,&nf,fm);if(nf>fcap)nf=fcap;
    {char list[512];int o=0;for(uint32_t i=0;i<nf&&o<480;i++)o+=snprintf(list+o,sizeof(list)-o,"%llx ",(long long)fm[i]);LOGI("swapchain formats (r=%d,%d n=%u): %s",rf1,rf2,nf,list);}
    scFormat=0;
    for(uint32_t i=0;i<nf;i++){if(srgbControl && fm[i]==GL_SRGB8_ALPHA8){scFormat=fm[i];break;}}
    if(!scFormat)for(uint32_t i=0;i<nf;i++)if(fm[i]==GL_RGBA8){scFormat=fm[i];break;}
    XrViewConfigurationView vc[2]={{XR_TYPE_VIEW_CONFIGURATION_VIEW},{XR_TYPE_VIEW_CONFIGURATION_VIEW}};uint32_t nv=0;
    p_xrEnumerateViewConfigurationViews(inst,sysId,XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO,2,&nv,vc);
    if(cfg.eye_size<=0){
        // Auto: the headset's own recommended per-eye width (Quest 3: 1680, Quest 2: 1440), square, multiple of 32.
        int e=(int)(vc[0].recommendedImageRectWidth*1.2f);if(e<=0)e=1280; // dynamic resolution may climb past the recommended size
        e=(e+16)/32*32;if(e<1024)e=1024;if(e>2048)e=2048;cfg.eye_size=e;
        renderEye=(int)vc[0].recommendedImageRectWidth/32*32;if(renderEye<1024||renderEye>e)renderEye=e; // start at the headset's recommended size
    }
    LOGI("recommended eye %ux%u, using %d, format 0x%llx srgbControl=%d layerSettings=%d",vc[0].recommendedImageRectWidth,vc[0].recommendedImageRectHeight,cfg.eye_size,(long long)scFormat,srgbControl,hasLayerSettings);
    // If the format list was unusable, just try the formats Quest is known to accept.
    int64_t tryFmt[4]={scFormat,GL_SRGB8_ALPHA8,GL_RGBA8,0};int made=0;
    for(int t=0;t<3 && !made;t++){
        if(!tryFmt[t] || (t>0 && tryFmt[t]==scFormat && scFormat))continue;
        scFormat=tryFmt[t];
        if(makeChain(&eyeChain[0],cfg.eye_size,cfg.eye_size)&&makeChain(&eyeChain[1],cfg.eye_size,cfg.eye_size)&&makeChain(&quadChain,1280,720))made=1;
    }
    if(!made){LOGE("swapchain creation failed");teardown();return lastError=-9;}
    LOGI("swapchains ready, format 0x%llx",(long long)scFormat);
    glGenFramebuffers(1,&blitFbo);
    for(int i=0;i<2;i++){views[i].type=XR_TYPE_VIEW;views[i].next=0;headViews[i].type=XR_TYPE_VIEW;headViews[i].next=0;}
    recenter=1;quadRecenter=1;lastError=0;
    LOGI("OpenXR session created");
    return 0;
}

// ---------------------------------------------------------------- events
static void pollEvents(void){
    XrEventDataBuffer ev;
    for(;;){
        ev.type=XR_TYPE_EVENT_DATA_BUFFER;ev.next=0;
        if(p_xrPollEvent(inst,&ev)!=XR_SUCCESS)break;
        if(ev.type==XR_TYPE_EVENT_DATA_SESSION_STATE_CHANGED){
            XrEventDataSessionStateChanged* s=(XrEventDataSessionStateChanged*)&ev;sstate=s->state;
            LOGI("session state %d",sstate);
            if(sstate==XR_SESSION_STATE_READY){
                XrSessionBeginInfo bi={XR_TYPE_SESSION_BEGIN_INFO};bi.primaryViewConfigurationType=XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
                if(p_xrBeginSession(sess,&bi)==XR_SUCCESS){running=1;recenter=1;quadRecenter=1;waited=0;}
            } else if(sstate==XR_SESSION_STATE_STOPPING){p_xrEndSession(sess);running=0;frameBegun=0;waited=0;}
            else if(sstate==XR_SESSION_STATE_EXITING||sstate==XR_SESSION_STATE_LOSS_PENDING){exitRequested=1;}
        } else if(ev.type==XR_TYPE_EVENT_DATA_REFERENCE_SPACE_CHANGE_PENDING){recenter=1;quadRecenter=1;}
        else if(ev.type==XR_TYPE_EVENT_DATA_INSTANCE_LOSS_PENDING){exitRequested=1;}
    }
    if(exitRequested && sess){teardown();exitRequested=0;}
}

// ---------------------------------------------------------------- pose math
static void poseToMat(const XrPosef* p,float m[3][4]){
    float x=p->orientation.x,y=p->orientation.y,z=p->orientation.z,w=p->orientation.w;
    m[0][0]=1-2*(y*y+z*z);m[0][1]=2*(x*y-z*w);m[0][2]=2*(x*z+y*w);m[0][3]=p->position.x;
    m[1][0]=2*(x*y+z*w);m[1][1]=1-2*(x*x+z*z);m[1][2]=2*(y*z-x*w);m[1][3]=p->position.y;
    m[2][0]=2*(x*z-y*w);m[2][1]=2*(y*z+x*w);m[2][2]=1-2*(x*x+y*y);m[2][3]=p->position.z;
}
// LOCAL-space point -> recentered frame (same transform VHRVR.dll applies to eye poses)
static void toRecentered(const XrVector3f* v,float o[3]){
    float c=cosf(yawCenter),s=sinf(yawCenter),px=v->x-center[0],py=v->y-center[1],pz=v->z-center[2];
    o[0]=c*px-s*pz;o[1]=py;o[2]=s*px+c*pz;
}

// ---------------------------------------------------------------- input update
static float getF(XrAction a,int h){XrActionStateGetInfo g={XR_TYPE_ACTION_STATE_GET_INFO};g.action=a;g.subactionPath=h>=0?hand[h]:XR_NULL_PATH;XrActionStateFloat s={XR_TYPE_ACTION_STATE_FLOAT};p_xrGetActionStateFloat(sess,&g,&s);return s.isActive?s.currentState:0;}
static int getB(XrAction a){XrActionStateGetInfo g={XR_TYPE_ACTION_STATE_GET_INFO};g.action=a;XrActionStateBoolean s={XR_TYPE_ACTION_STATE_BOOLEAN};p_xrGetActionStateBoolean(sess,&g,&s);return s.isActive&&s.currentState;}
static XrVector2f getV(XrAction a,int h){XrActionStateGetInfo g={XR_TYPE_ACTION_STATE_GET_INFO};g.action=a;g.subactionPath=hand[h];XrActionStateVector2f s={XR_TYPE_ACTION_STATE_VECTOR2F};p_xrGetActionStateVector2f(sess,&g,&s);XrVector2f z={0,0};return s.isActive?s.currentState:z;}
static int prevStickClickL=0,prevStickClickR=0;

static void updateInput(void){
    memcpy(verbPrev,verbNow,sizeof verbNow);memset(verbNow,0,sizeof verbNow);viewTogglePressed=0;
    XrActiveActionSet act={aset,XR_NULL_PATH};XrActionsSyncInfo si={XR_TYPE_ACTIONS_SYNC_INFO};si.countActiveActionSets=1;si.activeActionSets=&act;
    if(p_xrSyncActions(sess,&si)!=XR_SUCCESS)return;
    float grip[2]={getF(aGrip,0),getF(aGrip,1)},trig[2]={getF(aTrigger,0),getF(aTrigger,1)};
    XrVector2f st[2]={getV(aStick,0),getV(aStick,1)};
    int a=getB(aA),b=getB(aB),x=getB(aX),y=getB(aY),menu=getB(aMenu),scl=getB(aStickClickL),scr=getB(aStickClickR);
    if(scl && !prevStickClickL){recenter=1;quadRecenter=1;LOGI("recenter");}
    if(scr && !prevStickClickR)viewTogglePressed=1;
    prevStickClickL=scl;prevStickClickR=scr;

    // Pedals and buttons. Hands stay on the wheel: triggers are under the index fingers.
    verbNow[V_GAS]=trig[1]>cfg.trigger_on;
    verbNow[V_BRAKE]=trig[0]>cfg.trigger_on;
    verbNow[V_DRIFT]=a||x;
    verbNow[V_LOOKBACK]=b;
    verbNow[V_ACCEPT]=a||trig[1]>cfg.trigger_on; // trigger also confirms, for pointing-style habits
    verbNow[V_BACK]=b||y;
    verbNow[V_PAUSE]=menu;
    // Menus: hold a grip and push a stick up/down to move the floating screen nearer or farther.
    if(!sceneMode){
        float gy=fabsf(st[0].y)>fabsf(st[1].y)?st[0].y:st[1].y;
        if(grip[0]>0.55f||grip[1]>0.55f){
            if(fabsf(gy)>0.2f){cfg.theatre_dist-=gy*2.5f/60.f;if(cfg.theatre_dist<1.2f)cfg.theatre_dist=1.2f;if(cfg.theatre_dist>12.f)cfg.theatre_dist=12.f;theatreAdjusting=1;}
            st[0].x=st[0].y=st[1].x=st[1].y=0; // not menu navigation while adjusting
        } else if(theatreAdjusting){theatreAdjusting=0;save_theatre();}
    }
    // Menu directions from either thumbstick, with hysteresis.
    float sx=fabsf(st[0].x)>fabsf(st[1].x)?st[0].x:st[1].x,sy=fabsf(st[0].y)>fabsf(st[1].y)?st[0].y:st[1].y;
    float dirVal[4]={sy,-sy,-sx,sx};
    for(int d=0;d<4;d++){if(dirVal[d]>0.6f)stickDir[d]=1;else if(dirVal[d]<0.4f)stickDir[d]=0;verbNow[V_UP+d]=stickDir[d];}
    {static const char* vn[V_COUNT]={"accept","back","up","down","left","right","pause","gas","brake","drift","lookback"};
     for(int v=0;v<V_COUNT;v++) if(verbNow[v]&&!verbPrev[v]) LOGI("pressed %s",vn[v]);}

    // Pretend wheel: hands on the grips turn it; released, it springs back to center.
    XrSpaceLocation hl[2];float hp[2][3];int held[2];
    for(int h=0;h<2;h++){
        hl[h].type=XR_TYPE_SPACE_LOCATION;hl[h].next=0;p_xrLocateSpace(gripSpace[h],localSpace,predicted,&hl[h]);
        int ok=(hl[h].locationFlags&XR_SPACE_LOCATION_POSITION_VALID_BIT)!=0;
        held[h]=ok && grip[h]>0.55f;
        if(ok)toRecentered(&hl[h].pose.position,hp[h]);
    }
    int mode=cfg.steer_mode==1?0:(held[0]|(held[1]<<1)); // thumbstick mode: grips never steer
    float handsAngle=0;
    if(mode==3) handsAngle=atan2f(hp[1][1]-hp[0][1],hp[1][0]-hp[0][0]);
    else if(mode){int h=mode==1?0:1;handsAngle=atan2f(hp[h][1]-cfg.wheel_y,hp[h][0]-cfg.wheel_x);}
    if(mode){
        if(mode!=gripMode)prevHands=handsAngle; // re-grab without the wheel jumping
        wheelDeg-=wrapf(handsAngle-prevHands)*57.29578f;
        prevHands=handsAngle;
        float lim=cfg.wheel_lock*1.5f;if(wheelDeg>lim)wheelDeg=lim;if(wheelDeg<-lim)wheelDeg=-lim;
        steer=wheelDeg/cfg.wheel_lock;
    } else {
        float k=cfg.wheel_return>0.001f?expf(-(1.f/72.f)/cfg.wheel_return):0;
        wheelDeg*=k;if(fabsf(wheelDeg)<0.5f)wheelDeg=0;
        steer=wheelDeg/cfg.wheel_lock;
        if(cfg.steer_mode==1){
            // Thumbstick steering: left stick (right stick if the left one is idle), no dead band here:
            // the game applies its own Stick Deadzone setting.
            steer=fabsf(st[0].x)>=fabsf(st[1].x)?st[0].x:st[1].x;
            wheelDeg=steer*cfg.wheel_lock;
        }
    }
    gripMode=mode;
    if(steer>1)steer=1;if(steer<-1)steer=-1;
}

// ---------------------------------------------------------------- frame
static void locate(void){
    XrViewLocateInfo li={XR_TYPE_VIEW_LOCATE_INFO};li.viewConfigurationType=XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;li.displayTime=locateTime?locateTime:predicted;
    XrViewState vs={XR_TYPE_VIEW_STATE};uint32_t n=0;
    li.space=localSpace;
    if(p_xrLocateViews(sess,&li,&vs,2,&n,views)!=XR_SUCCESS||n<2||!(vs.viewStateFlags&XR_VIEW_STATE_ORIENTATION_VALID_BIT)){poseValid=0;return;}
    li.space=viewSpace;XrViewState vs2={XR_TYPE_VIEW_STATE};p_xrLocateViews(sess,&li,&vs2,2,&n,headViews);
    XrSpaceLocation head={XR_TYPE_SPACE_LOCATION};p_xrLocateSpace(viewSpace,localSpace,locateTime?locateTime:predicted,&head);
    float h[3][4];poseToMat(&head.pose,h);
    if(recenter){for(int i=0;i<3;i++)center[i]=h[i][3];yawCenter=atan2f(h[0][2],h[2][2]);recenter=0;}
    if(quadRecenter){quadYaw=atan2f(h[0][2],h[2][2]);for(int i=0;i<3;i++)quadOrigin[i]=h[i][3];quadRecenter=0;}
    quadPose.orientation.x=0;quadPose.orientation.y=sinf(quadYaw/2);quadPose.orientation.z=0;quadPose.orientation.w=cosf(quadYaw/2);
    quadPose.position.x=quadOrigin[0]-sinf(quadYaw)*cfg.theatre_dist;quadPose.position.y=quadOrigin[1];quadPose.position.z=quadOrigin[2]-cosf(quadYaw)*cfg.theatre_dist;
    float c=cosf(yawCenter),s=sinf(yawCenter);
    for(int e=0;e<2;e++){
        float p[3][4];poseToMat(&views[e].pose,p);
        for(int r=0;r<3;r++)p[r][3]-=center[r];
        for(int col=0;col<4;col++){
            eyePose[e][col]=c*p[0][col]-s*p[2][col];
            eyePose[e][4+col]=p[1][col];
            eyePose[e][8+col]=s*p[0][col]+c*p[2][col];
        }
    }
    // Quest 3 lenses have off-centre fields of view (each eye sees further outward and downward).
    // Rendering that needs off-centre projection terms whose signs depend on GameMaker's surface
    // orientation; any mismatch makes the cockpit stretch and swim as you look around. A centred
    // frustum that covers the whole lens view has no such terms, and the compositor gets the exact
    // same frustum, so the image always lines up.
    {static int told=0;if(!told){told=1;const XrFovf* f=&views[0].fov;LOGI("left eye lens fov (rad) L%.3f R%.3f U%.3f D%.3f, lens fit %d",f->angleLeft,f->angleRight,f->angleUp,f->angleDown,cfg.fov_symmetric);}}
    for(int e=0;e<2;e++){
        XrFovf* f=&views[e].fov;
        float h=fabsf(f->angleLeft)>fabsf(f->angleRight)?fabsf(f->angleLeft):fabsf(f->angleRight);
        float v=fabsf(f->angleUp)>fabsf(f->angleDown)?fabsf(f->angleUp):fabsf(f->angleDown);
        int mode=cfg.fov_symmetric;
        if(mode<=0){f->angleLeft=-h;f->angleRight=h;}          // Safe: centred both ways
        if(mode<=1){f->angleUp=v;f->angleDown=-v;}             // Safe/Medium: centred up/down
        renderFov[e]=*f;                                       // what the compositor gets
        // Sharp: GameMaker flips the image vertically when it renders to a surface on GLES, which
        // inverts the off-centre up/down term of the projection. Telling it the mirrored up/down
        // angles cancels that, so the rendered frustum equals the lens frustum submitted.
        if(mode>=2){renderFov[e].angleUp=-f->angleDown;renderFov[e].angleDown=-f->angleUp;}
    }
    poseValid=1;
}
static void endEmpty(void){
    XrFrameEndInfo fe={XR_TYPE_FRAME_END_INFO};fe.displayTime=predicted;fe.environmentBlendMode=XR_ENVIRONMENT_BLEND_MODE_OPAQUE;
    p_xrEndFrame(sess,&fe);frameBegun=0;
}
static int waitFrame(void){
    XrFrameState fs={XR_TYPE_FRAME_STATE};double t0=nowMs();
    XrResult r=p_xrWaitFrame(sess,0,&fs);accWait+=nowMs()-t0;
    if(r!=XR_SUCCESS){LOGW("xrWaitFrame %d",r);return 0;}
    nextPredicted=fs.predictedDisplayTime;nextShouldRender=fs.shouldRender;waited=1;return 1;
}
static void frameStats(void){
    double t=nowMs();
    if(tSubmitEnd>0)accRunner+=t-tSubmitEnd;
    if(prevBegin>0){double st=t-prevBegin;if(st>maxStep)maxStep=st;if(st>25.0)hitches++;}
    prevBegin=t;
    tBegin=t;
    if(statStart==0)statStart=t;
    if(++statFrames>=1 && t-statStart>=3000){
        double n=statFrames;
        double fps=n*1000.0/(t-statStart);
        if(renderEye<=0)renderEye=cfg.eye_size;
        LOGI("timing: %.1f fps | game cpu %.1f ms | GameMaker outside %.1f ms (window swap %.1f, sleep %.1f) | waiting for headset %.1f ms | %.0f Hz x%d%s | eye %d of %d | hitches %d, longest step %.1f ms",fps,(overlapStep?accGame-accWait:accGame)/n,accRunner/n,accSwap/n,accSleep/n,accWait/n,displayHz,repeatN,overlapStep?" overlapped":"",renderEye,cfg.eye_size,hitches,maxStep);
        // Dynamic resolution: drop the per-eye render size when the game cannot hold 60, creep back up
        // after two clean windows. Loading screens (one very long step) do not count.
        // Races only (menus are a flat screen). The game is mostly limited by its own CPU work, which
        // render size barely changes, so only a sustained drop (two windows in a row, no loading
        // pause) lowers it; steady 60 raises it toward the 1.2x supersampled maximum.
        if(cfg.dyn_res && running && sceneMode){
            int lo=cfg.eye_min<512?512:cfg.eye_min;
            if(maxStep>60){goodWindows=badWindows=0;}
            else if(fps<57.5 || hitches>4){
                goodWindows=0;
                if(++badWindows>=2 && renderEye>lo){renderEye-=128;if(renderEye<lo)renderEye=lo;badWindows=0;LOGI("render size down to %d per eye",renderEye);}
            } else if(fps>=59.3 && hitches<=1){
                badWindows=0;
                if(++goodWindows>=2 && renderEye<cfg.eye_size){renderEye+=96;if(renderEye>cfg.eye_size)renderEye=cfg.eye_size;goodWindows=0;LOGI("render size up to %d per eye",renderEye);}
            } else goodWindows=badWindows=0;
        }
        hitches=0;maxStep=0;
        statStart=t;statFrames=0;accWait=accGame=accRunner=accSwap=accSleep=0;
    }
}
static void updateRefresh(void);static void limit60(void);
static void endRepeatOpenReal(void){
    if(!repeatPending)return;
    repeatPending=0;
    XrFrameEndInfo fe={XR_TYPE_FRAME_END_INFO};fe.displayTime=predicted;fe.environmentBlendMode=XR_ENVIRONMENT_BLEND_MODE_OPAQUE;
    fe.layerCount=(lastValid && shouldRender && lastLayer)?1:0;fe.layers=&lastLayer;
    XrResult r=p_xrEndFrame(sess,&fe);frameBegun=0;
    if(r!=XR_SUCCESS){lastError=r;LOGW("xrEndFrame (in-between) %d",r);}
    if(!running)return;
    if(!waitFrame())return;
    waited=0;
    if(p_xrBeginFrame(sess,0)!=XR_SUCCESS)return;
    frameBegun=1;predicted=nextPredicted;shouldRender=nextShouldRender;
}
static int beginFrame(void){
    if(!sess)return 0;
    pollEvents();
    if(!sess||!running)return 0;
    if(frameBegun)endEmpty(); // a frame whose draw never submitted
    frameStats();
    updateRefresh();
    overlapStep=cfg.pace_overlap && repeatN==2 && lastValid && displayHz>0;
    if(overlapStep){
        // Begin Step opens the in-between headset frame (it shows the previous game frame again);
        // game logic runs while it is pending, and End Step submits it and opens the real frame.
        if(!waited && !waitFrame())return 0;
        waited=0;
        if(p_xrBeginFrame(sess,0)!=XR_SUCCESS)return 0;
        frameBegun=1;predicted=nextPredicted;shouldRender=nextShouldRender;repeatPending=1;
        locateTime=predicted+(XrTime)(1e9/displayHz); // the real frame shows one headset frame later
        locate();locateTime=0;
        return 1;
    }
    limit60();
    if(!waited && !waitFrame())return 0;
    waited=0;
    if(p_xrBeginFrame(sess,0)!=XR_SUCCESS)return 0;
    frameBegun=1;predicted=nextPredicted;shouldRender=nextShouldRender;
    locate();
    return 1;
}
static int blitDW=0,blitDH=0; // >0: copy into the lower-left blitDW x blitDH of the image (dynamic resolution)
static void blitInto(Chain* c,GLint srcFbo,int sx0,int sy0,int sx1,int sy1,int flip){
    // Upscale by a whole number with nearest filtering so pixel art stays sharp; otherwise smooth.
    int sw=sx1-sx0,sh=sy1-sy0;GLenum filt=GL_LINEAR;
    int dw=blitDW>0&&blitDW<=c->w?blitDW:c->w,dh=blitDH>0&&blitDH<=c->h?blitDH:c->h;
    if(sw>0&&sh>0&&dw%sw==0&&dh%sh==0&&dw/sw==dh/sh)filt=GL_NEAREST;
    uint32_t idx=0;XrSwapchainImageAcquireInfo ai={XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO};
    if(p_xrAcquireSwapchainImage(c->sc,&ai,&idx)!=XR_SUCCESS)return;
    XrSwapchainImageWaitInfo wi={XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO};wi.timeout=XR_INFINITE_DURATION;p_xrWaitSwapchainImage(c->sc,&wi);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER,blitFbo);
    glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,c->tex[idx],0);
    glBindFramebuffer(GL_READ_FRAMEBUFFER,srcFbo);
    if(flip)glBlitFramebuffer(sx0,sy0,sx1,sy1,0,dh,dw,0,GL_COLOR_BUFFER_BIT,filt);
    else glBlitFramebuffer(sx0,sy0,sx1,sy1,0,0,dw,dh,GL_COLOR_BUFFER_BIT,filt);
    XrSwapchainImageReleaseInfo ri={XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO};p_xrReleaseSwapchainImage(c->sc,&ri);
}

// Menu screen swapchain: the menu image times the largest whole number that stays within 2048 wide
// (a 512x288 image becomes 2048x1152), so the compositor gets every pixel crisp.
static void fitQuadChain(int W,int H){
    if(W<=0||H<=0)return;
    int k=2048/W;if(k<1)k=1;if(H*k>2048)k=2048/H;if(k<1)k=1;
    int w=W*k,h=H*k;if(w>2048)w=2048;if(h>2048)h=2048;
    if(quadChain.sc && quadChain.w==w && quadChain.h==h)return;
    Chain old=quadChain;
    if(!makeChain(&quadChain,w,h)){quadChain=old;return;}
    if(old.sc && p_xrDestroySwapchain)p_xrDestroySwapchain(old.sc);
    LOGI("menu screen swapchain %dx%d (menu image %dx%d)",w,h,W,H);
}
static void updateRefresh(void){
    static int n=0;if(!p_xrGetDisplayRefreshRateFB || (n++%36))return;
    float hz=0;if(p_xrGetDisplayRefreshRateFB(sess,&hz)!=XR_SUCCESS||hz<=0)return;
    int k=(int)(hz/60.f+0.5f);int rep=(k>=2 && fabsf(hz-60.f*k)<2.f)?k:1;
    if(hz!=displayHz||rep!=repeatN)LOGI("display %.0f Hz: each game step shown for %d headset frame(s)",hz,rep);
    displayHz=hz;repeatN=cfg.pace_60?rep:1;
}
// When the display rate is not a multiple of 60 (72, 80, 90 Hz), hold game steps 1/60 s apart ourselves.
static void limit60(void){
    double t=nowMs();
    if(cfg.pace_60 && repeatN==1 && lastBeginMs>0){
        double target=lastBeginMs+1000.0/60.0;
        if(t<target-0.2){struct {long s,ns;} ts={0,(long)((target-t)*1e6)};extern int nanosleep(const void*,void*);nanosleep(&ts,0);t=nowMs();}
        lastBeginMs=(t-target<4.0)?target:t; // stay on the 60 Hz grid unless a frame ran long
    } else lastBeginMs=t;
}

// ---------------------------------------------------------------- GameMaker frame pacing hooks
// GameMaker presents every frame to its Android window (invisible while the headset shows VR)
// and sleeps to hold 60 fps. Both are measured; a window swap that blocks is skipped in VR.
typedef struct {const char* lib;const char* sym;void* repl;void** orig;int count;} HookReq;
static int hookCb(struct dl_phdr_info* info,size_t sz,void* data){
    (void)sz;HookReq* h=(HookReq*)data;
    if(!info->dlpi_name||!strstr(info->dlpi_name,h->lib))return 0;
    ElfW(Addr) base=info->dlpi_addr;const ElfW(Dyn)* dyn=0;
    for(int i=0;i<info->dlpi_phnum;i++)if(info->dlpi_phdr[i].p_type==PT_DYNAMIC)dyn=(const ElfW(Dyn)*)(base+info->dlpi_phdr[i].p_vaddr);
    if(!dyn)return 0;
    const ElfW(Sym)* symtab=0;const char* strtab=0;const ElfW(Rela)* tabs[2]={0,0};size_t sizes[2]={0,0};
    #define ADJ(v) ((v)<base?(v)+base:(v))
    for(const ElfW(Dyn)* d=dyn;d->d_tag!=DT_NULL;d++){
        switch(d->d_tag){
        case DT_SYMTAB:symtab=(const ElfW(Sym)*)ADJ(d->d_un.d_ptr);break;
        case DT_STRTAB:strtab=(const char*)ADJ(d->d_un.d_ptr);break;
        case DT_JMPREL:tabs[0]=(const ElfW(Rela)*)ADJ(d->d_un.d_ptr);break;
        case DT_PLTRELSZ:sizes[0]=d->d_un.d_val;break;
        case DT_RELA:tabs[1]=(const ElfW(Rela)*)ADJ(d->d_un.d_ptr);break;
        case DT_RELASZ:sizes[1]=d->d_un.d_val;break;
        }
    }
    if(!symtab||!strtab)return 0;
    for(int t=0;t<2;t++){
        if(!tabs[t])continue;
        size_t n=sizes[t]/sizeof(ElfW(Rela));
        for(size_t i=0;i<n;i++){
            uint32_t type=ELF64_R_TYPE(tabs[t][i].r_info),si=ELF64_R_SYM(tabs[t][i].r_info);
            if((type!=R_AARCH64_JUMP_SLOT&&type!=R_AARCH64_GLOB_DAT)||!si)continue;
            if(strcmp(strtab+symtab[si].st_name,h->sym))continue;
            void** slot=(void**)(base+tabs[t][i].r_offset);
            uintptr_t page=(uintptr_t)slot&~(uintptr_t)4095;
            if(mprotect((void*)page,4096,3)!=0){LOGW("hook %s in %s: mprotect failed",h->sym,info->dlpi_name);continue;}
            if(*slot!=h->repl){if(!*h->orig)*h->orig=*slot;*slot=h->repl;h->count++;}
            mprotect((void*)page,4096,1);
        }
    }
    return 0;
}
static int hookGot(const char* lib,const char* sym,void* repl,void** orig){
    HookReq h={lib,sym,repl,orig,0};dl_iterate_phdr(hookCb,&h);
    LOGI("hook %s in %s: %d slot(s)",sym,lib,h.count);return h.count;
}
static unsigned (*realSwap)(void*,void*);
static int swapMode=-1,swapSamples=0;static double swapSampleSum=0;
static unsigned mySwap(void* d,void* surf){
    if(!sess||!running||!realSwap)return realSwap?realSwap(d,surf):1;
    if(swapMode==1){glFlush();return 1;}
    double t=nowMs();unsigned r=realSwap(d,surf);double dt=nowMs()-t;accSwap+=dt;
    if(swapMode<0){
        if(cfg.swap_skip==0)swapMode=0;
        else if(cfg.swap_skip==1){swapMode=1;LOGI("window swap skipped in VR (swap_skip=1)");}
        else if(++swapSamples>=1){swapSampleSum+=dt;
            if(swapSamples>=90){double avg=swapSampleSum/swapSamples;swapMode=avg>5.0?1:0;
                LOGI("window swap takes %.1f ms per frame: %s",avg,swapMode?"skipping it while in VR":"keeping it");}}
    }
    return r;
}
struct ts_q{long s,ns;};
static int (*realUsleep)(unsigned);static int (*realNanosleep)(const struct ts_q*,struct ts_q*);
extern unsigned long pthread_self(void);
static int myUsleep(unsigned us){double t=nowMs();int r=realUsleep(us);if(pthread_self()==glThread)accSleep+=nowMs()-t;return r;}
static int myNanosleep(const struct ts_q* a,struct ts_q* b){double t=nowMs();int r=realNanosleep(a,b);if(pthread_self()==glThread)accSleep+=nowMs()-t;return r;}
static void installHooks(void){
    static int done=0;if(done)return;done=1;
    hookGot("libandroid_runtime.so","eglSwapBuffers",(void*)mySwap,(void**)&realSwap);
    hookGot("libyoyo.so","eglSwapBuffers",(void*)mySwap,(void**)&realSwap);
    hookGot("libyoyo.so","usleep",(void*)myUsleep,(void**)&realUsleep);
    hookGot("libyoyo.so","nanosleep",(void*)myNanosleep,(void**)&realNanosleep);
}

// ---------------------------------------------------------------- exported API
// Same names and meanings as VHRVR.dll, with a vhrq_ prefix.
API vhrq_init(void){
    if(sess)return 0;
    int r=setup();if(r)LOGW("init failed %d",r);
    return r;
}
API vhrq_stop(void){if(sess && running && p_xrRequestExitSession)p_xrRequestExitSession(sess);teardown();return 0;}
API vhrq_recenter(void){recenter=1;quadRecenter=1;return 0;}
API vhrq_mode(double scene){sceneMode=scene>0.5;quadRecenter=1;return 0;}
API vhrq_frame(void){if(!sess)return 0;glThread=pthread_self();return beginFrame();}
API vhrq_poll(void){return sess && frameBegun && poseValid;}
API vhrq_active(void){return sess && running;}
API vhrq_value(double eye,double field){
    int i=(int)eye,k=(int)field;if(i<0||i>1)return 0;
    if(k>=0&&k<12)return poseValid?eyePose[i][k]:0;
    if(k==99)return lastError;
    if(k==30)return headViews[i].pose.position.x;
    if(k>=24&&k<=27){ // frustum the eye image covers (what the compositor gets): for screen-space overlays
        const XrFovf* f=&views[i].fov;
        if(k==24)return tanf(f->angleLeft);if(k==25)return tanf(f->angleRight);
        if(k==26)return -tanf(f->angleUp);return -tanf(f->angleDown);
    }
    if(k>=20&&k<=23){
        const XrFovf* f=&renderFov[i];
        if(k==20)return tanf(f->angleLeft);if(k==21)return tanf(f->angleRight);
        if(k==22)return -tanf(f->angleUp);return -tanf(f->angleDown);
    }
    return 0;
}
// Fixed foveated rendering of the game's side-by-side eye image (GL_QCOM_texture_foveated): full
// resolution in the middle of each lens, gradually fewer pixels toward the edges where the lens blurs
// anyway. Applied to the texture GameMaker renders into, from the next frame on.

static void applyFoveation(void){
    if(cfg.foveation<=0 || fovSupported==0)return;
    if(fovSupported<0){
        const char* ex=(const char*)glGetString(GL_EXTENSIONS);
        fovSupported=ex && strstr(ex,"GL_QCOM_texture_foveated")?1:0;
        if(fovSupported)p_fovParams=(PFN_fovQCOM)(void*)eglGetProcAddress("glTextureFoveationParametersQCOM");
        if(!p_fovParams)fovSupported=0;
        LOGI("foveated rendering %s",fovSupported?"available":"not available");
        if(!fovSupported)return;
    }
    GLint type=0,name=0;
    glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE,&type);
    if(type!=GL_TEXTURE)return;
    glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME,&name);
    if(!name || (GLuint)name==fovTex)return;
    while(glGetError()!=0){} // drop errors left by GameMaker so ours are ours
    GLint prev=0;glGetIntegerv(GL_TEXTURE_BINDING_2D,&prev);
    glBindTexture(GL_TEXTURE_2D,(GLuint)name);
    GLint query=0;glGetTexParameteriv(GL_TEXTURE_2D,0x8BFD /*FOVEATED_FEATURE_QUERY*/,&query);
    GLint bitsNow=0;glGetTexParameteriv(GL_TEXTURE_2D,0x8BFB,&bitsNow);
    GLenum e0=glGetError();
    GLint want=0x1|((query&0x2)?0x2:0); // ENABLE, plus SCALED_BIN when the driver offers it
    if(!(bitsNow&0x1))glTexParameteri(GL_TEXTURE_2D,0x8BFB /*FOVEATED_FEATURE_BITS*/,want);
    GLenum e1=glGetError();
    // Pixel density at the edge of each eye: low 0.7, medium 0.5, high 0.35 (1 = full).
    float edge=cfg.foveation==1?0.7f:cfg.foveation==2?0.5f:0.35f;
    float gx=(1.f/edge)/0.25f,gy=(1.f/edge); // each eye is half the image wide: edge is 0.5 from its centre
    p_fovParams((GLuint)name,0,0,-0.5f,0.f,gx,gy,0.f);
    p_fovParams((GLuint)name,0,1, 0.5f,0.f,gx,gy,0.f);
    glBindTexture(GL_TEXTURE_2D,(GLuint)prev);
    GLenum err=glGetError();
    fovTex=(GLuint)name;
    LOGI("foveation level %d on game image texture %d (supported bits 0x%x, had 0x%x; errors query 0x%x, enable 0x%x, params 0x%x)",cfg.foveation,name,query,bitsNow,e0,e1,err);
}
// stereo=1: bound framebuffer holds both eyes side by side (w x h); else a flat frame for the theatre panel.
API vhrq_submit(double stereo,double w,double h){
    if(!sess)return 0;
    if(!frameBegun && !beginFrame())return 0;
    GLint rd=0,dr=0,vp[4];GLboolean sc=glIsEnabled(GL_SCISSOR_TEST),sr=srgbControl?glIsEnabled(GL_FRAMEBUFFER_SRGB_EXT):0;
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&rd);glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&dr);glGetIntegerv(GL_VIEWPORT,vp);
    int W=(int)w,H=(int)h;
    XrCompositionLayerProjectionView pv[2];XrCompositionLayerProjection proj={XR_TYPE_COMPOSITION_LAYER_PROJECTION};
    XrCompositionLayerQuad quad={XR_TYPE_COMPOSITION_LAYER_QUAD};const XrCompositionLayerBaseHeader* layers[1];int nl=0;
    XrCompositionLayerSettingsFB eyeSet={XR_TYPE_COMPOSITION_LAYER_SETTINGS_FB},quadSet={XR_TYPE_COMPOSITION_LAYER_SETTINGS_FB};
    if(hasLayerSettings && cfg.sharpen>0){
        eyeSet.layerFlags=cfg.sharpen>=2?XR_COMPOSITION_LAYER_SETTINGS_QUALITY_SHARPENING_BIT_FB:XR_COMPOSITION_LAYER_SETTINGS_NORMAL_SHARPENING_BIT_FB;
        quadSet.layerFlags=XR_COMPOSITION_LAYER_SETTINGS_QUALITY_SHARPENING_BIT_FB;
        proj.next=&eyeSet;quad.next=&quadSet;
    }
    if(shouldRender && W>0 && H>0){
        if(sc)glDisable(GL_SCISSOR_TEST);
        if(sr)glDisable(GL_FRAMEBUFFER_SRGB_EXT);
        if(stereo>0.5 && sceneMode && poseValid){
            static int told=0;
            if(!told){told=1;LOGI("stereo source framebuffer %d (%dx%d)%s",dr,W,H,dr==0?" WARNING: window framebuffer, expected the application surface":"");}
            if(dr!=0)applyFoveation();
            for(int e=0;e<2;e++){
                // 1:1 copy into the corner of a larger image; the layer shows just that part (no rescale blur).
                int ew=W/2<eyeChain[e].w?W/2:eyeChain[e].w,eh=H<eyeChain[e].h?H:eyeChain[e].h;
                blitDW=ew;blitDH=eh;
                blitInto(&eyeChain[e],dr,e*W/2,0,(e+1)*W/2,H,cfg.flip_stereo);
                blitDW=blitDH=0;
                memset(&pv[e],0,sizeof pv[e]);pv[e].type=XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW;
                pv[e].pose=views[e].pose;pv[e].fov=views[e].fov;
                pv[e].subImage.swapchain=eyeChain[e].sc;pv[e].subImage.imageRect.extent.width=ew;pv[e].subImage.imageRect.extent.height=eh;
            }
            proj.space=localSpace;proj.viewCount=2;proj.views=pv;layers[nl++]=(XrCompositionLayerBaseHeader*)&proj;
        } else {
            fitQuadChain(W,H);
            blitInto(&quadChain,cfg.theatre_bound?dr:0,0,0,W,H,cfg.flip_theatre);
            quad.space=localSpace;quad.eyeVisibility=XR_EYE_VISIBILITY_BOTH;quad.pose=quadPose;
            quad.subImage.swapchain=quadChain.sc;quad.subImage.imageRect.extent.width=quadChain.w;quad.subImage.imageRect.extent.height=quadChain.h;
            quad.size.width=cfg.theatre_width;quad.size.height=cfg.theatre_width*(float)H/(float)W;
            layers[nl++]=(XrCompositionLayerBaseHeader*)&quad;
        }
        if(sr)glEnable(GL_FRAMEBUFFER_SRGB_EXT);
        if(sc)glEnable(GL_SCISSOR_TEST);
        glBindFramebuffer(GL_READ_FRAMEBUFFER,rd);glBindFramebuffer(GL_DRAW_FRAMEBUFFER,dr);glViewport(vp[0],vp[1],vp[2],vp[3]);
    }
    XrFrameEndInfo fe={XR_TYPE_FRAME_END_INFO};fe.displayTime=predicted;fe.environmentBlendMode=XR_ENVIRONMENT_BLEND_MODE_OPAQUE;
    fe.layerCount=nl;fe.layers=layers;
    accGame+=nowMs()-tBegin;
    XrResult r=p_xrEndFrame(sess,&fe);frameBegun=0;
    if(r!=XR_SUCCESS){lastError=r;LOGW("xrEndFrame %d",r);}
    // Keep this frame's layer for the in-between headset frame (overlapped 120 Hz pacing).
    if(nl==1){
        if(layers[0]==(XrCompositionLayerBaseHeader*)&proj){
            lastPv[0]=pv[0];lastPv[1]=pv[1];lastProj=proj;lastProj.views=lastPv;
            if(proj.next){lastEyeSet=eyeSet;lastProj.next=&lastEyeSet;}
            lastLayer=(XrCompositionLayerBaseHeader*)&lastProj;
        } else {
            lastQuad=quad;if(quad.next){lastQuadSet=quadSet;lastQuad.next=&lastQuadSet;}
            lastLayer=(XrCompositionLayerBaseHeader*)&lastQuad;
        }
        lastValid=1;
    }
    if(overlapStep){tSubmitEnd=nowMs();return r==XR_SUCCESS;}
    // 120 Hz: show this game step for one more headset frame (same images; the compositor
    // re-aims them at your head), so the game advances exactly 60 times a second.
    for(int k=1;k<repeatN && running && r==XR_SUCCESS;k++){
        if(!waited && !waitFrame())break;
        waited=0;
        if(p_xrBeginFrame(sess,0)!=XR_SUCCESS)break;
        fe.displayTime=nextPredicted;fe.layerCount=nextShouldRender?nl:0;
        r=p_xrEndFrame(sess,&fe);
        if(r!=XR_SUCCESS){lastError=r;LOGW("xrEndFrame (repeat) %d",r);}
    }
    // Block for the next headset frame now, while GameMaker would otherwise sleep in its own 60 fps limiter.
    if(cfg.early_wait && running && !waited)waitFrame();
    tSubmitEnd=nowMs();
    return r==XR_SUCCESS;
}
// type 0 held, 1 pressed, 2 released (the game's input_check convention)
API vhrq_verb(double type,double verb){
    int v=(int)verb,t=(int)type;
    static int calls=0;if(calls<5){calls++;LOGI("vhrq_verb called type=%d verb=%d sess=%d",t,v,sess!=0);}
    if(v<0||v>=V_COUNT||!sess)return 0;
    if(t==0)return verbNow[v];if(t==1)return verbNow[v]&&!verbPrev[v];return !verbNow[v]&&verbPrev[v];
}
// End Step of obj_vhrq (the last object, so it runs after every other End Step): sample Touch
// once per game step. Press edges then hold for exactly one full step, whatever each object's event order.
API vhrq_input(void){
    if(!sess||!running)return 0;
    endRepeatOpenReal();
    if(sstate==XR_SESSION_STATE_FOCUSED)updateInput();
    else{memcpy(verbPrev,verbNow,sizeof verbNow);memset(verbNow,0,sizeof verbNow);}
    return 1;
}
API vhrq_axis(double which){(void)which;return steer;}
API vhrq_wheel_deg(void){return wheelDeg;}
API vhrq_grip(void){return gripMode;}
API vhrq_btn(double id){if((int)id==1)return viewTogglePressed;return 0;}
API vhrq_haptic(double strength,double frames){
    if(!sess||!running||!cfg.haptics||strength<=0)return 0;
    // Strong by default: the game's values are scaled up (haptic_scale 1.6) with a floor, since Touch
    // controllers barely buzz below about 0.35. A weaker buzz never cuts a stronger one short.
    static double hapUntil=0;static float hapAmp=0;
    float amp=(float)(strength*cfg.haptic_scale);if(amp<0.35f)amp=0.35f;if(amp>1)amp=1;
    double durMs=frames*1000.0/60.0;if(durMs<40)durMs=40;
    double t=nowMs();
    if(t<hapUntil && amp<hapAmp)return 1;
    hapAmp=amp;hapUntil=t+durMs;
    XrHapticVibration v={XR_TYPE_HAPTIC_VIBRATION};v.amplitude=amp;
    v.duration=(XrDuration)(durMs*1e6);v.frequency=XR_FREQUENCY_UNSPECIFIED;
    for(int h=0;h<2;h++){XrHapticActionInfo hi={XR_TYPE_HAPTIC_ACTION_INFO};hi.action=aHaptic;hi.subactionPath=hand[h];p_xrApplyHapticFeedback(sess,&hi,(XrHapticBaseHeader*)&v);}
    return 1;
}
API vhrq_get(double key){
    load_config();
    int k=(int)key;
    if(k==0)return renderEye>0?renderEye:(cfg.eye_size>0?cfg.eye_size:1280); // render size per eye (dynamic)
    if(k==1)return cfg.wheel_lock;if(k==2)return cfg.steer_mode;if(k==3)return cfg.cockpit_paint;if(k==4)return cfg.fov_symmetric;if(k==5)return cfg.foveation;return 0;
}
// Options menu: key 2 = steering (0 virtual wheel, 1 thumbstick). Saved for the next launch.
API vhrq_set(double key,double val){
    load_config();
    if((int)key==2){cfg.steer_mode=val>0.5?1:0;wheelDeg=0;steer=0;LOGI("steering: %s",cfg.steer_mode?"thumbstick":"virtual wheel");return 1;}
    if((int)key==3){cfg.cockpit_paint=val>0.5?1:0;save_settings();return 1;}
    if((int)key==4){cfg.fov_symmetric=(int)(val+0.5);save_settings();LOGI("lens fit %d",cfg.fov_symmetric);return 1;}
    if((int)key==5){cfg.foveation=(int)(val+0.5);save_settings();fovTex=0;LOGI("foveation %d",cfg.foveation);return 1;}
    return 0;
}
// PC-only entry points kept so the shared GML compiles; the G29 path stays disabled on Quest.
API vhrq_mpoll(double a){(void)a;return 0;}
API vhrq_mkey(double a,double b){(void)a;(void)b;return 0;}
API vhrq_wheel_api(void){return -1;}
API vhrq_wstop(void){return 0;}
API vhrq_wpoll(void){return 0;}
API vhrq_wvalue(double k){(void)k;return 0;}
API vhrq_wforce(double a,double b,double c){(void)a;(void)b;(void)c;return 0;}

// ---------------------------------------------------------------- JNI entry (GameMaker Java extension)
// GameMaker's Android runner cannot load native extension libraries; it calls Java methods
// on com.segadreamcat.vhrquest.VHRQuest, which forward here with a function index.
__attribute__((visibility("default"))) jint JNI_OnLoad(JavaVM* vm,void* reserved){(void)reserved;jvm=vm;LOGI("libvhrvr loaded");return JNI_VERSION_1_6;}
// GML messages (room changes, GML errors) into the same log.
__attribute__((visibility("default"))) void Java_com_segadreamcat_vhrquest_VHRQuest_logs(JNIEnv* env,jclass c,jstring msg){
    (void)c;if(!msg)return;load_config();const char* u=(*env)->GetStringUTFChars(env,msg,0);
    if(u){LOGI("game: %s",u);(*env)->ReleaseStringUTFChars(env,msg,u);}
}
__attribute__((visibility("default"))) void Java_com_segadreamcat_vhrquest_VHRQuest_ctx(JNIEnv* env,jclass c,jobject activity){
    (void)c;if(activity && !jctx){jctx=(*env)->NewGlobalRef(env,activity);LOGI("activity received from Java");}
}
__attribute__((visibility("default"))) jdouble Java_com_segadreamcat_vhrquest_VHRQuest_n(JNIEnv* env,jclass c,jint f,jdouble a,jdouble b,jdouble d){
    (void)env;(void)c;
    switch(f){
    case 0:return vhrq_init();case 1:return vhrq_stop();case 2:return vhrq_recenter();case 3:return vhrq_mode(a);
    case 4:return vhrq_frame();case 5:return vhrq_poll();case 6:return vhrq_active();case 7:return vhrq_value(a,b);
    case 8:return vhrq_submit(a,b,d);case 9:return vhrq_verb(a,b);case 10:return vhrq_axis(a);case 11:return vhrq_wheel_deg();
    case 12:return vhrq_grip();case 13:return vhrq_btn(a);case 14:return vhrq_haptic(a,b);case 15:return vhrq_get(a);
    case 16:return vhrq_mpoll(a);case 17:return vhrq_mkey(a,b);case 18:return vhrq_wheel_api();case 19:return vhrq_wstop();
    case 20:return vhrq_wpoll();case 21:return vhrq_wvalue(a);case 22:return vhrq_wforce(a,b,d);case 23:return vhrq_input();case 24:return vhrq_set(a,b);
    }
    return 0;
}

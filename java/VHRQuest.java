// Generated: GameMaker Java extension facade for libvhrvr.so (OpenXR bridge).
// The Android runner calls these by name via reflection with double arguments.
package com.segadreamcat.vhrquest;

public class VHRQuest {
    static { System.loadLibrary("vhrvr"); }
    private static native double n(int f, double a, double b, double c);
    private static native void ctx(Object activity);
    private static native void logs(String msg);
    private static boolean sentContext;
    public VHRQuest() {}
    public void Init() { sendContext(); }
    private static void sendContext() {
        if (sentContext) return;
        try {
            Object a = Class.forName("com.segadreamcat.vhrquest.RunnerActivity").getField("CurrentActivity").get(null);
            if (a != null) {
                // Make sure <external files> exists: vhrq.txt, saved settings and vhrq-log.txt live there.
                try { a.getClass().getMethod("getExternalFilesDir", String.class).invoke(a, (Object) null); } catch (Throwable t) { }
                ctx(a); sentContext = true;
            }
        } catch (Throwable t) { android_log("no RunnerActivity.CurrentActivity: " + t); }
    }
    private static void android_log(String s) { System.out.println("VHRQ " + s); }
    public double vhrq_init() { sendContext(); return n(0, 0, 0, 0); }
    public double vhrq_stop() { return n(1, 0, 0, 0); }
    public double vhrq_recenter() { return n(2, 0, 0, 0); }
    public double vhrq_mode(double a0) { return n(3, a0, 0, 0); }
    public double vhrq_frame() { double r = n(4, 0, 0, 0); if (r > 0) unpace(); return r; }
    public double vhrq_poll() { return n(5, 0, 0, 0); }
    public double vhrq_active() { return n(6, 0, 0, 0); }
    public double vhrq_value(double a0, double a1) { return n(7, a0, a1, 0); }
    public double vhrq_submit(double a0, double a1, double a2) { return n(8, a0, a1, a2); }
    public double vhrq_verb(double a0, double a1) { return n(9, a0, a1, 0); }
    public double vhrq_axis(double a0) { return n(10, a0, 0, 0); }
    public double vhrq_wheel_deg() { return n(11, 0, 0, 0); }
    public double vhrq_grip() { return n(12, 0, 0, 0); }
    public double vhrq_btn(double a0) { return n(13, a0, 0, 0); }
    public double vhrq_haptic(double a0, double a1) { return n(14, a0, a1, 0); }
    public double vhrq_get(double a0) { return n(15, a0, 0, 0); }
    public double vhrq_mpoll(double a0) { return n(16, a0, 0, 0); }
    public double vhrq_mkey(double a0, double a1) { return n(17, a0, a1, 0); }
    public double vhrq_wheel_api() { return n(18, 0, 0, 0); }
    public double vhrq_wstop() { return n(19, 0, 0, 0); }
    public double vhrq_wpoll() { return n(20, 0, 0, 0); }
    public double vhrq_wvalue(double a0) { return n(21, a0, 0, 0); }
    public double vhrq_wforce(double a0, double a1, double a2) { return n(22, a0, a1, a2); }
    public double vhrq_input() { return n(23, 0, 0, 0); }
    public double vhrq_set(double a0, double a1) { return n(24, a0, a1, 0); }
    public double vhrq_log(String msg) { try { logs(msg); } catch (Throwable t) { } return 0; }

    // GameMaker's Android runner paces itself by counting the phone display's vsyncs
    // (DemoRenderer.WaitForVsync, fed by a Choreographer callback). On Quest that is the 2D panel's
    // 72 Hz clock: a 60 fps game waited for two ticks every step and ran at 36 fps. In VR the headset
    // paces frames instead (libvhrvr.so), so stop the vsync counter. -1 makes WaitForVsync return at once.
    private static java.lang.reflect.Field vsyncCount;
    private static int unpaceFrames;
    private static void unpace() {
        try {
            if (vsyncCount == null) vsyncCount = Class.forName("com.segadreamcat.vhrquest.DemoRenderer").getField("elapsedVsyncs");
            vsyncCount.setInt(null, -1);
            // The runner re-posts its callback on resume/surface changes: remove it again now and then.
            if ((unpaceFrames++ % 120) != 0) return;
            final Object act = Class.forName("com.segadreamcat.vhrquest.RunnerActivity").getField("CurrentActivity").get(null);
            if (act == null) return;
            final Object handler = act.getClass().getField("vsyncHandler").get(act);
            if (handler == null) return;
            Runnable stop = new Runnable() {
                public void run() {
                    try {
                        handler.getClass().getMethod("RemoveFrameCallback").invoke(handler);
                        vsyncCount.setInt(null, -1);
                    } catch (Throwable t) { android_log("vsync stop failed: " + t); }
                }
            };
            act.getClass().getMethod("runOnUiThread", Runnable.class).invoke(act, stop);
            if (unpaceFrames == 1) android_log("GameMaker vsync pacing off; the headset paces frames");
        } catch (Throwable t) { if (unpaceFrames < 3) android_log("unpace failed: " + t); }
    }
}

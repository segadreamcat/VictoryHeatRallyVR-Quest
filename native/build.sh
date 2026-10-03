#!/bin/sh
# Builds libvhrvr.so (Quest, arm64 Android) without the NDK: zig's clang + stub import libs.
# Needs: python3 with `pip install ziglang`, curl (first run fetches Khronos/JNI headers).
set -e
cd "$(dirname "$0")"
ZCC="python3 -m ziglang cc -target aarch64-linux-musl"
R=https://raw.githubusercontent.com
if [ ! -f inc/openxr/openxr.h ]; then
  mkdir -p inc/openxr inc/GLES3 inc/EGL inc/KHR inc/android
  for f in openxr.h openxr_platform.h openxr_platform_defines.h openxr_loader_negotiation.h; do curl -sSfo inc/openxr/$f $R/KhronosGroup/OpenXR-SDK/main/include/openxr/$f; done
  for f in gl3.h gl3platform.h; do curl -sSfo inc/GLES3/$f $R/KhronosGroup/OpenGL-Registry/main/api/GLES3/$f; done
  for f in egl.h eglext.h eglplatform.h; do curl -sSfo inc/EGL/$f $R/KhronosGroup/EGL-Registry/main/api/EGL/$f; done
  curl -sSfo inc/KHR/khrplatform.h $R/KhronosGroup/EGL-Registry/main/api/KHR/khrplatform.h
  curl -sSfo inc/jni.h $R/openjdk/jdk/master/src/java.base/share/native/include/jni.h
  curl -sSfo inc/jni_md.h $R/openjdk/jdk/master/src/java.base/unix/native/include/jni_md.h
  printf 'struct ANativeWindow;typedef struct ANativeWindow ANativeWindow;\n' > inc/android/native_window.h
fi
# Stub shared objects only give the linker correct DT_NEEDED names; Android supplies the real ones.
mkdir -p stubs
stub(){ n=$1; shift; : > stubs/$n.c; for s in "$@"; do echo "void $s(void){}" >> stubs/$n.c; done
  $ZCC -nostdlib -shared -fPIC -w -Wl,-soname,$n.so stubs/$n.c -o stubs/$n.so; }
stub libc open read write close clock_gettime dl_iterate_phdr mprotect snprintf strchr strcmp strncpy strstr memset memcpy strcpy strlen nanosleep pthread_self vsnprintf rename
stub liblog __android_log_print
stub libm atan2f cosf expf sinf tanf fabsf
stub libdl dlerror dlopen dlsym
stub libEGL eglSwapInterval eglChooseConfig eglGetCurrentContext eglGetCurrentDisplay eglQueryContext eglGetProcAddress
stub libGLESv3 glFlush glBindFramebuffer glBlitFramebuffer glDisable glEnable glFramebufferTexture2D glGenFramebuffers glGetIntegerv glGetString glIsEnabled glViewport glGetFramebufferAttachmentParameteriv glBindTexture glTexParameteri glGetError glGetTexParameteriv
$ZCC -D__ANDROID__ -O2 -fPIC -fvisibility=hidden -fno-stack-protector -Wall -I inc -c vhrq.c -o vhrq.o
$ZCC -nostdlib -shared -fPIC -s -Wl,-soname,libvhrvr.so -Wl,--no-as-needed -Wl,-z,defs -Wl,--hash-style=both -Wl,--build-id \
  vhrq.o stubs/liblog.so stubs/libEGL.so stubs/libGLESv3.so stubs/libm.so stubs/libdl.so stubs/libc.so -o libvhrvr.so
echo "built $(pwd)/libvhrvr.so"

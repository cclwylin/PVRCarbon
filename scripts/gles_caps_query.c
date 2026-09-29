// Print the GLES implementation limits the current EGL driver reports, one
// "pname value" line per limit, for scripts/gles_caps_shim.c to clamp to.
// Runs on surfaceless EGL, e.g. with the environment of replay_on_pvrgpu.sh.
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl32.h>
#include <stdio.h>

#include "gles_caps.h"

int main(void)
{
    EGLDisplay dpy = eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
    if (!eglInitialize(dpy, NULL, NULL) || !eglBindAPI(EGL_OPENGL_ES_API))
        return 1;
    const EGLint config_attribs[] = {EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_NONE};
    EGLConfig config;
    EGLint n = 0;
    eglChooseConfig(dpy, config_attribs, &config, 1, &n);
    const EGLint context_attribs[] = {EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 2, EGL_NONE};
    EGLContext ctx = eglCreateContext(dpy, n ? config : EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, context_attribs);
    if (ctx == EGL_NO_CONTEXT || !eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx))
        return 1;
    for (unsigned i = 0; i < sizeof(gles_caps) / sizeof(gles_caps[0]); ++i) {
        GLint v[2] = {0, 0};
        glGetIntegerv(gles_caps[i], v);
        if (glGetError() == GL_NO_ERROR)
            printf("0x%04X %d %d\n", gles_caps[i], v[0], v[1]);
    }
    return 0;
}

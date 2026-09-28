// LD_PRELOAD shim for recording GFXBench with PVRCarbon.
//
// GFXBench's GLEW resolves GL entry points through glXGetProcAddress(ARB), which
// hands back Mesa's functions and bypasses the PVRCarbon GLES recorder. Resolve
// gl* names through the recorder instead (preloaded libGLESv2 / eglGetProcAddress)
// and leave glX* names to the real libGL.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>

typedef void (*fn_t)(void);

static fn_t real_glx(const char *sym, const unsigned char *name)
{
    static void *libgl;
    if (!libgl)
        libgl = dlopen("libGL.so.1", RTLD_NOW | RTLD_GLOBAL);
    fn_t (*real)(const unsigned char *) = libgl ? (fn_t (*)(const unsigned char *))dlsym(libgl, sym) : 0;
    return real ? real(name) : 0;
}

static fn_t via_recorder(const unsigned char *name)
{
    const char *n = (const char *)name;
    if (strncmp(n, "gl", 2) != 0 || strncmp(n, "glX", 3) == 0)
        return 0;
    fn_t p = (fn_t)dlsym(RTLD_DEFAULT, n);
    if (p)
        return p;
    fn_t (*egl_gpa)(const char *) = (fn_t (*)(const char *))dlsym(RTLD_DEFAULT, "eglGetProcAddress");
    return egl_gpa ? egl_gpa(n) : 0;
}

fn_t glXGetProcAddressARB(const unsigned char *name)
{
    fn_t p = via_recorder(name);
    return p ? p : real_glx("glXGetProcAddressARB", name);
}

fn_t glXGetProcAddress(const unsigned char *name)
{
    fn_t p = via_recorder(name);
    return p ? p : real_glx("glXGetProcAddress", name);
}

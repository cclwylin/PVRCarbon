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

// GFXBench enables desktop GL's GL_TEXTURE_CUBE_MAP_SEAMLESS, which GLES does
// not have (its cube maps are always seamless; the call is GL_INVALID_ENUM).
// PVRCarbonTrim segfaults snapshotting that state, so it never reaches the
// recorder. The shim is preloaded first, so both direct calls and the lookups
// above land here.
#define GL_TEXTURE_CUBE_MAP_SEAMLESS 0x884F

void glEnable(unsigned int cap)
{
    static void (*next)(unsigned int);
    if (!next)
        next = (void (*)(unsigned int))dlsym(RTLD_NEXT, "glEnable");
    if (cap != GL_TEXTURE_CUBE_MAP_SEAMLESS && next)
        next(cap);
}

void glDisable(unsigned int cap)
{
    static void (*next)(unsigned int);
    if (!next)
        next = (void (*)(unsigned int))dlsym(RTLD_NEXT, "glDisable");
    if (cap != GL_TEXTURE_CUBE_MAP_SEAMLESS && next)
        next(cap);
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

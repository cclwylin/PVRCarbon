// LD_PRELOAD shim that makes an application see implementation limits no
// larger than another driver's, so a recording made on the host (llvmpipe)
// only uses sizes and unit counts the replay driver (e.g. PvrGPU) accepts.
//
//   GLES_CAPS_FILE=pvrgpu.caps LD_PRELOAD=gles_caps_shim.so:<recorder libs> app
//
// GLES_CAPS_FILE holds "pname v0 v1" lines from scripts/gles_caps_query.c run
// on the replay driver. Each queried limit is clamped toward that value: the
// smaller one for maxima, the larger for GL_MIN_PROGRAM_TEXEL_OFFSET. The
// shim is preloaded first and also interposes dlsym (dEQP resolves
// eglGetProcAddress from its libEGL handle and GL entry points through it),
// so direct calls, dlsym and eglGetProcAddress lookups all reach it; the
// real query still goes through the recorder.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define GL_MIN_PROGRAM_TEXEL_OFFSET 0x8904

struct cap { unsigned pname; long long v[2]; };
static struct cap caps[64];
static unsigned cap_count;

__attribute__((constructor)) static void load_caps(void)
{
    const char *path = getenv("GLES_CAPS_FILE");
    FILE *f = path ? fopen(path, "r") : NULL;
    if (!f)
        return;
    unsigned pname;
    long long a, b;
    while (cap_count < sizeof(caps) / sizeof(caps[0]) &&
           fscanf(f, "%x %lld %lld", &pname, &a, &b) == 3)
        caps[cap_count++] = (struct cap){pname, {a, b}};
    fclose(f);
}

static const struct cap *find(unsigned pname)
{
    for (unsigned i = 0; i < cap_count; ++i)
        if (caps[i].pname == pname)
            return &caps[i];
    return NULL;
}

static long long clamp(unsigned pname, long long host, long long target)
{
    if (pname == GL_MIN_PROGRAM_TEXEL_OFFSET)
        return host > target ? host : target;
    return host < target ? host : target;
}

static void *(*real_dlsym)(void *, const char *);

static void *next(const char *name)
{
    if (!real_dlsym) {
        real_dlsym = (void *(*)(void *, const char *))dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.34");
        if (!real_dlsym)
            real_dlsym = (void *(*)(void *, const char *))dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.2.5");
    }
    return real_dlsym(RTLD_NEXT, name);
}

void glGetIntegerv(unsigned pname, int *data)
{
    static void (*real)(unsigned, int *);
    if (!real)
        real = (void (*)(unsigned, int *))next("glGetIntegerv");
    real(pname, data);
    const struct cap *c = find(pname);
    if (c && data)
        for (int i = 0; i < (pname == 0x0D3A ? 2 : 1); ++i)
            data[i] = (int)clamp(pname, data[i], c->v[i]);
}

void glGetInteger64v(unsigned pname, int64_t *data)
{
    static void (*real)(unsigned, int64_t *);
    if (!real)
        real = (void (*)(unsigned, int64_t *))next("glGetInteger64v");
    real(pname, data);
    const struct cap *c = find(pname);
    if (c && data)
        for (int i = 0; i < (pname == 0x0D3A ? 2 : 1); ++i)
            data[i] = clamp(pname, data[i], c->v[i]);
}

void glGetFloatv(unsigned pname, float *data)
{
    static void (*real)(unsigned, float *);
    if (!real)
        real = (void (*)(unsigned, float *))next("glGetFloatv");
    real(pname, data);
    const struct cap *c = find(pname);
    if (c && data)
        for (int i = 0; i < (pname == 0x0D3A ? 2 : 1); ++i)
            if (pname == GL_MIN_PROGRAM_TEXEL_OFFSET ? data[i] < c->v[i] : data[i] > c->v[i])
                data[i] = (float)c->v[i];
}

typedef void (*fn_t)(void);

static fn_t wrapper(const char *name)
{
    if (!name)
        return NULL;
    if (!strcmp(name, "glGetIntegerv"))
        return (fn_t)glGetIntegerv;
    if (!strcmp(name, "glGetInteger64v"))
        return (fn_t)glGetInteger64v;
    if (!strcmp(name, "glGetFloatv"))
        return (fn_t)glGetFloatv;
    return NULL;
}

// The recorder looks up the host driver's entry points with dlsym too; it
// must get the real ones, or it would call back into this shim forever.
static int called_from_recorder(const void *address)
{
    Dl_info info;
    return dladdr(address, &info) && info.dli_fname && strstr(info.dli_fname, "PVRCarbon");
}

fn_t eglGetProcAddress(const char *name);

void *dlsym(void *handle, const char *name)
{
    /* dEQP resolves eglGetProcAddress from its libEGL handle and every GL
     * entry point through that, so hand out this shim's version too. */
    fn_t w = !strcmp(name, "eglGetProcAddress") ? (fn_t)eglGetProcAddress : wrapper(name);
    if (w && handle != RTLD_NEXT && !called_from_recorder(__builtin_return_address(0)))
        return (void *)w;
    next("dlsym");  /* resolves real_dlsym */
    return real_dlsym(handle, name);
}

fn_t eglGetProcAddress(const char *name)
{
    static fn_t (*real)(const char *);
    fn_t w = wrapper(name);
    if (w && !called_from_recorder(__builtin_return_address(0)))
        return w;
    if (!real)
        real = (fn_t (*)(const char *))next("eglGetProcAddress");
    return real ? real(name) : NULL;
}

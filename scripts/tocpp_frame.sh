#!/usr/bin/env bash
# Export a (single-frame) PVRCarbon recording to a standalone C++ program with
# PVRCarbonToCpp, add two opt-in hooks to the generated frame, and build it.
#
#   scripts/tocpp_frame.sh <recording.pvrcbn> [outdir]
#
# The program then runs without PVRCarbon on any EGL/GLES driver:
#   PBUFFER=1       render into a pbuffer of the recorded size instead of a
#                   window (needed for surfaceless EGL, e.g. the PvrGPU Mesa)
#   CAPTURE_PPM=f   read the default framebuffer back before each swap into f
# Two builds are made: build/ (X11 window) and build-headless/ (no window
# system, use with EGL_PLATFORM=surfaceless PBUFFER=1).
set -euo pipefail

rec="$(realpath "$1")"
name="$(basename "$rec" .pvrcbn)"
out="$(realpath -m "${2:-out/tocpp/$name}")"
PVRCARBON_DIR="${PVRCARBON_DIR:-/opt/PVRCarbon}"

rm -rf "$out"
mkdir -p "$(dirname "$out")"
"$PVRCARBON_DIR/CLI/Linux_x86_64/PVRCarbonToCpp" -o="$out" --name="$name" "$rec" >/dev/null

python3 - "$out" <<'EOF'
import glob, re, sys
out = sys.argv[1]
for path in glob.glob(f"{out}/src/threads/*/thread*_frame*.cpp"):
    s = open(path).read()
    s = s.replace("EGL_SURFACE_TYPE, EGL_WINDOW_BIT | EGL_SWAP_BEHAVIOR_PRESERVED_BIT,",
                  'EGL_SURFACE_TYPE, getenv("PBUFFER") ? EGL_PBUFFER_BIT : '
                  "(EGL_WINDOW_BIT | EGL_SWAP_BEHAVIOR_PRESERVED_BIT),")
    # Window creation -> optional pbuffer of the recorded size.
    s = re.sub(
        r"(#if defined\(SUPPORT_WAYLAND\)\n\tnativeWindow = .*?\n#endif\n\t\n"
        r"\tsurface = eglCreateWindowSurface\(display, config, nativeWindow, attribs2\.data\(\)\);)",
        lambda m: ('\tif (getenv("PBUFFER")) {\n'
                   "\t\tconst EGLint pbuffer[] = { EGL_WIDTH, %s, EGL_HEIGHT, %s, EGL_NONE };\n"
                   "\t\tsurface = eglCreatePbufferSurface(display, config, pbuffer);\n"
                   "\t} else {\n%s\n\t}") % (
                       *re.search(r"get<EGLNativeWindowType>\([^,]+, [^,]+, (\d+), (\d+)\)",
                                  m.group(1)).groups(), m.group(1)),
        s, flags=re.S)
    s = s.replace("\tplatformManager.present(",
                  '\tif (!getenv("PBUFFER")) platformManager.present(')
    capture = r'''	if (const char *capture = getenv("CAPTURE_PPM")) {
		GLint fb = 0; glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &fb);
		glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
		EGLint w = 0, h = 0;
		eglQuerySurface(display, surface, EGL_WIDTH, &w);
		eglQuerySurface(display, surface, EGL_HEIGHT, &h);
		std::vector<unsigned char> px(static_cast<size_t>(w) * h * 4);
		glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, px.data());
		if (FILE *f = fopen(capture, "wb")) {
			fprintf(f, "P6\n%d %d\n255\n", w, h);
			for (EGLint y = h - 1; y >= 0; --y)
				for (EGLint x = 0; x < w; ++x)
					fwrite(&px[(static_cast<size_t>(y) * w + x) * 4], 1, 3, f);
			fclose(f);
		}
		glBindFramebuffer(GL_READ_FRAMEBUFFER, fb);
	}
	eglSwapBuffers(display, surface);'''
    s = s.replace("\teglSwapBuffers(display, surface);", capture)
    s = s.replace('#include "threads/shared.h"',
                  '#include "threads/shared.h"\n#include <cstdio>\n#include <cstdlib>\n#include <vector>', 1)
    open(path, "w").write(s)
EOF

cmake -S "$out" -B "$out/build" -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake -S "$out" -B "$out/build-headless" -G Ninja -DCMAKE_BUILD_TYPE=Release -DX11=OFF >/dev/null
ninja -C "$out/build" >/dev/null
ninja -C "$out/build-headless" >/dev/null
echo "$out/build/bin/$name"
echo "$out/build-headless/bin/$name"

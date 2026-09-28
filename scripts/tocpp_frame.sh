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
#   MARK_FRAME="n ..." MARK_OUT=f
#                   at the start of each listed recorded frame, glFinish() and
#                   append "frame bytes" to f, bytes being the size of
#                   $PVRGPU_SYSTEMC_JSONL_OUT (PvrGPU's model.jsonl) then, so
#                   scripts/frame_sim_time.py can split the simulated time
# Two builds are made: build/ (X11 window) and build-headless/ (no window
# system, use with EGL_PLATFORM=surfaceless PBUFFER=1).
#
# Env: TOCPP_ARGS  extra PVRCarbonToCpp arguments (e.g. --frame-range=2-2)
set -euo pipefail

rec="$(realpath "$1")"
name="$(basename "$rec" .pvrcbn)"
out="$(realpath -m "${2:-out/tocpp/$name}")"
PVRCARBON_DIR="${PVRCARBON_DIR:-/opt/PVRCarbon}"

rm -rf "$out"
mkdir -p "$(dirname "$out")"
# shellcheck disable=SC2086
"$PVRCARBON_DIR/CLI/Linux_x86_64/PVRCarbonToCpp" -o="$out" --name="$name" ${TOCPP_ARGS:-} "$rec" >/dev/null

python3 - "$out" <<'EOF'
import glob, re, sys
out = sys.argv[1]
mark = r'''
static void pvrcarbonMarkFrame(int frame)
{
	const char *want = getenv("MARK_FRAME"), *out = getenv("MARK_OUT");
	const char *jsonl = getenv("PVRGPU_SYSTEMC_JSONL_OUT");
	if (!want || !out || !jsonl || eglGetCurrentContext() == EGL_NO_CONTEXT)
		return;
	bool listed = false;
	for (const char *p = want; *p;) {
		char *end;
		const long n = strtol(p, &end, 10);
		if (end == p) { ++p; continue; }
		listed |= n == frame;
		p = end;
	}
	if (!listed)
		return;
	glFinish();
	struct stat st;
	if (FILE *f = fopen(out, "a")) {
		fprintf(f, "%d %lld\n", frame, stat(jsonl, &st) == 0 ? (long long)st.st_size : -1LL);
		fclose(f);
	}
}
'''
for path in glob.glob(f"{out}/src/threads/*/thread*_frame*.cpp"):
    s = open(path).read()
    frame = int(re.search(r"_frame(\d+)\.cpp$", path).group(1))
    s = re.sub(r"(void runThread\d+Frame\d+\(\)\n\{\n)",
               lambda m: m.group(1) + f"\tpvrcarbonMarkFrame({frame});\n", s, count=1)
    s = s.replace("EGL_SURFACE_TYPE, EGL_WINDOW_BIT | EGL_SWAP_BEHAVIOR_PRESERVED_BIT,",
                  'EGL_SURFACE_TYPE, getenv("PBUFFER") ? EGL_PBUFFER_BIT : '
                  "(EGL_WINDOW_BIT | EGL_SWAP_BEHAVIOR_PRESERVED_BIT),")
    # Window creation -> optional pbuffer of the recorded size.
    s = re.sub(
        r"(#if defined\(SUPPORT_WAYLAND\)\n\tnativeWindow = .*?\n#endif\n\t\n"
        r"\tsurface = eglCreateWindowSurface\(display, config, nativeWindow, \w+\.data\(\)\);)",
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
                  '#include "threads/shared.h"\n#include <cstdio>\n#include <cstdlib>\n#include <vector>\n'
                  '#include <sys/stat.h>\n' + mark, 1)
    open(path, "w").write(s)
EOF

cmake -S "$out" -B "$out/build" -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake -S "$out" -B "$out/build-headless" -G Ninja -DCMAKE_BUILD_TYPE=Release -DX11=OFF >/dev/null
ninja -C "$out/build" >/dev/null
ninja -C "$out/build-headless" >/dev/null
echo "$out/build/bin/$name"
echo "$out/build-headless/bin/$name"

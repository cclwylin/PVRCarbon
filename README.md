# PVRCarbon

Record GFXBench (open-source GFXBench 5, GLES) with PVRCarbon on a headless
Linux host using Mesa software rendering (llvmpipe; no GPU needed).

## Steps

```bash
scripts/setup_env.sh        # Mesa EGL/GLES 3.2 + Vulkan (lavapipe) + Xvfb
scripts/build_gfxbench.sh   # clone + build Kishonti-Opensource/gfxbench -> tfw-pkg/bin/testfw_app
scripts/run_gfxbench.sh     # run the default test set, 10 frames each
```

`run_gfxbench.sh` accepts test ids (`ls <gfxbench>/tfw-pkg/config`) and the env
vars `FRAMES`, `STEP_MS`, `WIDTH`, `HEIGHT`, `OUT_DIR`, `WRAPPER`.

| test id          | scene              | llvmpipe, 640x360 |
|------------------|--------------------|-------------------|
| `gl_trex`        | T-Rex              | OK, ~1.1 fps      |
| `gl_manhattan`   | Manhattan 3.0      | OK, ~1.3 fps      |
| `gl_manhattan31` | Manhattan 3.1      | OK, ~1.0 fps      |
| `gl_4`           | Car Chase          | OK, ~2.0 fps      |
| `gl_5_normal`    | Aztec Ruins Normal | OK, ~6.9 fps      |
| `gl_5_high`      | Aztec Ruins High   | OK, ~4.5 fps      |

## PVRCarbon

Not installed yet: the PVRCarbon Linux package has to be downloaded from
developer.imaginationtech.com (blocked by this environment's network policy)
or committed to this repo. Once available, launch GFXBench through it via
`WRAPPER`.

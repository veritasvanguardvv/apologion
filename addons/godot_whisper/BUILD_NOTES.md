# About the Windows DLL in bin/

`libgodot_whisper.windows.template_release.x86_64.dll` is **not** the DLL from
the official Godot Whisper v2.0.3 release. The official one is linked against
`vulkan-1.dll`. That file only exists on PCs whose graphics driver installed
the Vulkan runtime. Without it, Windows refuses to load the addon (error 126,
"module not found") and the game says voice isn't available.

This copy was built from the same v2.0.3 source with the CPU backend only
(plus the OpenCL backend, whose loader is built in and only used on supported
Intel/Adreno GPUs). Vulkan is turned off:

    git clone --branch v2.0.3 --recursive https://github.com/appsinacup/godot-whisper
    scons platform=windows use_mingw=yes target=template_release arch=x86_64 vulkan=no

It was cross-compiled with MinGW-w64 GCC 14. libstdc++ and libgcc are linked
in statically. It only needs DLLs that every Windows 10/11 PC has: KERNEL32,
ADVAPI32, CFGMGR32, ole32 and msvcrt. It was tested with the official Windows
build of Godot 4.7.2 (under Wine, with vulkan-1.dll removed): it loads and
transcribes the test WAVs.

The project setting `audio/input/transcribe/use_gpu = false` keeps it on the
CPU, which is the most reliable choice. With the tiny model a sentence takes
about 1-5 seconds.

Licenses: Godot Whisper (MIT, see LICENSE), whisper.cpp/ggml (MIT),
libsamplerate (BSD-2), Khronos OpenCL ICD loader (Apache-2.0), GCC runtime
(GPL with the GCC Runtime Library Exception).

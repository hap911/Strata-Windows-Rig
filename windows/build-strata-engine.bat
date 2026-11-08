@echo off
rem Builds the patched DeepSeek engine (strata-dsv41.exe) from this repo into build\Release.
rem   build-strata-engine.bat configure   - CMake configure (downloads the pinned llama.cpp/ggml), then drops in the
rem                                         IQ1_M CPU-kernel fix (windows\patches\ggml\quants.c, see the .patch next to it)
rem   build-strata-engine.bat build       - compile (20-40 min the first time)
rem   build-strata-engine.bat install     - copy the result into windows\rig\engine\<version>\ (OUTSIDE Strata's
rem                                         folders, so an engine update cannot delete it) and save the official exe+dll
rem                                         of that folder into windows\rig\official\<version>\
rem Needs: Visual Studio 2022 Build Tools (MSVC 14.44+), CMake, CUDA 13 toolkit. Adjust CUDA_VER if yours differs.
setlocal
set "CUDA_VER=v13.4"
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set "CUDA_PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\%CUDA_VER%"
set "PATH=%CUDA_PATH%\bin;%PATH%"
cd /d "%~dp0.."
if /i "%1"=="configure" (
  "C:\Program Files\CMake\bin\cmake.exe" -S . -B build -G "Visual Studio 17 2022" -A x64 -DSTRATA_ENABLE_CUDA=ON -DSTRATA_BUILD_DSV41=ON -DSTRATA_PORTABLE=ON -DGGML_NATIVE=OFF "-DCMAKE_CUDA_ARCHITECTURES=86-real;89-real;120" "-DCMAKE_CUDA_FLAGS=--threads=2"
  if exist "build\_deps\strata_llamacpp-src\ggml\src\ggml-cpu\arch\x86\quants.c" (
    copy /y "windows\patches\ggml\quants.c" "build\_deps\strata_llamacpp-src\ggml\src\ggml-cpu\arch\x86\quants.c" >nul
    echo IQ1_M CPU-kernel fix applied to the downloaded ggml.
  ) else (
    echo WARNING: ggml source not found under build\_deps - the IQ1_M fix was not applied.
  )
) else if /i "%1"=="build" (
  "C:\Program Files\CMake\bin\cmake.exe" --build build --config Release --target strata-dsv41 -j 24
) else if /i "%1"=="install" (
  call "%~dp0rig\install-from-build.bat" "%~dp0..\build\Release"
) else (
  echo usage: build-strata-engine.bat configure ^| build ^| install
)

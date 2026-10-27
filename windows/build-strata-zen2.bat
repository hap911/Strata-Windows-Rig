@echo off
rem Zen 2 (Threadripper 3960X) targeted experiments - SEPARATE build dir (build-zen2), never touches build/ or build-native/.
rem Stage 1: build-strata-zen2.bat configure-instrument  -> PGO-instrumented build (MSVC /GL + /LTCG:PGINSTRUMENT)
rem          build-strata-zen2.bat build
rem          (run the instrumented exe through a realistic workload, flush .pgc with pgosweep)
rem Stage 2: build-strata-zen2.bat configure-pgo         -> link with /LTCG:PGOPTIMIZE using the collected profile
rem          build-strata-zen2.bat build
rem Same portable flags as the proven build (STRATA_PORTABLE=ON; native MSVC build was slower - do not change).
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set "CUDA_PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.4"
set "CUDA_PATH_V13_4=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.4"
set "PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.4\bin;%PATH%"
cd /d D:\strata\strata-src
set "PGD=D:/strata/strata-src/build-zen2/Release/strata-dsv41.pgd"
set "TC=-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY"
if "%1"=="configure-instrument" (
  "C:\Program Files\CMake\bin\cmake.exe" -S . -B build-zen2 -G "Visual Studio 17 2022" -A x64 "%TC%" -DSTRATA_ENABLE_CUDA=ON -DSTRATA_BUILD_DSV41=ON -DSTRATA_PORTABLE=ON "-DCMAKE_CUDA_ARCHITECTURES=86;120" "-DCMAKE_CXX_FLAGS=/GL" "-DCMAKE_EXE_LINKER_FLAGS=/LTCG:PGINSTRUMENT /PGD:%PGD%"
) else if "%1"=="configure-pgo" (
  "C:\Program Files\CMake\bin\cmake.exe" -S . -B build-zen2 -G "Visual Studio 17 2022" -A x64 "%TC%" -DSTRATA_ENABLE_CUDA=ON -DSTRATA_BUILD_DSV41=ON -DSTRATA_PORTABLE=ON "-DCMAKE_CUDA_ARCHITECTURES=86;120" "-DCMAKE_CXX_FLAGS=/GL" "-DCMAKE_EXE_LINKER_FLAGS=/LTCG:PGOPTIMIZE /PGD:%PGD%"
) else if "%1"=="configure-plain" (
  "C:\Program Files\CMake\bin\cmake.exe" -S . -B build-zen2 -G "Visual Studio 17 2022" -A x64 "%TC%" -DSTRATA_ENABLE_CUDA=ON -DSTRATA_BUILD_DSV41=ON -DSTRATA_PORTABLE=ON "-DCMAKE_CUDA_ARCHITECTURES=86;120"
) else if "%1"=="build" (
  if "%2"=="" (set J=24) else (set J=%2)
  "C:\Program Files\CMake\bin\cmake.exe" --build build-zen2 --config Release --target strata-dsv41 -j %J%
) else (
  echo usage: build-strata-zen2.bat configure-instrument^|configure-pgo^|configure-plain^|build
)

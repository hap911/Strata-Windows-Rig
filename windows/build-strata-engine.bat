@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set "CUDA_PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.4"
set "CUDA_PATH_V13_4=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.4"
set "PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.4\bin;%PATH%"
cd /d D:\strata\strata-src
if "%1"=="configure" (
  "C:\Program Files\CMake\bin\cmake.exe" -S . -B build -G "Visual Studio 17 2022" -A x64 -DSTRATA_ENABLE_CUDA=ON -DSTRATA_BUILD_DSV41=ON -DSTRATA_PORTABLE=ON "-DCMAKE_CUDA_ARCHITECTURES=86;120"
) else if "%1"=="configure-native" (
  "C:\Program Files\CMake\bin\cmake.exe" -S . -B build-native -G "Visual Studio 17 2022" -A x64 -DSTRATA_ENABLE_CUDA=ON -DSTRATA_BUILD_DSV41=ON "-DCMAKE_CUDA_ARCHITECTURES=86;120" "-DCMAKE_CXX_FLAGS=/arch:AVX2" "-DCMAKE_CUDA_FLAGS=-Xcompiler=/arch:AVX2"
) else if "%1"=="build-native" (
  "C:\Program Files\CMake\bin\cmake.exe" --build build-native --config Release --target strata-dsv41 -j 24
) else if "%1"=="build" (
  "C:\Program Files\CMake\bin\cmake.exe" --build build --config Release --target strata-dsv41 -j 24
)

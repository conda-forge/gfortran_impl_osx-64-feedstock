#!/bin/bash

set -xe

${PREFIX}/bin/${macos_machine}-gfortran --help

if [[ ${target_platform} == osx-64 ]]; then
  export CONDA_BUILD_SYSROOT="/opt/MacOSX10.9.sdk"
  export MACOSX_DEPLOYMENT_TARGET=10.9
fi

"${PREFIX}/bin/${macos_machine}-gfortran" -o hello hello.f90 -v -L$CONDA_BUILD_SYSROOT/usr/lib -L$CONDA_BUILD_SYSROOT/usr/lib/system
./hello
rm -f hello

"${PREFIX}/bin/${macos_machine}-gfortran" -O3 -fopenmp -ffast-math -o maths maths.f90 -v -L$CONDA_BUILD_SYSROOT/usr/lib -L$CONDA_BUILD_SYSROOT/usr/lib/system
./maths
rm -f maths

"${PREFIX}/bin/${macos_machine}-gfortran" -fopenmp -o omp-threadprivate omp-threadprivate.f90 -v -L$CONDA_BUILD_SYSROOT/usr/lib -L$CONDA_BUILD_SYSROOT/usr/lib/system
./omp-threadprivate
rm -f omp-threadprivate

${macos_machine}-gfortran -v
${macos_machine}-gfortran -E -dM - </dev/null

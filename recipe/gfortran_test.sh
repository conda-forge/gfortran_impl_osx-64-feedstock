#!/bin/bash

set -xe

${PREFIX}/bin/${macos_machine}-gfortran --help

if [[ "$target_platform" == "$cross_target_platform" ]]; then
  "${PREFIX}/bin/${macos_machine}-gfortran" -o hello hello.f90 -v -L$CONDA_BUILD_SYSROOT/usr/lib
  ./hello
  rm -f hello

  "${PREFIX}/bin/${macos_machine}-gfortran" -O3 -fopenmp -ffast-math -o maths maths.f90 -v -L$CONDA_BUILD_SYSROOT/usr/lib
  ./maths
  rm -f maths

  "${PREFIX}/bin/${macos_machine}-gfortran" -fopenmp -o omp-threadprivate omp-threadprivate.f90 -v -L$CONDA_BUILD_SYSROOT/usr/lib
  ./omp-threadprivate
  rm -f omp-threadprivate

  ${macos_machine}-gfortran -v
  ${macos_machine}-gfortran -E -dM - </dev/null
fi

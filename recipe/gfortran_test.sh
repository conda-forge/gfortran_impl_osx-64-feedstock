#!/bin/bash

set -xe

${PREFIX}/bin/${macos_machine}-gfortran --help

if [[ "$target_platform" == "$cross_target_platform" ]]; then
  "${PREFIX}/bin/${macos_machine}-gfortran" -o hello hello.f90
  ./hello
  rm -f hello

  "${PREFIX}/bin/${macos_machine}-gfortran" -O3 -fopenmp -ffast-math -o maths maths.f90
  ./maths
  rm -f maths
fi

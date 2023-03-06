#!/bin/bash

set -xe

${PREFIX}/bin/${macos_machine}-gfortran --help
${PREFIX}/bin/${macos_machine}-gfortran -v

if [[ "$target_platform" == "$cross_target_platform" ]]; then
  "${PREFIX}/bin/${macos_machine}-gfortran" -o hello hello.f90 -v
  ./hello
  rm -f hello

  "${PREFIX}/bin/${macos_machine}-gfortran" -O3 -fopenmp -ffast-math -o maths maths.f90 -v
  ./maths
  rm -f maths

  "${PREFIX}/bin/${macos_machine}-gfortran" -fopenmp -o omp-threadprivate omp-threadprivate.f90 -v
  ./omp-threadprivate
  rm -f omp-threadprivate

  ${macos_machine}-gfortran -v
  ${macos_machine}-gfortran -E -dM - </dev/null

  # check that we disable building C with gfortran
  echo "int main() {}" > test.c
  ! ${macos_machine}-gfortran test.c
fi

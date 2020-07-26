#!/bin/bash

set -e

${PREFIX}/bin/${macos_machine}-gfortran --help

cp ${RECIPE_DIR}/hello.f90 .
cp ${RECIPE_DIR}/maths.f90 .

"${PREFIX}/bin/${macos_machine}-gfortran" -o hello hello.f90
if [[ "$target_platform" == osx* ]]; then
  ./hello
fi
rm -f hello

"${PREFIX}/bin/${macos_machine}-gfortran" -O3 -fopenmp -ffast-math -o maths maths.f90
if [[ "$target_platform" == osx* ]]; then
  ./maths
fi
rm -f maths

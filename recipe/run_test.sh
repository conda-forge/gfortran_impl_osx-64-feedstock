#!/bin/bash

set -e

gfortran --help

cp ${RECIPE_DIR}/hello.f90 .
cp ${RECIPE_DIR}/maths.f90 .

"${PREFIX}/bin/gfortran" -o hello hello.f90
./hello
rm -f hello

"${PREFIX}/bin/gfortran" -O3 -fopenmp -ffast-math -o maths maths.f90
./maths
rm -f maths

#!/bin/bash

set -e

mkdir -p build_conda
cd build_conda

../configure \
    --prefix=${PREFIX} \
    --with-libiconv-prefix=${PREFIX} \
    --enable-languages=c,fortran \
    --with-tune=generic \
    --disable-multilib \
    --enable-checking=release \
    --disable-bootstrap \
    --build=${HOST} \
    --target=${macos_machine} \
    --with-gmp=${PREFIX} \
    --with-mpfr=${PREFIX} \
    --with-mpc=${PREFIX} \
    --with-isl=${PREFIX}

if [[ "$target_platform" == "osx-64" ]]; then
  # using || to quiet logs unless there is an issue
  {
      make -j"${CPU_COUNT}" >& make_logs.txt
  } || {
      tail -n 5000 make_logs.txt
      exit 1
  }

  # using || to quiet logs unless there is an issue
  {
      make install-strip >& make_install_logs.txt
  } || {
      tail -n 5000 make_install_logs.txt
      exit 1
  }
  rm $PREFIX/lib/libgomp.dylib
  rm $PREFIX/lib/libgomp.1.dylib
  ln -s $PREFIX/lib/libomp.dylib $PREFIX/lib/libgomp.dylib
  ln -s $PREFIX/lib/libomp.dylib $PREFIX/lib/libgomp.1.dylib

  pushd ${PREFIX}/lib
    sed -i.bak "s@^\*lib.*@& -rpath $PREFIX/lib@" libgfortran.spec
    rm libgfortran.spec.bak
  popd
else
  make all-gcc -j${CPU_COUNT}
  make install-gcc -j${CPU_COUNT}
  cp $RECIPE_DIR/libgomp.spec $PREFIX/lib
  sed "s/@CONDA_PREFIX@/$CONDA_PREFIX/g" $RECIPE_DIR/libgfortran.spec > $PREFIX/lib/libgfortran.spec
fi


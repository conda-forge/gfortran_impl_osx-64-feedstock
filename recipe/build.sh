#!/bin/bash

set -e

function start_spinner {
    if [ -n "$SPINNER_PID" ]; then
        return
    fi

    >&2 echo "Building libraries..."
    # Start a process that runs as a keep-alive
    # to avoid travis quitting if there is no output
    (while true; do
        sleep 60
        >&2 echo "Still building..."
    done) &
    SPINNER_PID=$!
    disown
}

function stop_spinner {
    if [ ! -n "$SPINNER_PID" ]; then
        return
    fi

    kill $SPINNER_PID
    unset SPINNER_PID

    >&2 echo "Building libraries finished."
}

start_spinner

mkdir -p build_conda
cd build_conda

../configure \
    --prefix=${PREFIX} \
    --with-libiconv-prefix=${PREFIX} \
    --enable-languages=c,fortran \
    --disable-multilib \
    --enable-checking=release \
    --disable-bootstrap \
    --target=${macos_machine} \
    --with-gmp=${PREFIX} \
    --with-mpfr=${PREFIX} \
    --with-mpc=${PREFIX} \
    --with-isl=${PREFIX}

if [[ "$target_platform" == "osx-"* ]]; then
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
  cp $RECIPE_DIR/libgomp.spec $PREFIX/lib/gcc/${macos_machine}/${PKG_VERSION}/libgomp.spec
  sed "s#@CONDA_PREFIX@#$PREFIX#g" $RECIPE_DIR/libgfortran.spec > $PREFIX/lib/gcc/${macos_machine}/${PKG_VERSION}/libgfortran.spec
fi

stop_spinner

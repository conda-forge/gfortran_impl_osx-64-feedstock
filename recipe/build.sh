#!/bin/bash

set -xe

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

function quiet_run {
    rm -f logs.txt
    if [[ -z "$CI" ]] || [[ "$target_platform" != osx*  ]]; then
        $@
    else
        {
            $@ >& logs.txt
        } || {
            tail -n 5000 logs.txt
            exit 1
        }
    fi
}

start_spinner

export host_platform=$target_platform
export TARGET=${macos_machine}

if [[ "$host_platform" != "$build_platform" ]]; then
    # If the compiler is a cross-native/canadian-cross compiler
    mkdir -p build_host
    pushd build_host
    CC=$CC_FOR_BUILD CXX=$CXX_FOR_BUILD AR="$($CC_FOR_BUILD -print-prog-name=ar)" LD="$($CC_FOR_BUILD -print-prog-name=ld)" \
         RANLIB="$($CC_FOR_BUILD -print-prog-name=ranlib)" NM="$($CC_FOR_BUILD -print-prog-name=nm)"  \
         CFLAGS="" CXXFLAGS="" CPPFLAGS="" LDFLAGS="-L$BUILD_PREFIX/lib -Wl,-rpath,$BUILD_PREFIX/lib" ../configure \
       --prefix=${BUILD_PREFIX} \
       --build=${BUILD} \
       --host=${BUILD} \
       --target=${TARGET} \
       --with-libiconv-prefix=${BUILD_PREFIX} \
       --enable-languages=c \
       --disable-multilib \
       --enable-checking=release \
       --disable-bootstrap \
       --with-gmp=${BUILD_PREFIX} \
       --with-mpfr=${BUILD_PREFIX} \
       --with-mpc=${BUILD_PREFIX} \
       --with-isl=${BUILD_PREFIX}
    echo "Building a compiler that runs on ${BUILD} and targets ${TARGET}"
    quiet_run make all-gcc -j${CPU_COUNT}
    quiet_run make install-gcc -j${CPU_COUNT}
    popd
fi

mkdir build_conda
cd build_conda

../configure \
    --prefix=${PREFIX} \
    --build=${BUILD} \
    --host=${HOST} \
    --target=${TARGET} \
    --with-libiconv-prefix=${PREFIX} \
    --enable-languages=c,fortran \
    --disable-multilib \
    --enable-checking=release \
    --disable-bootstrap \
    --with-gmp=${PREFIX} \
    --with-mpfr=${PREFIX} \
    --with-mpc=${PREFIX} \
    --with-isl=${PREFIX}

echo "Building a compiler that runs on ${HOST} and targets ${TARGET}"
if [[ "$host_platform" == "$cross_target_platform" ]]; then
  # If the compiler is a cross-native/native compiler
  make -j"${CPU_COUNT}" || (cat $TARGET/libgcc/config.log && false)
  quiet_run make install-strip
  rm $PREFIX/lib/libgomp.dylib
  rm $PREFIX/lib/libgomp.1.dylib
  ln -s $PREFIX/lib/libomp.dylib $PREFIX/lib/libgomp.dylib
  ln -s $PREFIX/lib/libomp.dylib $PREFIX/lib/libgomp.1.dylib

  pushd ${PREFIX}/lib
    sed -i.bak "s@^\*lib.*@& -rpath $PREFIX/lib@" libgfortran.spec
    rm libgfortran.spec.bak
  popd
else
  # The compiler is a cross compiler
  quiet_run make all-gcc -j${CPU_COUNT}
  quiet_run make install-gcc -j${CPU_COUNT}
  cp $RECIPE_DIR/libgomp.spec $PREFIX/lib/gcc/${TARGET}/${gfortran_version}/libgomp.spec
  sed "s#@CONDA_PREFIX@#$PREFIX#g" $RECIPE_DIR/libgfortran.spec > $PREFIX/lib/gcc/${TARGET}/${gfortran_version}/libgfortran.spec
fi

stop_spinner

ls -al $PREFIX/lib

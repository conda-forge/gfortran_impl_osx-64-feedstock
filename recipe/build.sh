#!/bin/bash

set -ex

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

set -x

# Undo conda-build madness
export host_platform=$target_platform
export target_platform=$cross_target_platform
# set the TARGET variable. HOST and BUILD are already set by the compilers/conda-build
export TARGET=${macos_machine}
# clang emits a ton of warnings
export NO_WARN_CFLAGS="-Wno-array-bounds -Wno-unknown-warning-option -Wno-deprecated -Wno-mismatched-tags -Wno-unused-command-line-argument -Wno-ignored-attributes"

export enable_darwin_at_rpath=yes

# conda binary prefix rewriting fails if the variables are not volatile
sed -i.bak 's/static const char \*const standard_/static const char * volatile standard_/g' gcc/gcc.c*

if [[ "$host_platform" != "$build_platform" ]]; then
    # We need to compile GFORTRAN_FOR_TARGET and GCC_FOR_TARGET
    mkdir -p build_host
    pushd build_host
    CC=$CC_FOR_BUILD CXX=$CXX_FOR_BUILD AR="$($CC_FOR_BUILD -print-prog-name=ar)" LD="$($CC_FOR_BUILD -print-prog-name=ld)" \
         RANLIB="$($CC_FOR_BUILD -print-prog-name=ranlib)" NM="$($CC_FOR_BUILD -print-prog-name=nm)"  \
         CFLAGS="$NO_WARN_CFLAGS" CXXFLAGS="$NO_WARN_CFLAGS" CPPFLAGS="$NO_WARN_CFLAGS" \
         LDFLAGS="-L$BUILD_PREFIX/lib -Wl,-rpath,$BUILD_PREFIX/lib" ../configure \
       --prefix=${BUILD_PREFIX} \
       --build=${BUILD} \
       --host=${BUILD} \
       --target=${TARGET} \
       --with-libiconv-prefix=${BUILD_PREFIX} \
       --enable-languages="c,fortran" \
       --disable-multilib \
       --enable-checking=release \
       --disable-bootstrap \
       --disable-libssp \
       --with-gmp=${BUILD_PREFIX} \
       --with-mpfr=${BUILD_PREFIX} \
       --with-mpc=${BUILD_PREFIX} \
       --with-isl=${BUILD_PREFIX} \
       --with-sysroot=$CONDA_BUILD_SYSROOT

    echo "Building a compiler that runs on ${BUILD} and targets ${TARGET}"
    make all-gcc -j${CPU_COUNT}
    make install-gcc -j${CPU_COUNT}
    popd
    # For the target compiler to work, it need some tools
    ln -sf ${BUILD_PREFIX}/bin/${TARGET}-ar       ${BUILD_PREFIX}/lib/gcc/${TARGET}/${gfortran_version}/ar
    ln -sf ${BUILD_PREFIX}/bin/${TARGET}-as       ${BUILD_PREFIX}/lib/gcc/${TARGET}/${gfortran_version}/as
    ln -sf ${BUILD_PREFIX}/bin/${TARGET}-nm       ${BUILD_PREFIX}/lib/gcc/${TARGET}/${gfortran_version}/nm
    ln -sf ${BUILD_PREFIX}/bin/${TARGET}-ranlib   ${BUILD_PREFIX}/lib/gcc/${TARGET}/${gfortran_version}/ranlib
    ln -sf ${BUILD_PREFIX}/bin/${TARGET}-strip    ${BUILD_PREFIX}/lib/gcc/${TARGET}/${gfortran_version}/strip
    ln -sf ${BUILD_PREFIX}/bin/${TARGET}-ld       ${BUILD_PREFIX}/lib/gcc/${TARGET}/${gfortran_version}/ld
fi

mkdir -p build_conda
cd build_conda

if [[ "$target_platform" == osx* ]]; then
    if [[ "$target_platform" == "$host_platform" ]]; then
        export LDFLAGS_FOR_TARGET="$LDFLAGS_FOR_TARGET $LDFLAGS"
        export CFLAGS_FOR_TARGET="$CFLAGS_FOR_TARGET $CFLAGS"
        export CXXFLAGS_FOR_TARGET="$CXXFLAGS_FOR_TARGET $CXXFLAGS"
        export CPPFLAGS_FOR_TARGET="$CPPFLAGS_FOR_TARGET $CPPFLAGS"
    fi
    # $PWD/$TARGET/libgcc is needed because the previous bootstrap compiler we built needs libemutls_w.a
    export LDFLAGS_FOR_TARGET="$LDFLAGS_FOR_TARGET -L$PWD/$TARGET/libgcc -L$CONDA_BUILD_SYSROOT/usr/lib"
    export CFLAGS_FOR_TARGET="$CFLAGS_FOR_TARGET $LDFLAGS_FOR_TARGET"
    export CXXFLAGS_FOR_TARGET="$CXXFLAGS_FOR_TARGET $LDFLAGS_FOR_TARGET"
    export CPPFLAGS_FOR_TARGET="$CPPFLAGS_FOR_TARGET $LDFLAGS_FOR_TARGET"
fi

if [[ "$host_platform" == osx* ]]; then
    export LDFLAGS="$LDFLAGS -L$CONDA_BUILD_SYSROOT/usr/lib"
    export CFLAGS="$CFLAGS $NO_WARN_CFLAGS"
    export CXXFLAGS="$CXXFLAGS $NO_WARN_CFLAGS"
    export CPPFLAGS="$CPPFLAGS $NO_WARN_CFLAGS"
fi

../configure \
    --prefix=${PREFIX} \
    --build=${BUILD} \
    --host=${HOST} \
    --target=${TARGET} \
    --with-libiconv-prefix=${PREFIX} \
    --enable-languages=fortran \
    --disable-multilib \
    --enable-checking=release \
    --disable-bootstrap \
    --disable-libssp \
    --with-gmp=${PREFIX} \
    --with-mpfr=${PREFIX} \
    --with-mpc=${PREFIX} \
    --with-isl=${PREFIX} \
    --enable-darwin-at-rpath \
    --with-sysroot=$CONDA_BUILD_SYSROOT

echo "Building a compiler that runs on ${HOST} and targets ${TARGET}"
if [[ "$host_platform" == "$target_platform" ]]; then
  # Build if the compiler is a cross-native/native compiler

  # Make sure that the libgomp configure script knows that the fortran
  # compiler used is GNU. Otherwise the standard fortran modules for
  # libgomp are not installed. TODO: figure out why the configure script thinks it isn't.
  if [[ "$host_platform" != "$build_platform" ]]; then
    export ac_cv_fc_compiler_gnu=${TARGET}-gfortran
    export FC=${TARGET}-gfortran
    export ac_cv_prog_FC=$FC
    $FC --version
    sed -i.bak "s/USE_FORTRAN_FALSE=.*/USE_FORTRAN_FALSE='#'/g" $SRC_DIR/libgomp/configure
    sed -i.bak "s/USE_FORTRAN_TRUE=.*/USE_FORTRAN_TRUE=/g" $SRC_DIR/libgomp/configure
  fi

  make -j"${CPU_COUNT}"
  make install-strip -j${CPU_COUNT}
  rm $PREFIX/lib/libgomp.dylib
  rm $PREFIX/lib/libgomp.1.dylib
  ln -s $PREFIX/lib/libomp.dylib $PREFIX/lib/libgomp.dylib
  ln -s $PREFIX/lib/libomp.dylib $PREFIX/lib/libgomp.1.dylib

  rm ${PREFIX}/lib/libgfortran.spec
  sed "s#@CONDA_PREFIX@#$PREFIX#g" $RECIPE_DIR/libgfortran.spec > libgfortran.spec
  if [[ "$target_platform" == "osx-arm64" && "$gfortran_version" == "11.3.0" ]]; then
    sed -i.bak "s#-lquadmath##g" libgfortran.spec
  fi
  mv libgfortran.spec ${PREFIX}/lib/libgfortran.spec

  for file in libgfortran.spec libgomp.spec; do
    mv $PREFIX/lib/$file $PREFIX/lib/gcc/${TARGET}/${gfortran_version}/$file
    ln -s $PREFIX/lib/gcc/${TARGET}/${gfortran_version}/$file $PREFIX/lib/$file
  done
else
  # The compiler is a cross compiler. Only make the compiler. No target libraries
  make all-gcc -j${CPU_COUNT}
  make install-gcc -j${CPU_COUNT}
fi

stop_spinner

ls -al $PREFIX/lib

mv ${PREFIX}/libexec/gcc/${TARGET}/${gfortran_version}/cc1 ${PREFIX}/libexec/gcc/${TARGET}/${gfortran_version}/cc1.bin
sed "s#@PATH@#${PREFIX}/libexec/gcc/${TARGET}/${gfortran_version}#g" ${RECIPE_DIR}/cc1 > ${PREFIX}/libexec/gcc/${TARGET}/${gfortran_version}/cc1
chmod +x ${PREFIX}/libexec/gcc/${TARGET}/${gfortran_version}/cc1

if [[ ! -f $PREFIX/bin/${TARGET}-gfortran ]]; then
  mv ${PREFIX}/bin/gfortran ${PREFIX}/bin/${TARGET}-gfortran
  # -ln -sf ${PREFIX}/bin/${TARGET}-gfortran ${PREFIX}/bin/gfortran
fi

ln -s ${PREFIX}/bin/${TARGET}-ar       $PREFIX/lib/gcc/${TARGET}/${gfortran_version}/ar
ln -s ${PREFIX}/bin/${TARGET}-as       $PREFIX/lib/gcc/${TARGET}/${gfortran_version}/as
ln -s ${PREFIX}/bin/clang              $PREFIX/lib/gcc/${TARGET}/${gfortran_version}/clang
ln -s ${PREFIX}/bin/${TARGET}-nm       $PREFIX/lib/gcc/${TARGET}/${gfortran_version}/nm
ln -s ${PREFIX}/bin/${TARGET}-ranlib   $PREFIX/lib/gcc/${TARGET}/${gfortran_version}/ranlib
ln -s ${PREFIX}/bin/${TARGET}-strip    $PREFIX/lib/gcc/${TARGET}/${gfortran_version}/strip
ln -s ${PREFIX}/bin/${TARGET}-ld       $PREFIX/lib/gcc/${TARGET}/${gfortran_version}/ld

# remove this symlink so that conda-build doesn't follow symlinks
rm -f ${PREFIX}/bin/clang

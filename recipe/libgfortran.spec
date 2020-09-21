#
# This spec file is read by gfortran when linking.
# It is used to specify the libraries we need to link in, in the right
# order.
#

%rename lib liborig
*lib:  -lquadmath -lm %(libgcc) %(liborig) -rpath @CONDA_PREFIX@/lib

*libgcc:
%{static-libgcc|static:                                                          %{!m32:%:version-compare(>= 10.6 mmacosx-version-min= -lSystem)}                  -lgcc_eh -lgcc;                                                             shared-libgcc|fexceptions|fgnu-runtime:                                          %:version-compare(!> 10.5 mmacosx-version-min= -lSystem)                  %:version-compare(>< 10.5 10.6 mmacosx-version-min= -lSystem)          %:version-compare(!> 10.5 mmacosx-version-min= -lSystem)             %:version-compare(>= 10.5 mmacosx-version-min= -lSystem)                  -lgcc ;                                     :%:version-compare(>< 10.3.9 10.5 mmacosx-version-min= -lSystem)        %:version-compare(>< 10.5 10.6 mmacosx-version-min= -lSystem)          %:version-compare(!> 10.5 mmacosx-version-min= -lSystem)           %:version-compare(>= 10.5 mmacosx-version-min= -lSystem)                  -lgcc }


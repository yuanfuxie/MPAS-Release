.SUFFIXES: .F .o

OBJS = mpas_ocn_mpas_core.o \
       mpas_ocn_time_integration.o \
       mpas_ocn_time_integration_rk4.o \
       mpas_ocn_time_integration_split.o

all: core_ocean

core_ocean: $(OBJS) 

mpas_ocn_time_integration.o: mpas_ocn_time_integration_rk4.o mpas_ocn_time_integration_split.o

mpas_ocn_time_integration_rk4.o: 

mpas_ocn_time_integration_split.o: 

mpas_ocn_mpas_core.o: mpas_ocn_time_integration.o \
                      mpas_ocn_time_integration_rk4.o \
                      mpas_ocn_time_integration_split.o

clean:
	$(RM) *.o *.mod *.f90 libdycore.a

.F.o:
	$(RM) $@ $*.mod
ifeq "$(GEN_F90)" "true"
	$(CPP) $(CPPFLAGS) $(CPPINCLUDES) $< > $*.f90
	$(FC) $(FFLAGS) -c $*.f90 $(FCINCLUDES)
else
	$(FC) $(CPPFLAGS) $(FFLAGS) -c $*.F $(CPPINCLUDES) $(FCINCLUDES)
endif

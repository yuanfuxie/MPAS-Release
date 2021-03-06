! Copyright (c) 2013,  Los Alamos National Security, LLC (LANS)
! and the University Corporation for Atmospheric Research (UCAR).
!
! Unless noted otherwise source code is licensed under the BSD license.
! Additional copyright and license information can be found in the LICENSE file
! distributed with this code, or at http://mpas-dev.github.com/license.html
!
module mpas_core


   contains


   subroutine mpas_core_init(domain, stream_manager, startTimeStamp)
   
      use mpas_grid_types
      use mpas_stream_manager
      use mpas_io_streams, only : MPAS_STREAM_NEAREST
      use mpas_configure
      use init_atm_cases
   
      implicit none
   
      type (domain_type), intent(inout) :: domain
      type (MPAS_streamManager_type), intent(inout) :: stream_manager
      character(len=*), intent(out) :: startTimeStamp

      type (block_type), pointer :: block
      type (mpas_pool_type), pointer :: state, mesh 
      character (len=StrKIND), pointer :: xtime
      character (len=StrKIND), pointer :: config_start_time
      real (kind=RKIND), pointer :: sphere_radius
      integer :: ierr


      block => domain % blocklist
      do while (associated(block))
         call mpas_pool_get_subpool(block % structs, 'state', state)
         call mpas_pool_get_subpool(block % structs, 'mesh', mesh)
         call mpas_pool_get_array(state, 'xtime', xtime)
         call mpas_pool_get_config(mesh, 'sphere_radius', sphere_radius)
         call mpas_pool_get_config(block % configs, 'config_start_time', config_start_time)

         startTimeStamp = config_start_time
         xtime = config_start_time
         domain % sphere_radius = a      ! Appears in output files
         sphere_radius = a               ! Used in setting up test cases

         block => block % next
      end do 

      call MPAS_stream_mgr_add_att(stream_manager, 'sphere_radius', domain % sphere_radius, streamID='output', ierr=ierr)
      call MPAS_stream_mgr_add_att(stream_manager, 'sphere_radius', domain % sphere_radius, streamID='surface', ierr=ierr)

      !
      ! We don't actually expect the time in the (most likely 'static') file to
      !    match the time in the namelist, so just read whatever time we find in
      !    the input file.
      !
      call MPAS_stream_mgr_read(stream_manager, whence=MPAS_STREAM_NEAREST, ierr=ierr)
      call MPAS_stream_mgr_reset_alarms(stream_manager, direction=MPAS_STREAM_INPUT, ierr=ierr)

   end subroutine mpas_core_init
   
   
   subroutine mpas_core_run(domain, stream_manager)
   
      use mpas_grid_types
      use mpas_stream_manager
      use mpas_timer
      use init_atm_cases
   
      implicit none
   
      type (domain_type), intent(inout) :: domain
      type (MPAS_streamManager_type), intent(inout) :: stream_manager
   
      integer :: ierr
      
      call init_atm_setup_case(domain, stream_manager)
   
   !
   ! Note: The following initialization calls have been moved to the mpas_init_atm_case_*() subroutines,
   !       since values computed by these routines are needed to produce initial fields
   !
   !   call atm_initialize_advection_rk(mesh)
   !   call atm_initialize_deformation_weights(mesh)
  
      call mpas_stream_mgr_write(stream_manager, streamID='output', ierr=ierr)
      call mpas_stream_mgr_reset_alarms(stream_manager, direction=MPAS_STREAM_OUTPUT, ierr=ierr)
   
   end subroutine mpas_core_run
   
   
   subroutine mpas_core_finalize(domain, stream_manager)
   
      use mpas_grid_types
      use mpas_stream_manager
   
      implicit none
   
      type (domain_type), intent(inout) :: domain 
      type (MPAS_streamManager_type), intent(inout) :: stream_manager
   
   end subroutine mpas_core_finalize


   subroutine mpas_core_setup_packages(configs, packages, ierr)

      use mpas_packages
      use mpas_grid_types

      implicit none

      type (mpas_pool_type), intent(inout) :: configs
      type (mpas_pool_type), intent(inout) :: packages
      integer, intent(out) :: ierr

      logical, pointer :: initial_conds, sfc_update
      integer, pointer :: config_init_case

      ierr = 0

      nullify(config_init_case)
      call mpas_pool_get_config(configs, 'config_init_case', config_init_case)

      nullify(initial_conds)
      call mpas_pool_get_package(packages, 'initial_condsActive', initial_conds)

      nullify(sfc_update)
      call mpas_pool_get_package(packages, 'sfc_updateActive', sfc_update)

      if (.not. associated(config_init_case) .or. &
          .not. associated(initial_conds) .or. &
          .not. associated(sfc_update)) then
         write(stderrUnit,*) '********************************************************************************'
         write(stderrUnit,*) '* Error while setting up packages for init_atmosphere core.'
         write(stderrUnit,*) '********************************************************************************'
         ierr = 1
         return
      end if

      if (config_init_case == 8) then
         initial_conds = .false.
         sfc_update = .true.
      else
         initial_conds = .true.
         sfc_update = .false.
      end if

   end subroutine mpas_core_setup_packages



   !***********************************************************************
   !
   !  routine mpas_core_setup_clock
   !
   !> \brief   Pacakge setup routine
   !> \author  Michael Duda
   !> \date    6 August 2014
   !> \details 
   !>  The purpose of this routine is to allow the core to set up a simulation
   !>  clock that will be used by the I/O subsystem for timing reads and writes
   !>  of I/O streams.
   !>  This routine is called from the superstructure after the framework 
   !>  has been initialized but before any fields have been allocated and 
   !>  initial fields have been read from input files. However, all namelist
   !>  options are available.
   !
   !-----------------------------------------------------------------------
   subroutine mpas_core_setup_clock(core_clock, configs, ierr)

      use mpas_timekeeping, only : MPAS_Clock_type, MPAS_Time_type, MPAS_Timeinterval_type, &
                                   mpas_set_time, mpas_set_timeInterval, mpas_create_clock
      use mpas_grid_types, only : mpas_pool_type, mpas_pool_get_config
      use mpas_kind_types, only : StrKIND

      implicit none

      type (MPAS_Clock_type), intent(inout) :: core_clock
      type (mpas_pool_type), intent(inout) :: configs
      integer, intent(out) :: ierr

      character(len=StrKIND), pointer :: config_start_time, config_stop_time
      integer, pointer :: config_fg_interval

      type (MPAS_Time_type)         :: start_time, stop_time
      type (MPAS_TimeInterval_type) :: dt


      ierr = 0

      call mpas_pool_get_config(configs, 'config_start_time', config_start_time)
      call mpas_pool_get_config(configs, 'config_stop_time', config_stop_time)
      call mpas_pool_get_config(configs, 'config_fg_interval', config_fg_interval)

      call mpas_set_time(start_time, dateTimeString=trim(config_start_time))
      call mpas_set_time(stop_time, dateTimeString=trim(config_stop_time))
      call mpas_set_timeInterval(dt, S=config_fg_interval)
      call mpas_create_clock(core_clock, start_time, dt, stopTime=stop_time)

   end subroutine mpas_core_setup_clock


   !***********************************************************************
   !
   !  routine mpas_core_get_mesh_stream
   !
   !> \brief   Returns the name of the stream containing mesh information
   !> \author  Michael Duda
   !> \date    8 August 2014
   !> \details 
   !>  This routine returns the name of the I/O stream containing dimensions,
   !>  attributes, and mesh fields needed by the framework bootstrapping 
   !>  routine. At the time this routine is called, only namelist options 
   !>  are available.
   !
   !-----------------------------------------------------------------------
   subroutine mpas_core_get_mesh_stream(configs, stream, ierr)

      use mpas_grid_types, only : mpas_pool_type, mpas_pool_get_config

      implicit none

      type (mpas_pool_type), intent(in) :: configs
      character(len=*), intent(out) :: stream
      integer, intent(out) :: ierr


      ierr = 0

      write(stream,'(a)') 'input'

   end subroutine mpas_core_get_mesh_stream
   
end module mpas_core

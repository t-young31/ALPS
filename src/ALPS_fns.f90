!Copyright (c) 2023, Kristopher G. Klein and Daniel Verscharen
!All rights reserved.
!
!This source code is licensed under the BSD-style license found in the
!LICENSE file in the root directory of this source tree.
!
!===============================================================================
!I                                                                             I
!I                              A  L  P  S                                     I
!I                     Arbitrary Linear Plasma Solver                          I
!I                                                                             I
!I                              Version 1.0                                    I
!I                                                                             I
!I  Kristopher Klein   (kgklein@arizona.edu)                                   I
!I  Daniel Verscharen  (d.verscharen@ucl.ac.uk)                                I
!I                                                                             I
!===============================================================================

module alps_fns
!! This module contains the key numerical functions of ALPS.
  implicit none

  private :: int_T, int_T_res, integrate
  private :: integrate_res, landau_integrate, resU

  public :: derivative_f0, disp, determine_bessel_array
  public :: determine_nmax, split_processes, secant, map_search

  public :: om_scan, om_double_scan

contains


subroutine derivative_f0
  !! This subroutine calculates the perpendicular and parallel derivatives of the background velocity distribution function f0.
    use alps_var, only : f0, pp, df0, nperp, npar, nspec, arrayName, ns, qs, ms, bMpdrifts
    use alps_var, only : f0_rel, gamma_rel, pparbar_rel,nspec_rel,df0_rel,ngamma,npparbar
    use alps_var, only : current_int
    use alps_var, only : writeOut, pi, relativistic, usebM
    use alps_io,  only : get_unused_unit
    use alps_fns_rel, only : derivative_f0_rel
    implicit none


    integer :: iperp
    !! Index for loop over perpendicular momentum.

    integer :: ipar
    !! Index for loop over parallel momentum.

    integer :: is
    !! Index of particle species.

    integer :: is_rel
	  !! Index for relativistic species (if any).

    integer :: unit_f
    !! Unit for file i/o.

    logical :: OutDF
    !! Check whether output shall be written to file.

    logical :: any_relativistic
    !! Check whether any relativistic calculations are necessary.

    character (50) :: fmt
    !! Output format for file i/o.

    character (100) :: writename
    !! File name for file i/o.

    double precision :: integrate
    !! Integral of the distribution function.

    double precision, dimension(0:nspec) :: charge
    !! Charge density.
    !! Zeroth index is sum over all species

    double precision :: dpperp
    !! Inifinitesimal step in perpendicular momentum.

    double precision :: dppar
    !! Inifinitesimal step in parallel momentum.

    allocate(current_int(0:nspec)); current_int=0.d0

    if (writeOut) then
       write(*,'(a)')&
            '-=-=-=-=-=-=-=-=-'
       write(*,'(a)')&
            'Calculating df0/dpperp, df0/ppar if necessary...'
    endif


    do is = 1, nspec

      if (usebM(is)) then
                write (*,'(a,i2)') ' Bi-Maxwellian calcuation: no derivatives necessary for species ',is
                df0(is,:,:,:)=0.d0
       else

       do iperp = 1, nperp-1
          do ipar = 1, npar-1
             !index 1-> vperp derivative
             df0(is,iperp,ipar,1) = &
                  (f0(is,iperp+1,ipar) - f0(is,iperp-1,ipar))/&
                  (pp(is,iperp+1,ipar,1) - pp(is,iperp-1,ipar,1))

             !index 2-> vpar derivative
             df0(is,iperp,ipar,2) = &
                  (f0(is,iperp,ipar+1) - f0(is,iperp,ipar-1))/&
                  (pp(is,iperp,ipar+1,2) - pp(is,iperp,ipar-1,2))
          enddo
       enddo
    endif

    enddo
    write(*,*)'Derivatives calculated'


    !Output df/dv to file:
    OutDF = .false.
    if (OutDF) then

       if (writeOut) &
            write(*,'(a)') 'Outputing df0/dpperp, df0/dppar'
       write(fmt,'(a)') '(2es14.4,2es14.4)'
       do is = 1, nspec


         if (.not.usebM(is)) then
          dpperp = pp(is, 2, 2, 1) - pp(is, 1, 2, 1)
          dppar  = abs(pp(is, 2, 2, 2) - pp(is, 2, 1, 2))

          write(writeName,'(3a,i0,a)')&
               'distribution/',trim(arrayName),'_dfdv.',is,'.array'


          call get_unused_unit(unit_f)
          open(unit=unit_f,file=trim(writeName),status='replace')

          do iperp = 1, nperp-1
             do ipar = 1, npar-1

                   write(unit_f,fmt) pp(is,iperp,ipar,1),pp(is,iperp,ipar,2),&
                    df0(is, iperp,ipar,1),df0(is, iperp,ipar,2)
             enddo
             write(unit_f,*)
          enddo
          close(unit_f)
       endif
       enddo
    endif
    !End output

    charge=0.d0
    current_int=0.d0

    do is = 1, nspec
       if (usebM(is)) then
          integrate = 1.d0
          charge(is)=ns(is)*qs(is)
          current_int(is)=ns(is)*qs(is)*&
               bMpdrifts(is)/ms(is)
       else
       integrate = 0.d0
       dpperp = pp(is, 2, 2, 1) - pp(is, 1, 2, 1)
       dppar  = abs(pp(is, 2, 2, 2) - pp(is, 2, 1, 2))

       do iperp = 0, nperp
          do ipar = 0, npar
             integrate = integrate + &
                  pp(is,iperp,ipar,1) * f0(is,iperp,ipar) * &
                  2.d0 * pi * dpperp * dppar

             charge(is) = charge(is) + &
                  ns(is)*qs(is)*pp(is,iperp,ipar,1) * f0(is,iperp,ipar) * &
                  2.d0 * pi * dpperp * dppar

             current_int(is) = current_int(is) + &
                  (ns(is)*qs(is)/ms(is))*pp(is,iperp,ipar,1)*pp(is,iperp,ipar,2)*&
                  f0(is,iperp,ipar) * &
                  2.d0 * pi * dpperp * dppar

          enddo
       enddo
    endif
       write(*,'(a)')&
            '-=-=-=-='
       write(*,'(a,i3,a)')&
            'Species ',is,':'
       write(*,'(a, 2es14.4)') &
            ' Integration:              ', integrate
       write(*,'(a, 2es14.4)') &
            ' Charge density:           ', charge(is)
       write(*,'(a, 2es14.4)') &
            ' Parallel current density: ', current_int(is)
    enddo
    write(*,'(a)')         '-=-=-=-='
    write(*,'(a, es14.4)') ' Total charge density:           ', sum(charge(1:nspec))
    write(*,'(a, es14.4)') ' Total parallel current density: ', sum(current_int(1:nspec))
    write(*,'(a)')         '-=-=-=-=-=-=-=-='


    if (writeOut) write(*,'(a)') '-=-=-=-=-=-=-=-=-'

	if (writeOut) write (*,'(a)') 'Determine if relativistic calculation necessary'
	any_relativistic = .FALSE.

	is_rel = 0
	do is = 1, nspec
		if (relativistic(is)) then
			any_relativistic=.TRUE.
			is_rel=is_rel+1
			write (*,'(a,i3,a,i3)') 'Species',is, ' requires relativistic calculation. is_rel=',is_rel
		endif
	enddo


	if (any_relativistic) then

		if(writeOut) write (*,'(a,i4)') "ngamma   = ",ngamma
		if(writeOut) write (*,'(a,i4)') "npparbar = ",npparbar

		 nspec_rel=is_rel

		 ! Allocate the relativistic fields (only on proc0 for now):
		 allocate(gamma_rel(nspec_rel,0:ngamma,0:npparbar))
		 allocate(pparbar_rel(nspec_rel,0:ngamma,0:npparbar))
		 allocate(f0_rel(nspec_rel,0:ngamma,0:npparbar))
		 allocate(df0_rel(nspec_rel,0:ngamma,0:npparbar,2))

		 is_rel=0
		 do is=1,nspec
		 	if(relativistic(is)) then
		 		is_rel=is_rel+1
		 		call derivative_f0_rel(is,is_rel)
		 	endif
		 enddo
	else
		 nspec_rel=0
		 write (*,'(a)') 'No relativistic calculation necessary.'
		 if (writeOut) write(*,'(a)') '-=-=-=-=-=-=-=-=-'
	endif

end subroutine derivative_f0



 double complex function disp(om)
 !! This function returns the determinant of the dispersion tensor for a given frequency om.
    use alps_var, only : nlim, proc0, nspec, ierror, sproc, relativistic
    use alps_var, only : wave, kperp, kpar, ns, qs, vA, chi0, usebM
    use alps_nhds, only: calc_chi
    use alps_fns_rel, only : int_ee_rel
    use mpi
    implicit none


    double complex, intent(in) :: om
    !! Complex wave frequency \(\omega\).

    double complex :: chi_NHDS(3,3)
    !! Susceptibility tensor \(\chi\) as calculated from NHDS in [[alps_nhds(module)]].

    double complex, dimension(1:nspec,1:3,1:3) :: schi
    !! Susceptibility tensor \(\chi\) of individual process.

    double complex, dimension(1:nspec,1:3,1:3) :: chi
    !! Susceptibility tensor \(\chi\) after summing over processes.

    double complex, dimension(1:3,1:3) :: eps
    !! Dielectric tensor \(\epsilon\).

    double complex :: enx2
    !! Index of refraction \(n_x^2\).

    double complex :: enz2
    !! Index of refraction \(n_z^2\).

    double complex :: enxnz
    !! Index of refraction \(n_xn_z\).

    integer :: is
    !! Index for species.

    integer :: nn
    !! Index for order of Bessel function.

    double complex, dimension(1:nspec) :: norm
    !! Normalisation for dispersion tensors.

    logical :: found_res_plus
    !! Check whether a resonance is found at positive n.

    logical :: found_res_minus
    !! Check whether a resonance is found at negative n.


    chi=cmplx(0.d0,0.d0,kind(1.d0))
    if (proc0) chi0=cmplx(0.d0,0.d0,kind(1.d0))
    schi=cmplx(0.d0,0.d0,kind(1.d0))

    if (proc0)  then

       !Indices of refraction for the dispersion relation in NHDS normalisation:
       enx2=kperp**2
       enz2=kpar**2
       enxnz=kperp*kpar

    else
        ! Integrate:
        ! c.f. Stix Equation 10.48; pg 255

        ! Split into NHDS or ALPS routines:
        ! Only run the NHDS routine if useBM is on for the species
        !   and if process is handling n=0 according to split_processes:
        if (usebM(sproc).and.(nlim(2).GE.0).and.(nlim(1).EQ.0)) then

          ! This is the case to use NHDS for the calculation of chi:
          call calc_chi(chi_NHDS,sproc,kpar,kperp,om)

          ! Account for norm below, which is already included in NHDS:
          schi(sproc,1,1)=chi_NHDS(1,1)/(ns(sproc) * qs(sproc))
          schi(sproc,2,2)=chi_NHDS(2,2)/(ns(sproc) * qs(sproc))
          schi(sproc,3,3)=chi_NHDS(3,3)/(ns(sproc) * qs(sproc))
          schi(sproc,1,2)=chi_NHDS(1,2)/(ns(sproc) * qs(sproc))
          schi(sproc,1,3)=chi_NHDS(1,3)/(ns(sproc) * qs(sproc))
          schi(sproc,2,3)=chi_NHDS(2,3)/(ns(sproc) * qs(sproc))

       else

       do nn = nlim(1),nlim(2)

          call determine_resonances(om,nn,found_res_plus,found_res_minus)

          ! CHIij(nn) function calls:

          if (nn == 0) then

             !xx term is zero
             !xy term is zero
             !xz term is zero

             !yy term:
             schi(sproc,2,2) = schi(sproc,2,2) + &
                  full_integrate(om,nn,2,found_res_plus)

             !zz term:
             schi(sproc,3,3) = schi(sproc,3,3) + &
                  full_integrate(om,nn,3,found_res_plus)

             !yz term:
             schi(sproc,2,3) = schi(sproc,2,3) + &
                  full_integrate(om,nn,6,found_res_plus)

          else

             !xx term:
             schi(sproc,1,1) = schi(sproc,1,1) + &
                  full_integrate(om,nn,1,found_res_plus) + &
                  full_integrate(om,-nn,1,found_res_minus)

             !yy term:
             schi(sproc,2,2) = schi(sproc,2,2) + &
                  full_integrate(om,nn,2,found_res_plus) + &
                  full_integrate(om,-nn,2,found_res_minus)

             !zz term:
             schi(sproc,3,3) = schi(sproc,3,3) + &
                  full_integrate(om,nn,3,found_res_plus) + &
                  full_integrate(om,-nn,3,found_res_minus)

             !xy term:
             schi(sproc,1,2) = schi(sproc,1,2) + &
                  full_integrate(om,nn,4,found_res_plus) + &
                  full_integrate(om,-nn,4,found_res_minus)

             !xz term:
             schi(sproc,1,3) = schi(sproc,1,3) + &
                  full_integrate(om,nn,5,found_res_plus) + &
                  full_integrate(om,-nn,5,found_res_minus)

             !yz term:
             schi(sproc,2,3) = schi(sproc,2,3) + &
                  full_integrate(om,nn,6,found_res_plus) + &
                  full_integrate(om,-nn,6,found_res_minus)

          endif
       enddo

       ! Add in ee term:
       if (nlim(1)==0) then
	     if(relativistic(sproc)) then
	     	    schi(sproc,3,3)=schi(sproc,3,3) + int_ee_rel(om)
	     else
	     		schi(sproc,3,3)=schi(sproc,3,3) + int_ee(om)
	     endif
       endif

     endif

       norm(sproc) = ns(sproc) * qs(sproc)

       schi(sproc,1,1) = schi(sproc,1,1) * norm(sproc)
       schi(sproc,2,2) = schi(sproc,2,2) * norm(sproc)
       schi(sproc,3,3) = schi(sproc,3,3) * norm(sproc)
       schi(sproc,1,2) = schi(sproc,1,2) * norm(sproc)
       schi(sproc,1,3) = schi(sproc,1,3) * norm(sproc)
       schi(sproc,2,3) = schi(sproc,2,3) * norm(sproc)

    endif

    ! Return the schi to proc0:
    call MPI_REDUCE (schi, chi, size(chi),&
        MPI_DOUBLE_COMPLEX, MPI_SUM, 0, MPI_COMM_WORLD, ierror)


    if (proc0) then
       !Calculate dielectric tensor epsilon:

       !The global variable 'chi0' is used
       !for heating & eigenfunction calculation.

       chi0=chi/(om*om*vA*vA)

       chi0(:,2,1)=-chi0(:,1,2)
       chi0(:,3,1)=-chi0(:,1,3)
       chi0(:,3,2)=-chi0(:,2,3)

    	wave=cmplx(0.d0,0.d0,kind(1.d0))
      eps=cmplx(0.d0,0.d0,kind(1.d0))


       ! Sum over species:
       do is = 1, nspec
          eps(1,1) = eps(1,1) + chi(is,1,1)
          eps(2,2) = eps(2,2) + chi(is,2,2)
          eps(3,3) = eps(3,3) + chi(is,3,3)

          eps(1,2) = eps(1,2) + chi(is,1,2)
          eps(1,3) = eps(1,3) + chi(is,1,3)
          eps(2,3) = eps(2,3) + chi(is,2,3)

       enddo

       ! Exploit symmetry of epsilon tensor:
       eps(2,1) = -eps(1,2)
       eps(3,1) =  eps(1,3)
       eps(3,2) = -eps(2,3)


       ! Add the unit tensor (in our normalisation):
       eps(1,1) = eps(1,1) + (om*vA)**2
       eps(2,2) = eps(2,2) + (om*vA)**2
       eps(3,3) = eps(3,3) + (om*vA)**2


       !Calculate dispersion tensor:
       !wave = ( eps_xx - nz^2  eps_xy              eps_xz + nxnz )
       !       ( eps_yx         eps_yy -nz^2 -nx^2  eps_yz        )
       !       ( eps_zx + nxnz  eps_zy              eps_zz - nx^2 )
       wave(1,1) = eps(1,1) - enz2
       wave(2,2) = eps(2,2) - enz2 - enx2
       wave(3,3) = eps(3,3) - enx2
       wave(1,3) = eps(1,3) + enxnz

       wave(1,2) = eps(1,2)
       wave(2,3) = eps(2,3)

       ! Exploit symmetry of dispersion tensor:
       wave(2,1) = -wave(1,2)
       wave(3,1) =  wave(1,3)
       wave(3,2) = -wave(2,3)
       !-=-=-=-=-=-

       !Calculate determinant of the dispersion tensor:
       !The below relies on the symmetries of the T_n tensor:
       !Again, c.f. Stix Equation 10.48; pg 255
       !---------------------------------------------------------------------
       disp = wave(1,1)*( wave(2,2)*wave(3,3) + wave(2,3)**2 ) + &
            2.d0*wave(1,2)*wave(2,3)*wave(1,3) - wave(1,3)**2*wave(2,2) + &
            wave(1,2)**2*wave(3,3)

    endif

    call mpi_bcast(disp, 1, MPI_DOUBLE_COMPLEX, 0, MPI_COMM_WORLD, ierror)

    !Make sure all processors have completed calculation to avoid
    !cross contamination with map and root searches
    call mpi_barrier(mpi_comm_world,ierror)

    return

end function disp




subroutine determine_resonances(om,nn,found_res_plus,found_res_minus)
  !! This subroutine determines whether any kinetic resonances are located in the integration domain.
	use alps_var, only : npar, pp, vA, ms, qs, sproc, kpar, nperp
	use alps_var, only : positions_principal, relativistic
	use alps_io, only  : alps_error
	implicit none

  double complex, intent(in) :: om
  !! Complex wave frequency \(\omega\).

	integer, intent(in) :: nn
  !! Order of Bessel function.

  logical, intent(out) :: found_res_plus
  !! Check whether a resonance is found at positive n.

  logical, intent(out) :: found_res_minus
  !! Check whether a resonance is found at negative n.

  integer :: iperp
  !! Index to loop over perpendicular momentum.

  integer :: ipar
  !! Index to loop over parallel momentum.

	double precision :: dppar
  !! Inifinitesimal step in parallel momentum.

  double precision :: gamma
  !! Lorentz factor \(\Gamma\).

	double complex :: p_res
  !! Complex resonance momentum.


	 dppar = pp(sproc,2,2,2)-pp(sproc,2,1,2)
	 found_res_plus = .FALSE.
	 found_res_minus = .FALSE.

	if (relativistic(sproc)) then

  ! The following checks for resonances in (pperp,ppar)-space rather than in (Gamma,pparbar)-space:
  do iperp=0,nperp
    do ipar=0,npar-1

     gamma = sqrt((pp(sproc, iperp, ipar, 1)**2 + &
        pp(sproc, iperp, ipar, 2)**2) * vA**2/ms(sproc)**2 +1.d0)

     ! positive n:
     p_res=(gamma*ms(sproc) * om - 1.d0 * nn * qs(sproc))/kpar

     if ((pp(sproc,2,ipar,2).LE.real(p_res)).and.&
			  (pp(sproc,2,ipar+1,2).GT.real(p_res))) found_res_plus = .TRUE.

    ! negative n:
    p_res=(gamma*ms(sproc) * om + 1.d0 * nn * qs(sproc))/kpar

        if ((pp(sproc,2,ipar,2).LE.real(p_res)).and.&
   			  (pp(sproc,2,ipar+1,2).GT.real(p_res))) found_res_minus = .TRUE.
	  enddo
  enddo


	else ! non-relativistic case:

	  ! positive n:
	  ipar = 0
	  p_res = (ms(sproc) * om - 1.d0 * nn * qs(sproc))/kpar

	  do while ((ipar.LE.(npar-2)).AND.(.NOT.found_res_plus))
		 ipar = ipar + 1
		 if ((pp(sproc,2,ipar,2).LE.real(p_res)).and.&
			  (pp(sproc,2,ipar+1,2).GT.real(p_res))) found_res_plus = .TRUE.

	  enddo

	  ! negative n:
	  ipar = 0
	  p_res = (ms(sproc) * om + 1.d0 * nn * qs(sproc))/kpar

	  do while ((ipar.LE.(npar-2)).AND.(.NOT.found_res_minus))
		 ipar = ipar + 1
		 if ((pp(sproc,2,ipar,2).LE.real(p_res)).and.&
			  (pp(sproc,2,ipar+1,2).GT.real(p_res))) found_res_minus = .TRUE.

	  enddo


	  ! Check if there is a resonance right outside the integration domain:
	  p_res = (ms(sproc) * om - 1.d0 * nn * qs(sproc))/kpar

	  if ((real(p_res).LT.pp(sproc,2,1,2)).AND.&
		(real(p_res).GE.(pp(sproc,2,1,2)-(1.d0*positions_principal)*dppar))) found_res_plus=.TRUE.
	  if ((real(p_res).GE.pp(sproc,2,npar-1,2)).AND.&
		(real(p_res).LT.(pp(sproc,2,npar-1,2)+(1.d0*positions_principal)*dppar))) found_res_plus=.TRUE.

	   p_res = (ms(sproc) * om + 1.d0 * nn * qs(sproc))/kpar

	  if ((real(p_res).LT.pp(sproc,2,1,2)).AND.&
		(real(p_res).GE.(pp(sproc,2,1,2)-(1.d0*positions_principal)*dppar))) found_res_minus=.TRUE.
	  if ((real(p_res).GE.pp(sproc,2,npar-1,2)).AND.&
		(real(p_res).LT.(pp(sproc,2,npar-1,2)+(1.d0*positions_principal)*dppar))) found_res_minus=.TRUE.
	endif

end subroutine determine_resonances




double complex function full_integrate(om, nn, mode, found_res)
  !! This function returns the full integral expression according to Eq. (2.9) in the code paper.
  use alps_var, only : npar, relativistic, sproc
  use alps_fns_rel, only : integrate_res_rel,landau_integrate_rel
  implicit none

  double complex, intent(in) :: om
  !! Complex wave frequency \(\omega\).

  integer, intent(in) :: nn
  !! Order of the Bessel function.

  integer, intent(in) :: mode
  !! Index of the entries in the T-tensor of Eq. (2.10).

  logical, intent(in) :: found_res
  !! Check whether a resonance is found.


  full_integrate = cmplx(0.d0,0.d0,kind(1.d0))

  if (.not. found_res) then
     !Brute force integrate
     full_integrate = integrate(om, nn, mode, 1, npar-1)
	 elseif (found_res.and.relativistic(sproc)) then
       	 	if (aimag(om).GT.0.d0) then
	    		full_integrate = integrate_res_rel(om,nn,mode)
       	 	elseif (aimag(om).LT.0.d0) then
      	 		full_integrate = integrate_res_rel(om,nn,mode) + 2.d0 * landau_integrate_rel(om, nn, mode)
       	 	elseif (aimag(om).EQ.0.d0) then
	       	 	full_integrate = integrate_res_rel(om,nn,mode) + landau_integrate_rel(om, nn, mode)
      	 	endif
  elseif ((found_res).and.(aimag(om).GT.0.d0)) then
     !Brute force integrate
	 full_integrate = integrate_res(om,nn,mode)
  elseif ((found_res).and.(aimag(om).LT.0.d0)) then
     !Landau Integral
   	 full_integrate = integrate_res(om,nn,mode)+2.d0 * landau_integrate(om, nn, mode)
  elseif ((found_res).and.(aimag(om).EQ.0.d0)) then
   	 full_integrate = integrate_res(om,nn,mode)+landau_integrate(om, nn, mode)
  endif
  return
end function full_integrate






double complex function integrate(om, nn, mode, iparmin, iparmax)
  !! This function performs the integral in Eq. (2.9) of the code paper, but without
  !! accounting for the Landau contour integral. It is called by [[full_integrate(function)]].
  use alps_var, only : nperp, pp, pi, sproc
  implicit none

  double complex, intent(in) :: om
  !! Complex wave frequency \(\omega\).

  integer, intent(in) :: nn
  !! Order of the Bessel function.

  integer, intent(in) :: mode
  !! Index of the entries in the T-tensor of Eq. (2.10).

  integer :: iparmin
  !! Minimum limit index of parallel momentum for integration.

  integer :: iparmax
  !! Maximum limit index of parallel momentum for integration.

  integer :: iperp
  !! Index to loop over perpendicular momentum.

  integer :: ipar
  !! Index to loop over parallel momentum.

  double precision :: dpperp
  !! Inifinitesimal step in perpendicular momentum.

  double precision :: dppar
  !! Inifinitesimal step in parallel momentum.


  integrate = cmplx (0.d0, 0.d0,kind(1.d0))

  dpperp = pp(sproc, 2, 2, 1) - pp(sproc, 1, 2, 1)
  dppar  = abs(pp(sproc, 2, 2, 2) - pp(sproc, 2, 1, 2))

  integrate = integrate + &
       2.d0 * resU(om, nn, 1, iparmin) * int_T(nn, 1, iparmin, mode) + &
       2.d0 * resU(om, nn, 1, iparmax) * int_T(nn, 1, iparmax, mode) + &
       resU(om, nn, nperp -1, iparmin) * int_T(nn, nperp -1, iparmin, mode) + &
       resU(om, nn, nperp -1, iparmax) * int_T(nn, nperp -1, iparmax, mode)

  do iperp = 2, nperp-2
     do ipar = iparmin+1, iparmax-1
        integrate = integrate + 4.d0 * resU(om, nn, iperp, ipar) * int_T(nn, iperp, ipar, mode)
     enddo

     integrate = integrate + &
      2.d0 * ( resU(om, nn, iperp, iparmin) * int_T(nn, iperp, iparmin, mode) + &
      resU(om, nn, iperp, iparmax) * int_T(nn, iperp, iparmax, mode) )
  enddo


  do ipar = iparmin+1, iparmax-1
        integrate = integrate + &
             2.d0 * (2.d0 * resU(om, nn, 1, ipar) * int_T(nn, 1, ipar, mode) + &
             resU(om, nn, nperp -1, ipar) * int_T(nn, nperp -1, ipar, mode) )
  enddo

  integrate = 2.d0 * pi * integrate * dpperp * dppar * 0.25d0

  return

end function integrate





double complex function integrate_res(om,nn,mode)
  !! This function performs the integration near resonances as described in Section 3.1 of the code paper. It is only called if resonances are present in or near the integration domain.
	use alps_var, only : nperp,npar,pp,ms,qs,kpar,pi,sproc
	use alps_var, only : positions_principal,n_resonance_interval, Tlim
	implicit none

  double complex, intent(in) :: om
  !! Complex wave frequency \(\omega\).

  integer, intent(in) :: nn
  !! Order of the Bessel function.

  integer, intent(in) :: mode
  !! Index of the entries in the T-tensor of Eq. (2.10).

	integer :: ipar_res
  !! Index of the nearest parallel momentum to the resonance.

  integer :: ipar
  !! Index to loop over parallel momentum.

  integer :: iperp
  !! Index to loop over perpendicular momentum.

  integer :: ntiny
  !! Small steps for integration near pole according to Eq. (3.5).

	integer :: lowerlimit
  !! Index of lower limit for integration according to Eq. (3.5).

  integer :: upperlimit
  !! Index of upper limit for integration according to Eq. (3.5).

  double precision :: dpperp
  !! Inifinitesimal step in perpendicular momentum.

  double precision :: dppar
  !! Inifinitesimal step in parallel momentum.

	double precision :: capDelta
  !! Size of interval \(\Delta\) for integration according to Eq. (3.5).

  double precision :: smdelta
  !! Size of sub-interval \(\delta\) for integration according to Eq. (3.5).

  double precision :: denomR
  !! Real part of denominator of Eq. (3.6).

  double precision :: denomI
  !! Imaginary part of denominator of Eq. (3.6).

  double precision :: ppar
  !! Parallel momentum.

  double precision :: correction
  !! Correction factor for finite size of interval \(\delta\).

	double complex :: p_res
  !! Resonance momentum.

  double complex :: ii
  !! Imaginary unit.

  double complex :: integrate_norm
  !! Variable to host integral without accounting for resonances.

  double complex :: gprimetr
  !! Function \(g^{\prime}\) in Eq. (3.6).

	logical :: found_res
  !! Check whether a resonance is found.

	dpperp = pp(sproc, 2, 2, 1) - pp(sproc, 1, 2, 1)
	dppar  = pp(sproc, 2, 2, 2) - pp(sproc, 2, 1, 2)

	integrate_res=cmplx(0.d0,0.d0,kind(1.d0))
	integrate_norm=cmplx(0.d0,0.d0,kind(1.d0))

	ii=cmplx(0.d0,1.d0,kind(1.d0))

	! determine the position of the resonance (i.e., the step LEFT of it):
	ipar = 0
	ipar_res=0
	found_res = .FALSE.

	p_res = (ms(sproc) * om - 1.d0*nn * qs(sproc))/kpar

	do while ((ipar.LT.(npar-2)).AND.(.NOT.found_res))
		ipar = ipar + 1

		if ((pp(sproc,2,ipar+1,2).GT.real(p_res)).and.&
			  (pp(sproc,2,ipar,2).LE.real(p_res))) then
				ipar_res=ipar
				found_res = .TRUE.
		endif
	enddo


	! Handle resonances that are right outside the integration domain:
	p_res = (ms(sproc) * om - (1.d0*nn) * qs(sproc))/kpar

	do ipar=0,positions_principal

		if ((real(p_res).GE.(pp(sproc,2,0,2)-dppar*ipar)).AND.&
		  (real(p_res).LT.(pp(sproc,2,0,2)-dppar*(ipar-1)))) ipar_res = -ipar

		if ((real(p_res).GE.(pp(sproc,2,npar-1,2)+dppar*ipar)).AND.&
		  (real(p_res).LT.(pp(sproc,2,npar-1,2)+dppar*(ipar+1)))) ipar_res = npar-1+ipar

	enddo


	! If the resonance is close to the edge, do the normal integration:
	if ((ipar_res-positions_principal).LE.2) then
		integrate_res=integrate(om, nn, mode, ipar_res+positions_principal,npar-1)
		return
	endif


	if ((ipar_res+positions_principal).GE.(npar-2)) then
		integrate_res=integrate(om, nn, mode, 1, ipar_res-positions_principal)
		return
	endif

	! positions_principal defines how close we can go to ipar_res with the "normal" integration.
	! the following part is the normal function "integrate" on the left and on the right of ipar_res:
	! left:
	lowerlimit=ipar_res-positions_principal
	integrate_norm = integrate(om, nn, mode, 1, lowerlimit)


	! right:
	if(abs(real(p_res)-pp(sproc,2,ipar_res,2)).LT.(0.5d0*dppar)) then
		upperlimit=ipar_res+positions_principal+1
	else
		upperlimit=ipar_res+positions_principal+2
	endif
	integrate_norm = integrate_norm + integrate(om, nn, mode, upperlimit, npar-1)



	! The following part includes the analytic switch described in Section 3.1 of the code paper
	! We call the function that needs to be integrated WITHOUT the resonance part funct_g.
	! We linearize this function. Now we can calculate the even part of the integration.
	! We set Delta so that it starts at ipar_res-positions_principal. In that way, there is only
	! a tiny rest left on the right side that needs to be integrated.
	! split the range between the resonance and the upper limit into n_resonance_interval steps:

	denomR=real(ms(sproc)*om/kpar - (1.d0*nn) * qs(sproc) /kpar )
	denomI=aimag(ms(sproc)*om/kpar)

	capDelta=real(p_res)-pp(sproc,1,ipar_res-positions_principal,2)
	smdelta=capDelta/(1.d0*n_resonance_interval)

	if (abs(denomI).GT.Tlim) then ! regular integration:
		! Integrate the boundaries:
		ppar=real(p_res) ! left end of integration interval

    ! At iperp=1, we are already missing the part from iperp=0, where we should actually start. Therefore, we use 4 instead of 2 in the trapezoid integration:
		integrate_res = integrate_res + 2.d0 * funct_g(ppar,1,om,nn,mode)/(ppar-denomR-ii*denomI)
		integrate_res = integrate_res - 2.d0 * funct_g(2.d0*denomR-ppar,1,om,nn,mode)/(ppar-denomR+ii*denomI)

		integrate_res = integrate_res + funct_g(ppar,nperp-1,om,nn,mode)/(ppar-denomR-ii*denomI)
		integrate_res = integrate_res - funct_g(2.d0*denomR-ppar,nperp-1,om,nn,mode)/(ppar-denomR+ii*denomI)

		ppar=capDelta+real(p_res)	! right end of integration interval

		integrate_res = integrate_res + 2.d0 * funct_g(ppar,1,om,nn,mode)/(ppar-denomR-ii*denomI)
		integrate_res = integrate_res - 2.d0 * funct_g(2.d0*denomR-ppar,1,om,nn,mode)/(ppar-denomR+ii*denomI)

		integrate_res = integrate_res + funct_g(ppar,nperp-1,om,nn,mode)/(ppar-denomR-ii*denomI)
		integrate_res = integrate_res - funct_g(2.d0*denomR-ppar,nperp-1,om,nn,mode)/(ppar-denomR+ii*denomI)



		do iperp = 2, nperp-2
			do ipar = 1, n_resonance_interval-1
				ppar=real(p_res)+smdelta*ipar

				integrate_res = integrate_res + 4.d0 * funct_g(ppar,iperp,om,nn,mode)/(ppar-denomR-ii*denomI)
				integrate_res = integrate_res - 4.d0 * funct_g(2.d0*denomR-ppar,iperp,om,nn,mode)/(ppar-denomR+ii*denomI)

			enddo

			ppar=real(p_res)+smdelta
			ppar=real(p_res)

			integrate_res = integrate_res + 2.d0 * funct_g(ppar,iperp,om,nn,mode)/(ppar-denomR-ii*denomI)
			integrate_res = integrate_res - 2.d0 * funct_g(2.d0*denomR-ppar,iperp,om,nn,mode)/(ppar-denomR+ii*denomI)

			ppar=real(p_res)+capDelta

			integrate_res = integrate_res + 2.d0 * funct_g(ppar,iperp,om,nn,mode)/(ppar-denomR-ii*denomI)
			integrate_res = integrate_res - 2.d0 * funct_g(2.d0*denomR-ppar,iperp,om,nn,mode)/(ppar-denomR+ii*denomI)

		enddo


		do ipar = 1, n_resonance_interval-1
			ppar=real(p_res)+smdelta*ipar

      ! At iperp=1, we are already missing the part from iperp=0, where we should actually start. Therefore, we use 4 instead of 2 in the trapezoid integration:
			integrate_res = integrate_res + 4.d0 * funct_g(ppar,1,om,nn,mode)/(ppar-denomR-ii*denomI)
			integrate_res = integrate_res - 4.d0 * funct_g(2.d0*denomR-ppar,1,om,nn,mode)/(ppar-denomR+ii*denomI)

			integrate_res = integrate_res + 2.d0 * funct_g(ppar,nperp-1,om,nn,mode)/(ppar-denomR-ii*denomI)
			integrate_res = integrate_res - 2.d0 * funct_g(2.d0*denomR-ppar,nperp-1,om,nn,mode)/(ppar-denomR+ii*denomI)

		  enddo


	else ! analytic approximation according to Eq. (3.7) of the code paper:


		ppar=real(p_res)

    ! At iperp=1, we are already missing the part from iperp=0, where we should actually start. Therefore, we use 4 instead of 2 in the trapezoid integration:
		gprimetr = (funct_g(denomR+dppar,1,om,nn,mode)-funct_g(denomR-dppar,1,om,nn,mode))/(2.d0*dppar)
		if (denomI.NE.0.d0) then
			integrate_res = integrate_res + 2.d0 * 2.d0 * gprimetr * (ppar-denomR)**2 / ((ppar-denomR)**2+denomI**2)
		else
			integrate_res = integrate_res + 2.d0 * 2.d0 * gprimetr
		endif

		gprimetr = (funct_g(denomR+dppar,nperp-1,om,nn,mode)-funct_g(denomR-dppar,nperp-1,om,nn,mode))/(2.d0*dppar)
		if (denomI.NE.0.d0) then
			integrate_res = integrate_res + 2.d0 * gprimetr * (ppar-denomR)**2 / ((ppar-denomR)**2+denomI**2)
		else
			integrate_res = integrate_res + 2.d0 * gprimetr
		endif


		ppar=capDelta+real(p_res)	! right end of integration interval
		gprimetr = (funct_g(denomR+dppar,1,om,nn,mode)-funct_g(denomR-dppar,1,om,nn,mode))/(2.d0*dppar)
		integrate_res = integrate_res + 2.d0 * 2.d0*gprimetr*(ppar-denomR)**2 / ((ppar-denomR)**2+denomI**2)

		gprimetr = (funct_g(denomR+dppar,nperp-1,om,nn,mode)-funct_g(denomR-dppar,nperp-1,om,nn,mode))/(2.d0*dppar)
		integrate_res = integrate_res + 2.d0*gprimetr*(ppar-denomR)**2 / ((ppar-denomR)**2+denomI**2)

    ! The following lines account for the second term in Eq. (3.7) in the code paper:
    if (denomI.GT.0.d0) then
      integrate_res = integrate_res + 2.d0 * 2.d0 * ii * pi * funct_g(denomR,1,om,nn,mode)/smdelta
			integrate_res = integrate_res + 2.d0 * ii * pi * funct_g(denomR,nperp-1,om,nn,mode)/smdelta
    else if (denomI.LT.0.d0) then
      integrate_res = integrate_res - 2.d0 * 2.d0 * ii * pi * funct_g(denomR,1,om,nn,mode)/smdelta
      integrate_res = integrate_res - 2.d0 * ii * pi * funct_g(denomR,nperp-1,om,nn,mode)/smdelta
    else if (denomI.EQ.0.d0) then
      integrate_res = integrate_res+0.d0
    endif


		do iperp = 2, nperp-2
			do ipar = 1, n_resonance_interval-1
				ppar=real(p_res)+smdelta*ipar

				gprimetr = (funct_g(denomR+dppar,iperp,om,nn,mode)-&
					funct_g(denomR-dppar,iperp,om,nn,mode))/(2.d0*dppar)
				integrate_res = integrate_res + 4.d0 * 2.d0 * gprimetr * (ppar-denomR)**2 / ((ppar-denomR)**2+denomI**2)
			enddo

			ppar=real(p_res)
      ! In this case, ppar is equal to denomR, so: no integration needed

			ppar=real(p_res)+capDelta
			gprimetr = (funct_g(denomR+dppar,iperp,om,nn,mode)-funct_g(denomR-dppar,iperp,om,nn,mode))/(2.d0*dppar)
			integrate_res = integrate_res + 2.d0*2.d0*gprimetr*(ppar-denomR)**2 / ((ppar-denomR)**2+denomI**2)


      ! The following lines account for the second term in Eq. (3.7) in the paper:
      if (denomI.GT.0.d0) then
        integrate_res = integrate_res + 4.d0 * ii * pi * funct_g(denomR,iperp,om,nn,mode)/smdelta
      else if (denomI.LT.0.d0) then
        integrate_res = integrate_res - 4.d0 * ii * pi * funct_g(denomR,iperp,om,nn,mode)/smdelta
      else if (denomI.EQ.0.d0) then
        integrate_res = integrate_res+0.d0
      endif

		enddo



		do ipar = 1, n_resonance_interval-1
			ppar=real(p_res)+smdelta*ipar

			gprimetr = (funct_g(denomR+dppar,1,om,nn,mode)-funct_g(denomR-dppar,1,om,nn,mode))/(2.d0*dppar)
			integrate_res = integrate_res + 4.d0*2.d0*gprimetr*(ppar-denomR)**2 / ((ppar-denomR)**2+denomI**2)

			gprimetr = (funct_g(denomR+dppar,nperp-1,om,nn,mode)-funct_g(denomR-dppar,nperp-1,om,nn,mode))/(2.d0*dppar)
			integrate_res = integrate_res + 2.d0*2.d0*gprimetr*(ppar-denomR)**2 / ((ppar-denomR)**2+denomI**2)

		  enddo


	endif



	! Calculate tiny rest left between the point real(p_res)+capDelta and the position
	! pp(sproc,2,upperlimit,2). We split this interval into steps of roughly size smdelta:
	ntiny=int((pp(sproc,2,upperlimit,2)-real(p_res)-capDelta)/smdelta)

	if (ntiny.GT.0) then

		! Correct for the fact that smdelta is not exactly the step width in the tiny-rest integration:
		correction=((pp(sproc,2,upperlimit,2)-real(p_res)-capDelta)/(1.d0*ntiny))/smdelta


		ppar=real(p_res)+capDelta

		integrate_res=integrate_res + &
		 2.d0 * correction*(funct_g(ppar,1,om,nn,mode)/(ppar-denomR-ii*denomI))

		integrate_res=integrate_res + &
		correction*(funct_g(ppar,nperp-1,om,nn,mode)/(ppar-denomR-ii*denomI))


		ppar=real(p_res)+capDelta+correction*smdelta*ntiny

		integrate_res=integrate_res + &
		2.d0 * correction*(funct_g(ppar,1,om,nn,mode)/(ppar-denomR-ii*denomI))

		integrate_res=integrate_res + &
		correction*(funct_g(ppar,nperp-1,om,nn,mode)/(ppar-denomR-ii*denomI))


		do iperp=2,nperp-2
			do ipar=1,ntiny-1
				ppar=real(p_res)+capDelta+correction*smdelta*ipar

				integrate_res=integrate_res + 4.d0*&
				correction*(funct_g(ppar,iperp,om,nn,mode)/(ppar-denomR-ii*denomI))
			enddo


			ppar=real(p_res)+capDelta

			integrate_res=integrate_res + 2.d0*&
			correction*(funct_g(ppar,iperp,om,nn,mode)/(ppar-denomR-ii*denomI))


			ppar=real(p_res)+capDelta+correction*smdelta*ntiny

			integrate_res=integrate_res + 2.d0*&
			correction*(funct_g(ppar,iperp,om,nn,mode)/(ppar-denomR-ii*denomI))

		enddo

		do ipar=1,ntiny-1
			ppar=real(p_res)+capDelta+correction*smdelta*ipar

			integrate_res=integrate_res + 2.d0 * 2.d0*&
			correction*(funct_g(ppar,1,om,nn,mode)/(ppar-denomR-ii*denomI))

			integrate_res=integrate_res + 2.d0*&
			correction*(funct_g(ppar,nperp-1,om,nn,mode)/(ppar-denomR-ii*denomI))
		enddo

	endif


	integrate_res = 2.d0 * pi * integrate_res * smdelta * dpperp * 0.25d0
	integrate_res = integrate_res + integrate_norm

	return

end function integrate_res




double complex function funct_g(ppar_real,iperp,om,nn,mode)
  !! This function returns the function \(g\) from Eq. (3.2) of the code paper.
	use alps_var,only : npar,pp,ms,qs,kpar,df0,sproc
	implicit none


  double precision, intent(in) :: ppar_real
  !! Real part of the momentum at which \(g\) is evaluated.

  integer, intent(in) :: iperp
  !! Index of the perpendicular momentum.

  double complex, intent(in) :: om
  !! Complex wave frequency \(\omega\).

  integer, intent(in) :: nn
  !! Order of the Bessel function.

  integer, intent(in) :: mode
  !! Index of the entries in the T-tensor of Eq. (2.10).

	integer :: ipar
  !! Index of the parallel momentum.

  integer :: ipar_close
  !! Index of the parallel momentum closest to the resonance.

	double complex :: integrandplus
  !! Integrand function ahead of position.

  double complex :: integrandminus
  !! Integrand function behind of position.

  double complex :: integrand
  !! Integrand function at position.

	double precision :: dppar
  !! Inifinitesimal step in parallel momentum.


	dppar  = abs(pp(sproc, 2, 2, 2) - pp(sproc, 2, 1, 2))

	ipar_close=0
	! determine the closest ipar (on the left) to this p_res_real:
	do ipar=1,npar-1
		if ((pp(sproc,iperp,ipar+1,2).GT.ppar_real).AND.(pp(sproc,iperp,ipar,2).LE.ppar_real)) then
			ipar_close=ipar
		endif
	enddo

	if (ipar_close.GE.(npar-1)) ipar_close=npar-2
	if (ipar_close.LE.1) ipar_close=2


	! calculate the function on the grid (left and right of ppar_real):
	integrandplus=-qs(sproc) * &
		   (om*df0(sproc, iperp, ipar_close+1, 1) + (kpar / ( ms(sproc)) ) * &
		   (pp(sproc, iperp, ipar_close+1, 1) * df0(sproc, iperp, ipar_close+1, 2) -&
		   pp(sproc, iperp, ipar_close+1, 2) * df0(sproc, iperp, ipar_close+1, 1) ) ) * &
		   int_T(nn,iperp,ipar_close+1,mode)/kpar

	integrand=-qs(sproc) * &
		   (om*df0(sproc, iperp, ipar_close, 1) + (kpar / ( ms(sproc)) ) * &
		   (pp(sproc, iperp, ipar_close, 1) * df0(sproc, iperp, ipar_close, 2) -&
		   pp(sproc, iperp, ipar_close, 2) * df0(sproc, iperp, ipar_close, 1) ) ) * &
		   int_T(nn,iperp,ipar_close,mode)/kpar

	integrandminus=-qs(sproc) * &
		   (om*df0(sproc, iperp, ipar_close-1, 1) + (kpar / ( ms(sproc)) ) * &
		   (pp(sproc, iperp, ipar_close-1, 1) * df0(sproc, iperp, ipar_close-1, 2) -&
		   pp(sproc, iperp, ipar_close-1, 2) * df0(sproc, iperp, ipar_close-1, 1) ) ) * &
		   int_T(nn,iperp,ipar_close-1,mode)/kpar

	funct_g = integrand+ &
		0.5d0*((integrandplus-integrandminus)/dppar) * (ppar_real - pp(sproc,iperp,ipar_close,2))

	return

end function funct_g





double complex function landau_integrate(om, nn, mode)
  !! This function evaluates the Landau contour according to Eqs. (3.8) and (3.9) of the code paper.
	use alps_var, only : nperp, pp, pi, ms, qs, kpar, sproc
	use alps_analyt, only: eval_fit
	implicit none

  double complex, intent(in) :: om
  !! Complex wave frequency \(\omega\).

  integer, intent(in) :: nn
  !! Order of the Bessel function.

  integer, intent(in) :: mode
  !! Index of the entries in the T-tensor of Eq. (2.10).

  double precision :: dpperp
  !! Inifinitesimal step in perpendicular momentum.

  double precision :: dppar
  !! Inifinitesimal step in parallel momentum.

  double precision :: h
  !! Infinitesimal step in perpendicular momentum.

  double complex :: ii
  !! Imaginary unit.

  double complex :: p_res
  !! Resonance momentum.

  double complex :: dfperp_C
  !! Derivative of f0 evaluated at resonance.

  double complex :: dfpar_C
  !! Derivative of f0 evaluated at resonance.

	integer :: iperp
	!! Index of perpendicular momentum.


	ii = cmplx(0.d0,1.d0,kind(1.d0))


	landau_integrate = cmplx(0.d0,0.d0,kind(1.d0))

	dpperp = pp(sproc, 2, 2, 1) - pp(sproc, 1, 2, 1)
	dppar = abs(pp(sproc, 2, 2, 2) - pp(sproc, 2, 1, 2))

  ! Landau contour integral:
  ! At iperp=1, we are already missing the part from iperp=0, where we should actually start. Therefore, we use 4 instead of 2 in the trapezoid integration:
	do iperp = 1, nperp-1
		if ((iperp .EQ. 0).or.(iperp .EQ. (nperp -1))) then
		   h = 0.5d0
		else
		   h = 1.d0
		endif

		p_res = (ms(sproc) * (om) - 1.d0*nn * qs(sproc))/kpar

		! Calculate the derivatives of f0 at the complex p_res:
		dfperp_C=(eval_fit(sproc,iperp+1,p_res)-eval_fit(sproc,iperp-1,p_res))/(2.d0*dpperp)
		dfpar_C=(eval_fit(sproc,iperp,p_res+dppar)-eval_fit(sproc,iperp,p_res-dppar))/(2.d0*dppar)

    landau_integrate = landau_integrate - h * int_T_res(nn, iperp, p_res, mode)*&
        (qs(sproc) /abs(kpar)) *( (pp(sproc, iperp, 1, 1) * dfpar_C - &
        p_res * dfperp_C) * kpar  /  ( ms(sproc)) + om*dfperp_C )

	enddo

	landau_integrate = landau_integrate * ii * dpperp * pi * 2.d0 * pi

	return

end function landau_integrate




double complex function int_ee(om)
  !! This function returns the ee term in Eq. (2.9).
	use alps_var, only : qs, ms, nperp, npar, pp, pi, df0, sproc
	implicit none

    double complex, intent(in) :: om
    !! Complex wave frequency \(\omega\).

    integer :: iperp
    !! Index to loop over perpendicular momentum.

    integer :: ipar
    !! Index to loop over parallel momentum.

    double precision :: dpperp
    !! Inifinitesimal step in perpendicular momentum.

    double precision :: dppar
    !! Inifinitesimal step in parallel momentum.

	int_ee = cmplx (0.d0, 0.d0,kind(1.d0))

	dpperp = pp(sproc, 2, 2, 1) - pp(sproc, 1, 2, 1)
	dppar  = abs(pp(sproc, 2, 2, 2) - pp(sproc, 2, 1, 2))

  ! At iperp=1, we are already missing the part from iperp=0, where we should actually start. Therefore, we use 4 instead of 2 in the trapezoid integration:
	int_ee = int_ee + &
		   2.d0 * pp(sproc, 1, 1, 2) *&
		   (df0(sproc, 1, 1, 2)*pp(sproc, 1, 1, 1) - &
		   pp(sproc, 1, 1, 1)*df0(sproc, 1, 1, 1))


	int_ee = int_ee + &
		   2.d0 * pp(sproc, 1, npar -1, 2) *&
		   (df0(sproc, 1, npar -1, 2)*pp(sproc, 1, npar -1, 1) - &
		   pp(sproc, 1, npar -1, 2)*df0(sproc, 1, npar -1, 1))


	int_ee = int_ee + &
		   pp(sproc, nperp -1, 1, 2) *&
		   (df0(sproc, nperp -1, 1, 2)*pp(sproc, nperp -1, 1, 1) - &
		   pp(sproc, nperp -1, 1, 2)*df0(sproc, nperp -1, 1, 1))


	int_ee = int_ee + &
		   pp(sproc, nperp -1, npar -1, 2) *&
		   (df0(sproc, nperp -1, npar -1, 2)*pp(sproc, nperp -1, npar -1, 1) - &
		   pp(sproc, nperp -1, npar -1, 2)*df0(sproc, nperp -1, npar -1, 1))


	do iperp = 2, nperp-2
		do ipar = 2, npar-2
			  int_ee = int_ee + &
				   4.d0*(&
				   pp(sproc, iperp, ipar, 2) *&
				   (df0(sproc, iperp, ipar, 2)*pp(sproc, iperp, ipar, 1) - &
				   pp(sproc, iperp, ipar, 2)*df0(sproc, iperp, ipar, 1)) )
		enddo
	enddo


	do ipar = 2, npar-2

    ! At iperp=1, we are already missing the part from iperp=0, where we should actually start. Therefore, we use 4 instead of 2 in the trapezoid integration:
		   int_ee = int_ee + &
				2.d0 * 2.d0*(&
				pp(sproc, 1, ipar, 2) *&
				(df0(sproc, 1, ipar, 2)*pp(sproc, 1, ipar, 1) - &
				pp(sproc, 1, ipar, 2)*df0(sproc, 1, ipar, 1)) )


			int_ee = int_ee + &
				2.d0*(&
				pp(sproc, nperp -1, ipar, 2) *&
				(df0(sproc, nperp -1, ipar, 2)*pp(sproc, nperp -1, ipar, 1) - &
				pp(sproc, nperp -1, ipar, 2)*df0(sproc, nperp -1, ipar, 1)) )
	enddo

	do iperp = 2, nperp-2

		  int_ee = int_ee + &
				2.d0*(&
				pp(sproc, iperp, 1, 2) *&
				(df0(sproc, iperp, 1, 2)*pp(sproc, iperp, 1, 1) - &
				pp(sproc, iperp, 1, 2)*df0(sproc, iperp, 1, 1)) )

			int_ee = int_ee + &
				2.d0*(&
				pp(sproc, iperp, npar -1, 2) *&
				(df0(sproc, iperp, npar -1, 2)*pp(sproc, iperp, npar -1, 1) - &
				pp(sproc, iperp, npar -1, 2)*df0(sproc, iperp, npar -1, 1)))
	enddo

	int_ee = int_ee * 2.d0 * pi * qs(sproc) / ms(sproc)
	int_ee = int_ee * dpperp * dppar * 0.25d0

	return

end function int_ee




double complex function resU(om, nn, iperp, ipar)
  !! This function evaluates the term proportional to \(U\) in Eq. (2.9) of the code paper.
	use ALPS_var, only : pp, kpar, ms, qs, df0, vA, sproc, relativistic
	implicit none

  double complex, intent(in) :: om
  !! Complex wave frequency \(\omega\).

  integer, intent(in) :: nn
  !! Order of the Bessel function.

  integer, intent(in) :: iperp
  !! Index to loop over perpendicular momentum.

  integer, intent(in) :: ipar
  !! Index to loop over parallel momentum.

	double precision :: gamma
  !! Lorentz factor \(\Gamma\).


	gamma = 1.d0 ! standard for non-relativistic calculation

  ! For relativistic calculation:
	if (relativistic(sproc)) gamma = sqrt((pp(sproc, iperp, ipar, 1)**2 + &
		pp(sproc, iperp, ipar, 2)**2) * vA**2/ms(sproc)**2 +1.d0)

	resU = qs(sproc) * &
	   (om*df0(sproc, iperp, ipar, 1) + (kpar / (gamma * ms(sproc)) ) * &
	   (pp(sproc, iperp, ipar, 1) * df0(sproc, iperp, ipar, 2) -&
	   pp(sproc, iperp, ipar, 2) * df0(sproc, iperp, ipar, 1) ) )/&
	   (gamma * ms(sproc)*om - kpar * pp(sproc, iperp, ipar, 2) - &
	   (1.d0*nn) * qs(sproc)  )

	return

end function resU




double complex function int_T(nn, iperp, ipar, mode)
!! This function returns the T-tensor according to Eq. (2.10) of the code paper.
	use ALPS_var, only : pp, kperp, qs, bessel_array, sproc
	implicit none

  integer, intent(in) :: nn
  !! Order of the Bessel function.

  integer, intent(in) :: iperp
  !! Index to loop over perpendicular momentum.

  integer, intent(in) :: ipar
  !! Index to loop over parallel momentum.

  integer, intent(in) :: mode
  !! Index of the entries in the T-tensor of Eq. (2.10).

	double precision :: z
  !! Argument of the Bessel functions.

	double precision :: bessel
  !! Bessel function.

	double precision :: besselP
  !! First derivative of the Bessel function.

	double complex :: ii = cmplx(0.d0,1.d0,kind(1.d0))
  !! Imaginary unit.

	!Bessel function argument:
	z= kperp/qs(sproc)

	! Look up array of Bessel functions:
	if (nn.LT.0) then
	   bessel=((-1.d0)**nn)*bessel_array(-nn,iperp)
	else
	   bessel=bessel_array(nn,iperp)
	endif

	! Determine derivative of Bessel function:
	if (nn.GE.1) then
		besselP = 0.5d0 * (bessel_array(nn-1,iperp)-bessel_array(nn+1,iperp))
	else if (nn.LT.-1) then
		besselP = 0.5d0 * ((((-1.d0)**(nn-1))*bessel_array(-(nn-1),iperp))&
			-(((-1.d0)**(nn+1))*bessel_array(-(nn+1),iperp)))
	else if (nn.EQ.0) then
	   besselP = -bessel_array(1,iperp)
	else if (nn.EQ.-1) then
		besselP = 0.5d0 * (bessel_array(2,iperp)-bessel_array(0,iperp))
	endif


	select case(mode) ! evaluate the components of the T-tensor:

	  case(1) !T xx
		 int_T = 1.d0 * (nn * nn) * bessel * bessel / (z * z)

	  case(2) !T yy
		 int_T = (pp(sproc, iperp, ipar, 1)**2)*besselP * besselP

	  case(3) !T zz
		 int_T = bessel * bessel * pp( sproc, iperp, ipar, 2)**2

	  case(4) !T xy
		 int_T = (pp(sproc, iperp, ipar, 1))*ii*(1.d0 * (nn)) * bessel * besselP / z

	  case(5) !T xz
		 int_T = (1.d0 * nn) * bessel * bessel* pp(sproc, iperp, ipar, 2)  / z

	  case(6) !T yz
		 int_T = (-1.d0 * ii) * bessel * besselP * pp(sproc, iperp, ipar, 2) *pp(sproc, iperp, ipar,1)

	end select

	return

end function int_T



double complex function int_T_res(nn, iperp, p_res, mode)
  !! This function returns the T-tensor according to Eq. (2.10) of the code paper for the case in which it is evaluated at the complex resonance momentum.
	use ALPS_var, only : pp, kperp, qs, bessel_array,sproc
	implicit none

  integer, intent(in) :: nn
  !! Order of the Bessel function.

  integer, intent(in) :: iperp
  !! Index to loop over perpendicular momentum.

  double complex, intent(in) :: p_res
  !! Complex resonance momentum.

  integer, intent(in) :: mode
  !! Index of the entries in the T-tensor of Eq. (2.10).

  double precision :: z
  !! Argument of the Bessel functions.

	double precision :: bessel
  !! Bessel function.

	double precision :: besselP
  !! First derivative of the Bessel function.

	double complex :: ii = cmplx(0.d0,1.d0,kind(1.d0))
  !! Imaginary unit.

	!Bessel function argument:
	z = kperp / qs(sproc)

	! Look up array of Bessel functions:
	if (nn.LT.0) then
	   bessel=((-1.d0)**(nn))*bessel_array(-nn,iperp)
	else
	   bessel=bessel_array(nn,iperp)
	endif

	! Determine derivative of Bessel function:
	if (nn.GE.1) then
		besselP = 0.5d0 * (bessel_array(nn-1,iperp)-bessel_array(nn+1,iperp))
	else if (nn.LT.-1) then
		besselP = 0.5d0 * ((((-1.d0)**(nn-1))*bessel_array(-(nn-1),iperp))&
			-(((-1.d0)**(nn+1))*bessel_array(-(nn+1),iperp)))
	else if (nn.EQ.0) then
	   besselP = -bessel_array(1,iperp)
	else if (nn.EQ.-1) then
		besselP = 0.5d0 * (bessel_array(2,iperp)-bessel_array(0,iperp))
	endif

	select case(mode) ! evaluate the components of the T-tensor:

	  case(1) !T xx
		 int_T_res = 1.d0 * (nn * nn) * bessel * bessel / (z * z)

	  case(2) !T yy
		 int_T_res = (pp(sproc, iperp, 1, 1)**2)*besselP * besselP

	  case(3) !T zz
		 int_T_res = bessel * bessel * p_res**2

	  case(4) !T xy
		 int_T_res = (pp(sproc, iperp, 1, 1))*ii*(1.d0 * (nn)) * bessel * besselP/z

	  case(5) !T xz
		 int_T_res = (1.d0 * nn) * bessel * bessel* p_res/z

	  case(6) !T yz
		 int_T_res = (-1.d0 * ii) * bessel * besselP * p_res*pp(sproc, iperp, 1, 1)

	end select

	return

end function int_T_res


subroutine secant(om)
  !! This subroutine applies the secant method to find the roots of the dispersion tensor.
	use ALPS_var, only : numiter, D_threshold, ierror, proc0, writeOut, D_prec
   use mpi
	implicit none

  double complex, intent(inout) :: om
  !! Complex wave frequency \(\omega\).

	double complex :: prevom
  !! Storage of previous entry of om.

  double complex :: ii
  !! Imaginary unit.

  double complex :: D
  !! Dispersion tensor.

  double complex :: Dprev
  !! Storage of previous entry of D.

  double complex :: jump
  !! Difference to be added to om.

  double complex :: minom
  !! Check variable for convergence.

  double complex :: minD
  !! Check variable for convergence.

	integer :: iter
  !! Index to loop over iterations.

	logical :: go_for_secant
  !! Check whether a secant-method step is required.

	ii = cmplx(0.d0,1.d0,kind(1.d0))

	prevom=om*(1.d0-D_prec)
	Dprev = disp(prevom)
	minD=Dprev
	minom=prevom

	call mpi_barrier(mpi_comm_world,ierror)

	iter = 0
	go_for_secant = .TRUE.

	do while ((iter.LE.(numiter-1)).AND.(go_for_secant))
		iter = iter + 1
		D = disp(om)

	 if ((abs(D-Dprev).LT.1.d-80)) then
		prevom = prevom + 1.d-8
		Dprev = disp(prevom)
	 endif

		if ((abs(D).LT.D_threshold)) then
			jump = 0.d0
			go_for_secant = .FALSE.
			if (proc0.AND.writeOut) then
				write(*,'(a,i4)') ' Converged after iteration ',iter
				write(*,'(a,2es14.4,a,2es14.4)') ' D(',real(om),aimag(om),')= ',D
			endif

		else
			jump = D*(om-prevom)/(D-Dprev)
		endif
		prevom = om
		om = om - jump
		Dprev = D
		if (abs(D).LT.abs(minD)) then
			minom=om
			minD=D
		endif
	enddo

	if (proc0.AND.writeOut.AND.(iter.GE.numiter)) then
		write(*,'(a,i4,a)') ' Maximum iteration ',iter,' reached.'
		om=minom
		write(*,'(a,2es14.4,a,2es14.4)') ' D(',real(om),aimag(om),')= ',D
	endif

end subroutine secant



subroutine om_scan(ik)
  !! This subroutine scans solutions along a single prescribed path in wavevector space.
  use ALPS_var, only : proc0, nroots, runname, ierror, wroots, scan, sproc
  use ALPS_var, only : kperp,kpar,kperp_last,kpar_last, D_gap
  use ALPS_var, only : nspec
  use ALPS_io,  only : get_unused_unit, isnancheck, alps_error
  use mpi
  implicit none


  integer, intent(in) :: ik
  !! Index of scan number.

  integer :: it
  !! Index to loop over steps of scan.

  integer :: nt
  !! Number of scans.

  integer :: in
  !! Number of roots

  character(500), dimension(:), allocatable :: scanName
  !! Output file name for scan.

  character(500), dimension(:), allocatable :: heatName
  !! Output file name for heating-rate calculation.

  character(500), dimension(:), allocatable :: eigenName
  !! Output file name for eigenfunction calculation.

  character(6) :: scan_ID
  !! ID tags for scan types.

  double precision :: theta_0
  !! Wavevector angle of previous step.

  double precision :: theta_1
  !! Wavevector angle.

  double precision :: k_0
  !! Wavevector magnitude of previous step.

  double complex :: omega
  !! Complex wave frequency \(\omega\).

  integer, dimension(:), allocatable :: scan_unit
  !! File unit for scan output. (1:nroots)

  integer, dimension(:), allocatable :: heat_unit
  !! File unit for heating-rate output. (1:nroots)

  integer, dimension(:), allocatable :: eigen_unit
  !! File unit for eigenfunction output. (1:nroots)

  integer :: imm
  !! Index to check for root jumps.

  logical, dimension(:),allocatable :: jump
  !! Check whether a jump should be applied. (1:nroots)

  logical :: alljump
  !! Check whether any root has jumped.

  double complex :: tmp
  !! Storage variable for determinant of dispersion tensor.

  double complex, dimension(1:3) :: ef
  !! Relative electric field amplitude (eigenfunction).

  double complex, dimension(1:3) :: bf
  !! Relative magnetic field amplitude (eigenfunction).

  double complex, dimension(1:nspec) :: ds
  !! Relative density-fluctuation amplitude (eigenfunction).

  double complex, dimension(1:3,1:nspec) :: Us
  !! Relative velocity-fluctuation amplitude (eigenfunction).

  double precision, dimension(1:nspec) :: Ps
  !! Relative heating rate of a given species.

  character (50) :: fmt_eigen
  !! Format string for eigenfunction output.

  character (50) :: fmt_heat
  !! Format string for heating-rate output.


  allocate(jump(1:nroots));jump=.true.

  if (proc0) then
     allocate(scan_unit(nroots))
     allocate(scanName(nroots))
     select case(scan(ik)%type_s)
     case (0) ! k_0 to k_1
        write(scan_ID,'(a)')'k1_k2_'
     case (1) ! theta_0 to theta_1
        write(scan_ID,'(a)')'theta_'
     case (2) ! |k_0| to |k_1| @ constant theta
        write(scan_ID,'(a)')'kcstq_'
     case (3) ! kperp scan
        write(scan_ID,'(a)')'kperp_'
     case (4) ! kpar scan
        write(scan_ID,'(a)')'kpara_'
     end select
          if (scan(ik)%eigen_s) then
        write(fmt_eigen,'(a,i0,a)') '(4es14.4,12es14.4,',nspec*8,'es14.4)'
        allocate(eigen_unit(nroots))
        allocate(eigenName(nroots))
     endif
     if (scan(ik)%heat_s) then
        write(fmt_heat,'(a,i0,a)') '(4es14.4,',nspec,'es14.4)'
        allocate(heat_unit(nroots))
        allocate(heatName(nroots))
     endif
     do in=1,nroots
        write(scanName(in),'(4a,i0,a,i0)')&
             'solution/',trim(runname),'.scan_',scan_ID,ik,'.root_',in
        write(*,'(2a)')' => ',trim(scanName(in))
        call get_unused_unit(scan_unit(in))
        open(unit=scan_unit(in),file=trim(scanName(in)),status='replace')
        write(scan_unit(in),'(4es14.4)') &
             kperp,kpar,wroots(in)
        close(scan_unit(in))
     enddo
  endif

  if ((scan(ik)%eigen_s).or.(scan(ik)%heat_s)) then

     do in=1,nroots
        omega=wroots(in)
        tmp = disp(omega)

        call calc_eigen(omega,ef,bf,Us,ds,Ps,scan(ik)%eigen_s,scan(ik)%heat_s)

        !reassign omega:
        omega=wroots(in)

        call mpi_barrier(mpi_comm_world,ierror)

        if (proc0) then
           if (scan(ik)%eigen_s) then
              write(eigenName(in),'(4a,i0,a,i0)')&
                   'solution/',trim(runname),'.eigen_',scan_ID,ik,'.root_',in
              write(*,'(2a)')' => ',trim(eigenName(in))
              call get_unused_unit(eigen_unit(in))
              open(unit=eigen_unit(in),file=trim(eigenName(in)),status='replace')
              write(eigen_unit(in),trim(fmt_eigen)) &
                   kperp,kpar,wroots(in),ef,bf,Us,ds
              close(eigen_unit(in))
           endif

           if (scan(ik)%heat_s) then
              write(heatName(in),'(4a,i0,a,i0)')&
                   'solution/',trim(runname),'.heat_',scan_ID,ik,'.root_',in
              write(*,'(2a)')' => ',trim(heatName(in))
              call get_unused_unit(heat_unit(in))
              open(unit=heat_unit(in),file=trim(heatName(in)),status='replace')
              write(heat_unit(in),trim(fmt_heat)) &
                   kperp,kpar,wroots(in),Ps
              close(heat_unit(in))
           endif

        endif
     enddo
  endif

  nt = scan(ik)%n_out*scan(ik)%n_res

  kperp_last=kperp;kpar_last=kpar

  theta_0=atan(kperp_last/kpar_last)
  k_0=sqrt(kperp_last**2+kpar_last**2)

  do it = 1, nt
     !Scan through wavevector space:
     select case(scan(ik)%type_s)
     case (0) ! k_0 to k_1
        if (scan(ik)%log_scan) then
           kperp=10.d0**(log10(kperp_last)+scan(ik)%diff*it)
           kpar=10.d0**(log10(kpar_last)+scan(ik)%diff2*it)
        else
           kperp=kperp_last+scan(ik)%diff*it
           kpar= kpar_last +scan(ik)%diff2*it
        endif
     case (1) ! theta_0 to theta_1
        if (scan(ik)%log_scan) then
           theta_1=10.d0**(log10(theta_0)+scan(ik)%diff*it)
        else
           theta_1=theta_0+scan(ik)%diff*it
        endif
        kperp=k_0*sin(theta_1)
        kpar=k_0*cos(theta_1)
     case (2) ! |k_0| to |k_1| @ constant theta
        if (scan(ik)%log_scan) then
           kperp=10.d0**(log10(kperp_last)+scan(ik)%diff*it)
           kpar=10.d0**(log10(kpar_last)+scan(ik)%diff2*it)
        else
           kperp=kperp_last+scan(ik)%diff*it
           kpar= kpar_last +scan(ik)%diff2*it
        endif
     case (3) ! kperp scan
        if (scan(ik)%log_scan) then
           kperp=10.d0**(log10(kperp_last)+scan(ik)%diff*it)
        else
           kperp=kperp_last+scan(ik)%diff*it
        endif
     case (4) ! kpar scan
        if (scan(ik)%log_scan) then
           kpar=10.d0**(log10(kpar_last)+scan(ik)%diff*it)
        else
           kpar=kpar_last+scan(ik)%diff*it
        endif
     end select

     if (scan(ik)%type_s.ne.4) then

       ! Scan types with varying kperp require a re-call of split_processes:
        call determine_nmax
        call split_processes
        if(.NOT.(sproc.EQ.0)) call determine_bessel_array

     endif

     call mpi_barrier(mpi_comm_world,ierror)

     if (proc0) write(*,'(a,es14.4,a,es14.4)')'kperp: ',kperp,' kpar: ',kpar

	! Check if all jumps are set to .false.:
	alljump=.FALSE.
	do in = 1,nroots
		alljump=alljump.OR.jump(in)
	enddo

	if (alljump.EQV..FALSE.) call alps_error(9)

     do in = 1,nroots
        !Search for new roots

        if (jump(in)) then

           omega=wroots(in)

           call secant(omega)

           wroots(in)=omega

           call mpi_bcast(wroots(in), 1, &
                MPI_DOUBLE_COMPLEX, 0, MPI_COMM_WORLD, ierror)

           tmp = disp(omega)

           call mpi_barrier(mpi_comm_world,ierror)


           ! Eigenfunctions and heating rates:
           ! only call on wavevector steps that will be output:
           if (mod(it,scan(ik)%n_res)==0) then

              if ((scan(ik)%eigen_s).or.((scan(ik)%heat_s))) then

                 call calc_eigen(omega,ef,bf,Us,ds,Ps,scan(ik)%eigen_s,scan(ik)%heat_s)

                 !reassign omega:
                 omega=wroots(in)

              endif
           endif
           call mpi_barrier(mpi_comm_world,ierror)

           !Output and check for root jumps and NaNs:
           if (proc0) then

              if(isnancheck(real(omega))) then
              	  omega=cmplx(0.d0,0.d0,kind(1.d0));jump(in)=.false.
              endif
!
              do imm=1,in-1
                 if (abs(wroots(in)-wroots(imm)).lt.D_gap) then
                    write(*,'(a,6es14.4)')'Root too close!',&
                         wroots(in),wroots(imm),&
                         real(wroots(in))-real(wroots(imm)), &
                         aimag(wroots(in))-aimag(wroots(imm))
                    wroots(in)=cmplx(0.d0,0.d0);jump(in)=.false.
                 endif
              enddo

              if (mod(it,scan(ik)%n_res)==0) then
                 open(unit=scan_unit(in),file=trim(scanName(in)),status='old',position='append')
                 write(scan_unit(in),'(4es14.4)') &
                      kperp,kpar,wroots(in)
                 close(scan_unit(in))

                 if (scan(ik)%eigen_s) then
                    open(unit=eigen_unit(in),file=trim(eigenName(in)),status='old',position='append')
                    write(eigen_unit(in),trim(fmt_eigen)) &
                         kperp,kpar,wroots(in),ef,bf,Us,ds
                    close(eigen_unit(in))
                 endif

                 if (scan(ik)%heat_s) then
                    open(unit=heat_unit(in),file=trim(heatName(in)),status='old',position='append')
                    write(heat_unit(in),trim(fmt_heat)) &
                         kperp,kpar,wroots(in),Ps
                    close(heat_unit(in))
                 endif

              endif
           endif
           call mpi_bcast(jump(in),1,MPI_LOGICAL,0,MPI_COMM_WORLD, ierror)

        end if
        call mpi_barrier(mpi_comm_world,ierror)

     enddo
  enddo

  if (proc0) then
     deallocate(scan_unit)
     deallocate(scanName)
  endif

end subroutine om_scan




subroutine calc_eigen(omega,electric,magnetic,vmean,ds,Ps,eigen_L,heat_L)
  !! This subroutine calculates the relative electric and magnetic field amplitudes, the relative fluctuations in the density and velocity of all species, and the heating rates of the given solution.
  !! It is based on the calc_eigen routine by Greg Howes and Kris Klein.
  use ALPS_var, only : proc0, nspec, ns, qs, wave, chi0, kperp, kpar, vA, current_int
  implicit none

  double complex, intent(in) :: omega
  !! Complex wave frequency \(\omega\).

  double complex, dimension(1:3), intent(out) :: electric
  !! Relative electric field amplitude (eigenfunction).

  double complex, dimension(1:3), intent(out) :: magnetic
  !! Relative magnetic field amplitude (eigenfunction).

  double complex, dimension(1:nspec), intent(out) :: ds
  !! Relative density-fluctuation amplitude (eigenfunction).

  double complex, dimension(1:3,1:nspec), intent(out) :: vmean
  !! Relative velocity-fluctuation amplitude (eigenfunction).

  double precision, dimension(1:nspec), intent(out) :: Ps
  !! Relative heating rate of a given species.

  logical, intent(in) :: eigen_L
  !! Check whether eigenfunction calculation is requested.

  logical, intent(in) :: heat_L
  !! Check whether eigenfunction calculation is requested.

  integer :: ii
  !! Index to loop over tensor elements.

  integer :: j
  !! Index to loop over tensor elements.

  integer :: jj
  !! Index to loop over species.

  double complex :: temp1
  !! Storage variable for real part of frequency and evaluated dispersion tensor.

  double complex, dimension(nspec,3,3) :: chia
  !! Anti-Hermitian part of the dispersion tensor.

  double complex, dimension(3,3) :: chih
  !! Hermitian part of the dispersion tensor.

  double complex, dimension(3,3) :: chihold
  !! Storage variable for the Hermitian part of the dispersion tensor.

  double complex, dimension(3,3) :: dchih
  !! Derivative of the Hermitian part of the dispersion tensor.

  double complex, dimension(nspec,3) :: term
  !! Tensor product in heating-rate calculation.

  double complex, dimension(3) :: term1
  !! Tensor product in heating-rate calculation.

  double precision :: ewave
  !! Normalised wave energy.


  if (proc0) then

     !The electric and magnetic fields are needed for the heating
     !rate calculation; thus, we always calculate them
        electric(1) = cmplx(1.d0,0.d0,kind(1.d0))
        electric(3)=-electric(1)*(wave(2,1)*wave(3,2)-wave(3,1)*wave(2,2))
        electric(3)= electric(3)/(wave(2,3)*wave(3,2)-wave(3,3)*wave(2,2))
        electric(2) = -electric(3)*wave(3,3) - electric(1)*wave(3,1)
        electric(2) = electric(2)/wave(3,2)

        !Calculate Magnetic Fields, normalized to E_x:
        magnetic(1) = -1.d0* kpar*electric(2)/(omega*vA)
        magnetic(2) = -1.d0* (kperp*electric(3) - kpar*electric(1))/(omega*vA)
        magnetic(3) = kperp*electric(2)/(omega*vA)


        if (eigen_L) then

        ! Calculate relative velocity fluctuations:
        vmean(:,:)=0.d0
        do j=1,3!x,y,z
           do jj = 1,nspec !Species velocity fluctuations
              vmean(j,jj) = -(vA**2.d0/(qs(jj)*ns(jj)))*&
                   cmplx(0.d0,1.d0,kind(1.d0))*&
                   omega*sum(electric(:)*chi0(jj,j,:))

           enddo
        enddo

        ! Calculate relative density fluctuations:
        do jj=1,nspec
           ds(jj) = (vmean(1,jj)*kperp+vmean(3,jj)*kpar)/&
                (omega-kpar * current_int(jj)/(ns(jj)*qs(jj)))

           !TO-DO:
           !add in correct effects of drift on density fluctuation
           !e.g. omega-kpar V_0
           !with a physically meaningful V_0 used.
           !ds(jj) = 0.d0
           !ds(jj) = (vmean(1,jj)*kperp+vmean(3,jj)*kpar)/&
           !     (omega)
        enddo
     endif
  endif



if (heat_L) then

   ! Calculate component heating-rate:
   temp1 = cmplx(real(omega),0.d0,kind(1.d0))
   !temp1 = omega
   temp1 = disp(temp1)

   if (proc0) then

      do ii = 1, 3 !tensor index
         do j = 1, 3 !tensor index
            do jj = 1, nspec !species index
               chia(jj,ii,j) = -0.5d0*cmplx(0.d0,1.d0)* &
                    (chi0(jj,ii,j) - conjg(chi0(jj,j,ii)))
            enddo
            chihold(ii,j) = 0.5*(sum(chi0(:,ii,j)) + &
                 sum(conjg(chi0(:,j,ii))))
         enddo
      enddo

      term(:,:)=0.d0
      term1(:)=0.d0
      do ii = 1, 3
         do jj = 1, nspec
            term(jj,ii) = sum(conjg(electric(:))*chia(jj,:,ii))
         enddo
      enddo

      Ps = 0.d0
      do jj = 1, nspec
         Ps(jj) = sum(term(jj,:)*electric(:))
      enddo

   endif

   temp1 = disp(cmplx(real(omega*1.000001d0),0.d0,kind(1.d0)))

   if (proc0) then
      do ii = 1, 3
         do j = 1, 3
            chih(ii,j) = 0.5d0*(sum(chi0(:,ii,j)) + &
                 sum(conjg(chi0(:,j,ii))))
            dchih(ii,j)=(1.000001d0*chih(ii,j)-chihold(ii,j))/0.000001d0
         enddo
      enddo

      ewave = 0.d0
      do ii = 1, 3
         term1(ii) = sum(conjg(electric(:))*dchih(:,ii))
      enddo

      ewave = sum(term1(:)*electric(:)) + sum(magnetic(:)*conjg(magnetic(:)))

      Ps = Ps/ewave
   endif

endif

end subroutine calc_eigen




subroutine om_double_scan
  !! This subroutine scans along a prescribed plane in wavevector space to map out \(\omega\) in this space. It is required that n_scan=2.
  use ALPS_var, only : proc0, nroots, runname, ierror, wroots, scan, sproc
  use ALPS_var, only : kperp,kpar,kperp_last,kpar_last, D_gap
  use ALPS_var, only : ierror, nspec
  use ALPS_io,  only : get_unused_unit, alps_error, isnancheck
  use mpi
  implicit none


  integer :: it
  !! Index to loop over steps of first scan.

  integer :: nt
  !! Number of scans for first scan.

  integer :: it2
  !! Index to loop over steps of second scan.

  integer :: nt2
  !! Number of scans for second scan.

  integer :: in
  !! Number of roots.

  character(500), dimension(:), allocatable :: scanName
  !! Output file name for scan.

  character(500), dimension(:), allocatable :: heatName
  !! Output file name for heating-rate calculation.

  character(500), dimension(:), allocatable :: eigenName
  !! Output file name for eigenfunction calculation.

  character(6) :: scan_ID
  !! ID tags for scan types for first scan.

  character(5) :: scan_ID2
  !! ID tags for scan types for second scan.

  double precision :: theta_0
  !! Wavevector angle of previous step

  double precision :: theta_1
  !! Wavevector angle.

  double precision :: k_0
  !! Wavevector magnitude of previous step.

  double precision :: theta_i
  !! Wavevector angle of step i.

  double precision :: k_i
  !! Wavevector magnitude of step i.

  double precision :: kperpi
  !! Perpendicular wavenumber of step i.

  double precision :: kpari
  !! Parallel wavenumber of step i.

  double complex, dimension(:), allocatable :: om_tmp
  !! Storage variable for frequency omega. (1:nroots)

  double complex :: omega
  !! Complex wave frequency \(\omega\).

  integer, dimension(:), allocatable :: scan_unit
  !! File unit for scan output. (1:nroots)

  integer, dimension(:), allocatable :: heat_unit
  !! File unit for heating-rate output. (1:nroots)

  integer, dimension(:), allocatable :: eigen_unit
  !! File unit for eigenfunction output. (1:nroots)

  integer :: imm
  !! Index to check for root jumps.

  logical, dimension(:),allocatable :: jump
  !! Check whether a jump should be applied. (1:nroots)

  logical :: alljump
  !! Check whether any root has jumped.

  double complex :: tmp
  !! Storage variable for determinant of dispersion tensor.

  double complex, dimension(1:3) :: ef
  !! Relative electric field amplitude (eigenfunction).

  double complex, dimension(1:3) :: bf
  !! Relative magnetic field amplitude (eigenfunction).

  double complex, dimension(1:nspec) :: ds
  !! Relative density-fluctuation amplitude (eigenfunction).

  double complex, dimension(1:3,1:nspec) :: Us
  !! Relative velocity-fluctuation amplitude (eigenfunction).

  double precision, dimension(1:nspec) :: Ps
  !! Relative heating rate of a given species.

  character (50) :: fmt_eigen
  !! Format string for eigenfunction output.

  character (50) :: fmt_heat
  !! Format string for heating-rate output.

  allocate(jump(1:nroots)); jump=.true.

  if (scan(1)%type_s==scan(2)%type_s) then
     call alps_error(5)
  endif

  if ((scan(1)%type_s==0).or.(scan(2)%type_s==0)) then
     call alps_error(6)
  endif

  allocate(om_tmp(nroots))

  if (proc0) then
     allocate(scan_unit(nroots))
     allocate(scanName(nroots))

     !Name of first scan:
     select case(scan(1)%type_s)
     case (0) ! k_0 to k_1
        write(scan_ID,'(a)')'k1_k2_'
     case (1) ! theta_0 to theta_1
        write(scan_ID,'(a)')'theta_'
     case (2) ! |k_0| to |k_1| @ constant theta
        write(scan_ID,'(a)')'kcstq_'
     case (3) ! kperp scan
        write(scan_ID,'(a)')'kperp_'
     case (4) ! kpar scan
        write(scan_ID,'(a)')'kpara_'
     end select

     !Name of second scan:
     select case(scan(2)%type_s)
     case (0) !k_0 to k_1
        write(scan_ID2,'(a)')'k1_k2'
     case (1) !theta_0 to theta_1
        write(scan_ID2,'(a)')'theta'
     case (2) ! |k_0| to |k_1| @ constant theta
        write(scan_ID2,'(a)')'kcstq'
     case (3) !kperp scan
        write(scan_ID2,'(a)')'kperp'
     case (4) !kpar scan
        write(scan_ID2,'(a)')'kpara'
     end select

     if (scan(1)%eigen_s) then
        write(fmt_eigen,'(a,i0,a)') '(4es14.4,12es14.4,',nspec*8,'es14.4)'
        allocate(eigen_unit(nroots))
        allocate(eigenName(nroots))
     endif
     if (scan(1)%heat_s) then
        write(fmt_heat,'(a,i0,a)') '(4es14.4,',nspec,'es14.4)'
        allocate(heat_unit(nroots))
        allocate(heatName(nroots))
     endif

     do in=1,nroots
        write(scanName(in),'(6a,i0)')&
             'solution/',trim(runname),'.scan_',scan_ID,scan_ID2,'.root_',in
        write(*,'(2a)')' => ',trim(scanName(in))
        call get_unused_unit(scan_unit(in))
        open(unit=scan_unit(in),file=trim(scanName(in)),status='replace')
        close(scan_unit(in))

     enddo

  endif

  if ((scan(1)%eigen_s).or.(scan(1)%heat_s)) then

     do in=1,nroots
        omega=wroots(in)
        tmp = disp(omega)

        call calc_eigen(omega,ef,bf,Us,ds,Ps,scan(1)%eigen_s,scan(1)%heat_s)

        !reassign omega:
        omega=wroots(in)

        call mpi_barrier(mpi_comm_world,ierror)

        if (proc0) then
           if (scan(1)%eigen_s) then
              write(eigenName(in),'(6a,i0)')&
                   'solution/',trim(runname),'.eigen_',scan_ID,scan_ID2,'.root_',in
              write(*,'(2a)')' => ',trim(eigenName(in))
              call get_unused_unit(eigen_unit(in))
              open(unit=eigen_unit(in),file=trim(eigenName(in)),status='replace')
              close(eigen_unit(in))
           endif

           if (scan(1)%heat_s) then
              write(heatName(in),'(6a,i0)')&
                   'solution/',trim(runname),'.heat_',scan_ID,scan_ID2,'.root_',in
              write(*,'(2a)')' => ',trim(heatName(in))
              call get_unused_unit(heat_unit(in))
              open(unit=heat_unit(in),file=trim(heatName(in)),status='replace')
              close(heat_unit(in))
           endif
        endif

     enddo

  endif



  nt = scan(1)%n_out*scan(1)%n_res
  nt2 = scan(2)%n_out*scan(2)%n_res

  kperp_last=kperp;kpar_last=kpar

  theta_0=atan(kperp_last/kpar_last)
  k_0=sqrt(kperp_last**2+kpar_last**2)

  do it = 0, nt
     ! Scan through wavevector space:
     select case(scan(1)%type_s)
     case (0) ! k_0 to k_1
        if (scan(1)%log_scan) then
           kperp=10.d0**(log10(kperp_last)+scan(1)%diff*it)
           kpar=10.d0**(log10(kpar_last)+scan(1)%diff2*it)
        else
           kperp=kperp_last+scan(1)%diff*it
           kpar= kpar_last +scan(1)%diff2*it
        endif
     case (1) ! theta_0 to theta_1
        if (scan(1)%log_scan) then
           theta_1=10.d0**(log10(theta_0)+scan(1)%diff*it)
        else
           theta_1=theta_0+scan(1)%diff*it
        endif
        kperp=k_0*sin(theta_1)
        kpar=k_0*cos(theta_1)
     case (2) ! |k_0| to |k_1| @ constant theta
        if (scan(1)%log_scan) then
           kperp=10.d0**(log10(kperp_last)+scan(1)%diff*it)
           kpar=10.d0**(log10(kpar_last)+scan(1)%diff2*it)
        else
           kperp=kperp_last+scan(1)%diff*it
           kpar= kpar_last +scan(1)%diff2*it
        endif
     case (3) ! kperp scan
        if (scan(1)%log_scan) then
           kperp=10.d0**(log10(kperp_last)+scan(1)%diff*it)
        else
           kperp=kperp_last+scan(1)%diff*it
        endif
     case (4) ! kpar scan
        if (scan(1)%log_scan) then
           kpar=10.d0**(log10(kpar_last)+scan(1)%diff*it)
        else
           kpar=kpar_last+scan(1)%diff*it
        endif
     end select

     if (scan(1)%type_s.ne.4) then

        ! Scan types with varying kperp require a re-call of split_processes:
        call determine_nmax
        call split_processes
        if(.NOT.(sproc.EQ.0)) call determine_bessel_array

     endif

     call mpi_barrier(mpi_comm_world,ierror)

     if (proc0) write(*,'(a,es14.4,a,es14.4)')'kperp: ',kperp,' kpar: ',kpar

     ! Check if all jumps are set to .false.:
     alljump=.FALSE.
     do in = 1,nroots
        alljump=alljump.OR.jump(in)
     enddo

     if (alljump.EQV..FALSE.) call alps_error(9)

     !Save roots before starting second parameter scan.
     om_tmp=wroots

     ! Second scan:
     do it2 = 0, nt2

        ! Scan through wavevector space:
        !if (it2==1) then
        if (it2==0) then
           kperpi=kperp; kpari=kpar
           kperpi=kperp; kpari=kpar
           theta_i=atan(kperpi/kpari)
           k_i=sqrt(kperpi**2+kpari**2)
           wroots=om_tmp
        endif
        select case(scan(2)%type_s)
        case (0) ! k_0 to k_1
           if (scan(2)%log_scan) then
              kperp=10.d0**(log10(kperpi)+scan(2)%diff*it2)
              kpar=10.d0**(log10(kpari)+scan(2)%diff2*it2)
           else
              kperp=kperpi+scan(2)%diff*it2
              kpar= kpari +scan(2)%diff2*it2
           endif
        case (1) ! theta_i to theta_1
           if (scan(2)%log_scan) then
              theta_1=10.d0**(log10(theta_i)+scan(2)%diff*it2)
           else
              theta_1=theta_i+scan(2)%diff*it2
           endif
           kperp=k_i*sin(theta_1)
           kpar=k_i*cos(theta_1)
        case (2) ! |k_0| to |k_1| @ constant theta
           if (scan(2)%log_scan) then
              kperp=10.d0**(log10(kperpi)+scan(2)%diff*it2)
              kpar=10.d0**(log10(kpari)+scan(2)%diff2*it2)
           else
              kperp=kperpi+scan(2)%diff*it2
              kpar= kpari +scan(2)%diff2*it2
           endif
        case (3) ! kperp scan
           if (scan(2)%log_scan) then
              kperp=10.d0**(log10(kperpi)+scan(2)%diff*it2)
           else
              kperp=kperpi+scan(2)%diff*it2
           endif
        case (4) ! kpar scan
           if (scan(2)%log_scan) then
              kpar=10.d0**(log10(kpari)+scan(2)%diff*it2)
           else
              kpar=kpari+scan(2)%diff*it2
           endif
        end select

        if (scan(2)%type_s.ne.4) then
           ! Scan types with varying kperp require a re-call of split_processes:
           call determine_nmax
           call split_processes
           if(.NOT.(sproc.EQ.0)) call determine_bessel_array
        endif

        call mpi_barrier(mpi_comm_world,ierror)

        if (proc0) write(*,'(a,es14.4,a,es14.4)')'kperp: ',kperp,' kpar: ',kpar

          do in = 1,nroots
             !Search for new roots:
             if (jump(in)) then

                omega=wroots(in)

                call secant(omega)

                wroots(in)=omega

                call mpi_bcast(wroots(in), 1, &
                     MPI_DOUBLE_COMPLEX, 0, MPI_COMM_WORLD, ierror)

                tmp = disp(omega)

                call mpi_barrier(mpi_comm_world,ierror)

           ! Eigenfunctions and heating rates:
           ! only call on wavevector steps that will be output:
           if ((mod(it,scan(1)%n_res)==0).and.(mod(it2,scan(2)%n_res)==0)) then

              if ((scan(1)%eigen_s).or.((scan(1)%heat_s))) then

                 call calc_eigen(omega,ef,bf,Us,ds,Ps,scan(1)%eigen_s,scan(1)%heat_s)

                 !reassign omega:
                 omega=wroots(in)

              endif
           endif
           call mpi_barrier(mpi_comm_world,ierror)

           ! Output:
           if (proc0) then

              if(isnancheck(real(omega))) then
              	  omega=cmplx(0.d0,0.d0,kind(1.d0));jump(in)=.false.
              endif

              ! infty Check:
              if (abs(tmp) .gt. 1.d100) then
                 omega=cmplx(0.d0,0.d0);jump(in)=.false.
              endif

              do imm=1,in-1
                 if (abs(wroots(in)-wroots(imm)).lt.D_gap) then
                    write(*,'(a,6es14.4)')'Root too close!',&
                         wroots(in),wroots(imm),&
                         real(wroots(in))-real(wroots(imm)), &
                         aimag(wroots(in))-aimag(wroots(imm))
                    wroots(in)=cmplx(0.d0,0.d0);jump(in)=.false.
                 endif
              enddo


              if ((mod(it,scan(1)%n_res)==0).and.((mod(it2,scan(2)%n_res)==0))) then
                 open(unit=scan_unit(in),file=trim(scanName(in)),&
                      status='old',position='append')
                 write(scan_unit(in),'(4es14.4)') &
                      kperp,kpar,wroots(in)
                 close(scan_unit(in))

                 if (scan(1)%eigen_s) then
                    open(unit=eigen_unit(in),file=trim(eigenName(in)),status='old',position='append')
                    write(eigen_unit(in),trim(fmt_eigen)) &
                         kperp,kpar,wroots(in),ef,bf,Us,ds
                    close(eigen_unit(in))
                 endif

                 if (scan(1)%heat_s) then
                    open(unit=heat_unit(in),file=trim(heatName(in)),status='old',position='append')
                    write(heat_unit(in),trim(fmt_heat)) &
                         kperp,kpar,wroots(in),Ps
                    close(heat_unit(in))
                 endif

              endif

           endif

           call mpi_bcast(jump(in),1,MPI_LOGICAL,0,MPI_COMM_WORLD, ierror)

        endif

        call mpi_barrier(mpi_comm_world,ierror)


     enddo

  enddo

  if ((proc0).and.(mod(it,scan(1)%n_res)==0)) then
     do in = 1,nroots
        open(unit=scan_unit(in),file=trim(scanName(in)),&
             status='old',position='append')
        write(scan_unit(in),*)
        close(scan_unit(in))

        if (scan(1)%eigen_s) then
           open(unit=eigen_unit(in),file=trim(eigenName(in)),status='old',position='append')
           write(eigen_unit(in),*)
           close(eigen_unit(in))
        endif
        if (scan(1)%heat_s) then
           open(unit=heat_unit(in),file=trim(heatName(in)),status='old',position='append')
           write(heat_unit(in),*)
           close(heat_unit(in))
        endif

     enddo
  endif



  kperp=kperp_last
  kpar=kpar_last

enddo

if (proc0) then
   deallocate(scan_unit)
   deallocate(scanName)
endif

deallocate(om_tmp)

end subroutine om_double_scan



subroutine map_search
  !! This subroutine calculates the map of the determinant of the dispersion tensor in complex frequency space.
  use ALPS_var, only : ierror
  use ALPS_var, only : omi, omf, gami, gamf, loggridw, loggridg, determine_minima
  use ALPS_var, only : ni, nr, proc0, ms, ns, qs, runname, nspec
  use ALPS_var, only : writeOut, kperp, kpar, wroots, numroots, nroots, nroots_max
  use ALPS_io,  only : get_unused_unit
  use mpi
  implicit none

  double precision :: dr
  !! Infinitesimal spacing in real part of frequency.

  double precision :: di
  !! Infinitesimal spacing in imaginar part of frequency.

  double precision :: wr
  !! Real part of frequency.

  double precision :: wi
  !! Imaginary part of frequency.

  double precision, dimension(:,:), pointer :: val
  !! Real part of determinant of dispersion tensor. (1:nr,1:ni)

  double complex, dimension(:,:), allocatable :: cal
  !! Value of determinant of dispersion tensor. (1:nr,1:ni)

  double complex, dimension(:,:), allocatable :: om
  !! Array of complex wave frequency \(\omega\). (1:nr,1:ni)

  double complex :: omega
  !! Complex wave frequency \(\omega\).

  integer :: ir
  !! Index to loop over real part of frequency.

  integer :: ii
  !! Index to loop over imaginary part of frequency.

  integer :: is
  !! Index to loop over species.

  integer :: iw
  !! Index to loop over roots.

  character(500) :: mapName
  !! File name for output of map.

  integer, dimension(1:2,1:numroots) :: iroots
  !! Indices of roots in local minimum search.

  integer :: unit_map
  !! Unit for map output.

  double precision :: tmp
  !! Storage variable for determinant of dispersion tensor.




  if (writeOut .and. proc0.and. .true.) then
     write(*,'(a)')'-=-=-=-=-=-=-=-=-=-'
     write(*,'(a)')      'Global Plasma Parameters:'
     write(*,'(a,es12.3)')' k_perp d_p   = ',kperp
     write(*,'(a,es12.3)')' k_par  d_p   = ',kpar
     do is = 1, nspec
        write(*,'(a)')'-=-=-=-=-=-=-=-=-=-'
        write(*,'(a,i3)')      'Parameters for species',is
        write(*,'(a,es12.3)')' m_s/m_m =        ',ms(is)
        write(*,'(a,es12.3)')' q_s/q_p =        ',qs(is)
        write(*,'(a,es12.3)')' n_s/n_p =        ',ns(is)
     enddo
     write(*,'(a)')'-=-=-=-=-=-=-=-=-=-'
     write(*,'(a)')'Searching over:'
     write(*,'(a,es12.3,a,es12.3,a)')' om  in [',omi,',',omf,']'
     write(*,'(a,es12.3,a,es12.3,a)')' gam in [',gami,',',gamf,']'
     write(*,'(a)')'-=-=-=-=-=-=-=-=-=-'
  endif

  ! Allocate array for map values:
  ! Value of dispersion relation on frequency grid:
  allocate(cal(nr,ni)); cal(:,:)=cmplx(0.d0,0.d0,kind(1.d0))
  ! magnitude of cal:
  allocate(val(nr,ni)); val(:,:)=0.d0
  ! Array of complex frequencies:
  allocate(om(nr,ni)); om(:,:)=cmplx(0.d0,0.d0,kind(1.d0))

  ! Determine spacing in complex omega space (Normal or log):
  dr=omf-omi
  di=gamf-gami
  if (nr.GT.1) dr=(omf-omi)/(1.d0*(nr-1))
  if (ni.GT.1) di=(gamf-gami)/(1.d0*(ni-1))

  if (proc0) then
     write(mapName,'(3a)') 'solution/',trim(runname),'.map'
     call get_unused_unit(unit_map)
     open(unit=unit_map,file=trim(mapName),status='replace')
     close(unit_map)
  endif

  ! Scan over complex frequency space and calculate dispersion relation:
  do ir=1,nr
     if (loggridw) then
        wr=omi
        if (nr.GT.1) wr=omi*((omf/omi)**((1.d0*(ir-1))/(1.d0*(nr-1))))
     else
        wr=omi+dr*(1.d0*(ir-1))
     endif
     if (proc0.and.writeOut)&
          write(*,'(a,es11.4)')' omega_real = ',wr
     do ii=1,ni
        if (loggridg) then
		   wi=gami
           if(ni.GT.1) wi=gami*((gamf/gami)**((1.d0*(ii-1))/(1.d0*(ni-1))))
        else
           wi=gami+di*(1.d0*(ii-1))
        endif

        omega=cmplx(wr,wi,kind(1.d0))
        om(ir,ii)=omega
        cal(ir,ii)=disp(omega)
        val(ir,ii)=abs(cal(ir,ii))

        if (proc0) then
           tmp=cal(ir,ii)
           val(ir,ii)=log10(val(ir,ii))
           !NaN Check:
           if (aimag(cal(ir,ii)).ne.0.d0) then
              if (.not.(tmp .ne. cal(ir,ii)) ) then
                 cal(ir,ii)=999999.d0;val(ir,ii)=999999.d0
              endif
           else
              if ((tmp .ne. cal(ir,ii)) ) then
                 cal(ir,ii)=999999.d0;val(ir,ii)=999999.d0
              endif
           endif

           !infty Check:
           if (abs(tmp) .gt. 1.d100) then
              cal(ir,ii)=899999.d0;val(ir,ii)=899999.d0
           endif

           open(unit=unit_map,file=trim(mapName),status='old',position='append')
           write(unit_map,'(5es14.6)') &
                om(ir,ii),val(ir,ii),cal(ir,ii)
           close(unit_map)

        endif
     enddo

     if (proc0) then
        open(unit=unit_map,file=trim(mapName),status='old',position='append')
        write(unit_map,*)
        close(unit_map)
     endif
  enddo

  if(determine_minima) then
    !Search for Local Minima in Dispersion Surface:
    if (proc0.and.(nr.gt.1).and.(ni.gt.1)) then
      write(*,*)'finding minima'
      call find_minima(val,numroots,iroots,nroots_max)
      if (writeOut) &
           write(*,'(i2,a)')nroots_max,'  possible local minimum found'
      do iw=1,nroots_max
         wroots(iw)=om(iroots(1,iw),iroots(2,iw))
         if (writeOut) then
            write(*,'(a,i4,a,i4)')'ir = ',iroots(1,iw),'    ii = ',iroots(2,iw)
            write(*,'(4es14.4)') wroots(iw) ,cal(iroots(1,iw),iroots(2,iw))
         endif
      enddo

      nroots=min(nroots,nroots_max)

   endif

    call mpi_bcast(nroots, 1, MPI_INTEGER, 0, MPI_COMM_WORLD, ierror)
    call mpi_bcast(wroots(:), size(wroots(:)), MPI_DOUBLE_COMPLEX, 0, MPI_COMM_WORLD, ierror)

    call refine_guess

    call mpi_bcast(nroots, 1, MPI_INTEGER, 0, MPI_COMM_WORLD, ierror)
    call mpi_bcast(wroots(:), size(wroots(:)), MPI_DOUBLE_COMPLEX, 0, MPI_COMM_WORLD, ierror)

 endif

end subroutine map_search




subroutine refine_guess
  !! This subroutine refines the guess at the starting point of the search for solutions to the dispersion relation when scanning. It is also used by [[map_search]] to identify the roots on the map.
  use alps_var, only : wroots, nroots, writeOut, proc0
  use alps_var, only : ierror,runname
  use alps_io,  only : get_unused_unit
  use mpi
  implicit none


  double complex :: omega
  !! Complex wave frequency \(\omega\).

  character(500) :: mapName
  !! File name for output of map.

  double complex :: tmpDisp
  !! Storage variable for determinant of the dispersion tensor.

  integer :: iw
  !! Index to loop over roots.

  integer :: unit_refine
  !! File unit for refinement output.



  if (proc0) then
     if (writeOut) write(*,'(a)')' Refining Roots:'
     write(mapName,'(3a)') 'solution/',trim(runname),'.roots'
     call get_unused_unit(unit_refine)
     open(unit=unit_refine,file=trim(mapName),status='replace')
  endif


  do iw=1,nroots
     if (proc0.and.writeOut) write(*,'(a,i0)')'Root ',iw
     call mpi_barrier(mpi_comm_world,ierror)
     omega=wroots(iw)

     call secant(omega)

     wroots(iw)=omega

     tmpDisp=disp(wroots(iw))
     if (proc0.and.(abs(tmpDisp).NE.0.d0)) then
        write(unit_refine,'(i4,5es14.4)') iw,wroots(iw),log10(abs(tmpDisp)),tmpDisp
        write(*,'(i4,5es14.4)') iw,wroots(iw),log10(abs(tmpDisp)),tmpDisp
 !       if (writeOut) write(*,'(a,2es14.4,a,2es14.4)')'D(',wroots(iw),')= ',tmpDisp
     endif

  enddo
  if (proc0) close(unit_refine)
end subroutine refine_guess



subroutine find_minima(val,numroots,iroots,nroots)
     !! This subroutine identifies the minima of the coarse map grid. It is called by [[map_search]].
     !! The code is based on a routine by Greg Howes, 2006.
     use ALPS_var, only : ni,nr
     implicit none

     double precision, dimension(:,:), pointer, intent(in) :: val
     !! Array of determinant of the dispersion tensor.

     integer, intent(in) :: numroots
     !! Number of roots.

     integer, dimension(1:2,1:numroots), intent(out) :: iroots
     !! Indices of roots.

     integer, intent(out) :: nroots
     !! Number of roots found.

     integer :: ir
     !! Index to loop over real parts of frequency.

     integer :: ii
     !! Index to loop over imaginary parts of frequency.


     iroots=0
     nroots=0
     do ii=ni,1,-1
        do ir=1,nr
           !ir = 0
           if (ir ==1) then
              if (val(ir,ii) .lt. val(ir+1,ii)) then
                 if (ii==1) then
                    if (val(ir,ii) .lt. val(ir,ii+1)) then
                       nroots=nroots+1
                       iroots(1,nroots)=ir
                       iroots(2,nroots)=ii
                    endif
                 elseif (ii==ni) then
                    if (val(ir,ii) .lt. val(ir,ii-1)) then
                       nroots=nroots+1
                       iroots(1,nroots)=ir
                       iroots(2,nroots)=ii
                    endif
                 else
                    if (val(ir,ii) .lt. val(ir,ii-1) .and.  &
                         val(ir,ii) .lt. val(ir,ii+1))then
                       nroots=nroots+1
                       iroots(1,nroots)=ir
                       iroots(2,nroots)=ii
                    endif
                 endif
              endif
           elseif (ir == nr) then
              if (val(ir,ii) .lt. val(ir-1,ii)) then
                 if (ii==1) then
                    if (val(ir,ii) .lt. val(ir,ii+1)) then
                       nroots=nroots+1
                       iroots(1,nroots)=ir
                       iroots(2,nroots)=ii
                    endif
                 elseif (ii==ni) then
                    if (val(ir,ii) .lt. val(ir,ii-1)) then
                       nroots=nroots+1
                       iroots(1,nroots)=ir
                       iroots(2,nroots)=ii
                    endif
                 else
                    if (val(ir,ii) .lt. val(ir,ii-1) .and.  &
                         val(ir,ii) .lt. val(ir,ii+1))then
                       nroots=nroots+1
                       iroots(1,nroots)=ir
                       iroots(2,nroots)=ii
                    endif
                 endif
              endif
           else
              if (val(ir,ii) .lt. val(ir-1,ii) .and.  &
                   val(ir,ii) .lt. val(ir+1,ii))then
                 if (ii==1) then
                    if (val(ir,ii) .lt. val(ir,ii+1)) then
                       nroots=nroots+1
                       iroots(1,nroots)=ir
                       iroots(2,nroots)=ii
                    endif
                 elseif (ii==ni) then
                    if (val(ir,ii) .lt. val(ir,ii-1)) then
                       nroots=nroots+1
                       iroots(1,nroots)=ir
                       iroots(2,nroots)=ii
                    endif
                 else
                    if (val(ir,ii) .lt. val(ir,ii-1) .and.  &
                         val(ir,ii) .lt. val(ir,ii+1))then
                       nroots=nroots+1
                       iroots(1,nroots)=ir
                       iroots(2,nroots)=ii
                    endif
                 endif
              endif
           endif
        enddo
     enddo

     write(*,*) nroots

   end subroutine find_minima




subroutine determine_nmax()
!! This subroutine determines the maximum required order of the Bessel functions in Eq. (2.9) of the code paper.
use ALPS_var, only : pp, kperp, qs, Bessel_zero, nmax, ierror
use ALPS_var, only : proc0, nperp, nspec, writeOut, nproc, usebM
use ALPS_fns_rel, only : BESSJ
use mpi
implicit none

integer :: is
!! Index of particle species.

integer :: nn
!! Order of Bessel function.

double precision :: bessel
!! Bessel function.

double precision :: besselprev
!! Storage variable for Bessel function.

double precision :: besselmax
!! Check variable for largest Bessel function.

double precision :: z
!! Argument of the Bessel function.

integer :: iperp
!! Index for loop over perpendicular momentum.

integer :: ipar
!! Index for loop over parallel momentum.

integer :: max_procs
!! Maximum number of processes.

logical :: maximum
!! Check whether a maximum has been found.

logical :: modified_nmax
!! Check whether additional n are available due to number of processes.


ipar = 1

max_procs=nspec
do is = 1, nspec

  if (usebM(is)) then
         nmax(is)=1

    else

    nn = 0
    besselmax = 10.d0

    do while (besselmax.GT.Bessel_zero)
       nn = nn + 1

       iperp = 0
       maximum = .FALSE.
       bessel = 0.d0

       if (nn.GT.1000) write (*,*) 'Bessel-function n is greater than 1000.'

       do while ((iperp .LT. nperp).AND.(.NOT.maximum))

          iperp=iperp+1
          z = kperp * pp(is, iperp, ipar, 1) / abs(qs(is))

          besselprev = bessel
          bessel = BESSJ(nn,z)

          if (bessel .LT. besselprev) maximum = .TRUE.

       enddo

       besselmax = bessel

    enddo

    nmax(is) = nn

    endif

    if (writeOut .and. proc0) &
         write(*,'(a,i0,a,i0,a)') 'Required nMax for species ',is,' : ',nmax(is)

    max_procs=max_procs+nmax(is)

enddo

! If we have too many processes, then allow for additional n's:
! The condition is that max_procs has to be greater or equal (nproc-1):
is=1
modified_nmax=.FALSE.
do while (max_procs.LT.(nproc-1))

  if (usebM(is)) then

  else
    modified_nmax=.TRUE.
	  nmax(is)=nmax(is)+1
  endif

	is=is+1
	max_procs=max_procs+1

  if (is.GT.nspec) is = 1

enddo

if (modified_nmax.AND.proc0.AND.writeOut) then
	write (*,'(a)') "More processes than required. nMax is adjusted."
	do is=1,nspec
	 	write(*,'(a,i0,a,i0,a)') ' Adjusted nMax for Species ',is,' : ',nmax(is)
	enddo
endif

call mpi_barrier(mpi_comm_world,ierror)

end subroutine 	determine_nmax



subroutine split_processes()
!! This subroutine defines the tasks for the individual processes. It uses the number of species and the required orders of the Bessel functions to define the splitting across the MPI processes.
use alps_var, only : nproc, iproc, nmax, nlim
use alps_var, only : nspec, sproc, writeOut, proc0
implicit none

integer :: is
!! Index of particle species.

integer :: max_procs
!! Maximum number of processes.

integer :: ideal_ns_per_proc
!! Ideal number of n's per process.

integer :: proc_per_spec(nspec)
!! Number of processes for each species.

integer :: ideal_splitting(nspec)
!! Ideal number of n's for each process associated with a given species.

integer :: splitting_rest(nspec)
!! Rest of n's after ideal splitting for each process associated with a given species.

integer :: largest_rest
!! Largest rest of splitting.

integer :: largest_spec
!! Index of species with the largest rest of splitting.

integer :: used_procs
!! Number of used processes.

integer :: proc_count
!! Index to count processes.

integer :: prev_proc_count
!! Storage variable for index to count processes.

integer :: local_iproc
!! Local process number (in species field).

integer :: rest_sum
!! Sum over the rests of n's.


max_procs = nspec	! to include the Bessel functions with n = 0 for all species
do is = 1,nspec
	max_procs = max_procs + nmax(is)
enddo

ideal_ns_per_proc = ceiling((1.*max_procs)/(1.*nproc-1.))

used_procs = 0
rest_sum = 0

! Define number of processes for each species:
do is = 1, nspec

	if ((nmax(is)+1).LE.ideal_ns_per_proc) then
		proc_per_spec(is) = 1
	else
  	  proc_per_spec(is) = (nmax(is)+1)/ideal_ns_per_proc ! COULD LEAVE A REST
  endif

    ideal_splitting(is) = (nmax(is)+1)/proc_per_spec(is)  ! is the ideal splitting of species is
	  splitting_rest(is) = modulo((nmax(is)+1),proc_per_spec(is))
	  ! Every process for species is should get as close as possible to this number.
	  ! This is a little bit better than just using ideal_ns_per_proc. The last one will get the rest.

    !  Determine number of remaining processes:
	   used_procs = used_procs + proc_per_spec(is)
     rest_sum = rest_sum + splitting_rest(is)

enddo


if (proc0.AND.writeOut) then
	if(modulo((max_procs + rest_sum + 1),2).EQ.0) then
	 write(*,'(a,i0)')&
     'Ideal Number of Processors: ',max_procs + rest_sum + 1
     else
		write(*,'(a,i0)')&
     'Ideal Number of Processors: ',max_procs + rest_sum
     endif
     write(*,'(a,i0)') '-=-=-=-=-=-=-=-=-=-'
endif

! Determine species with the largest rest of n's:
largest_spec=1
largest_rest=0
do is = 1,nspec
	if (splitting_rest(is).GT.largest_rest) then
		largest_spec = is
		largest_rest = splitting_rest(is)
	endif
enddo

! The rest of processes go to species largest_spec:
 proc_per_spec(largest_spec) = proc_per_spec(largest_spec) + ((nproc-1)-used_procs)
 ideal_splitting(largest_spec) = nint((1.*nmax(largest_spec)+1.)/(1.*proc_per_spec(largest_spec)))


proc_count = 0
prev_proc_count = 0
do is = 1,nspec
	proc_count = proc_count + proc_per_spec(is)

		if ((iproc.LE.proc_count).AND.(iproc.GT.prev_proc_count)) then
			sproc = is
			local_iproc = (iproc - prev_proc_count)

			nlim(1) = (local_iproc - 1) * (ideal_splitting(is))
      nlim(2) = nlim(1) + ideal_splitting(is)-1

      if ((local_iproc.EQ.proc_per_spec(is)).AND.(nlim(1).LE.nmax(is))) nlim(2)=nmax(is)

		endif
	prev_proc_count = proc_count
enddo

  if (writeOut) &
       write(*,'(a,i4,a,i4,a,i4,a,2i4,a)') &
       'Processor ',iproc,' of ',nproc,' ready. Species ',sproc,': n in [', nlim(1:2),']'

end subroutine split_processes





! determine bessel_array (this process only works on one species
subroutine determine_bessel_array()
!! This subroutine determines the array of Bessel functions that is used in the T-tensor of Eq. (2.10) of the code paper.
  use ALPS_var, only : pp, kperp, qs, sproc,bessel_array, nperp, nlim
  use ALPS_io, only : get_unused_unit
  use ALPS_fns_rel, only : BESSJ
  implicit none

  integer :: nn
  !! Order of Bessel function.

  double precision :: z
  !! Argument of the Bessel function.

  integer :: iperp
  !! Index for loop over perpendicular momentum.

  integer :: ipar
  !! Index for loop over parallel momentum.


  ipar = 1

  ! Allocate bessel_array:
  if (allocated(bessel_array)) deallocate(bessel_array)
  allocate(bessel_array(nlim(1)-1:nlim(2)+1,0:nperp)); bessel_array = 0.d0

  ! Fill this array with values:
  do nn = nlim(1)-1, nlim(2)+1
     do iperp = 0, nperp

        z = kperp * pp(sproc, iperp, ipar, 1) / qs(sproc)
        bessel_array(nn,iperp) = BESSJ(nn,z)

        if (nn.EQ.-1) bessel_array(nn,iperp)=-BESSJ(1,z)

     enddo
  enddo

end subroutine determine_bessel_array



end module alps_fns

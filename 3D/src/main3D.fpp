!=================================================================
      PROGRAM MAIN3D
!=================================================================
! GHOST code: Geophysical High Order Suite for Turbulence
!
! Numerically integrates the incompressible HD/MHD/Hall-MHD 
! equations in 3 dimensions with periodic boundary conditions 
! and external forcing. A pseudo-spectral method is used to 
! compute spatial derivatives, while adjustable order 
! Runge-Kutta method is used to evolve the system in the time 
! domain. To compile, you need the FFTW library installed on 
! your system. You should link with the FFTP subroutines
! and use the FFTPLANS and MPIVARS modules (see the file 
! 'fftp_mod.f90').
!
! Notation: index 'i' is 'x' 
!           index 'j' is 'y'
!           index 'k' is 'z'
!
! Conditional compilation options:
!           HD_SOL        builds the hydrodynamic (HD) solver
!           PHD_SOL       builds the HD solver with passive scalar
!           MHD_SOL       builds the MHD solver
!           MHDB_SOL      builds the MHD solver with uniform B_0
!           HMHD_SOL      builds the Hall-MHD solver
!           ROTH_SOL      builds the HD solver in a rotating frame
!           LAHD_SOL      builds the Lagrangian-averaged HD solver
!           CAHD_SOL      builds the Clark-alpha HD solver
!           LHD_SOL       builds the Leray HD solver
!           LAMHD_SOL     builds the Lagrangian-averaged MHD solver
!           EDQNMHD_SOL   builds the EDQNM HD solver
!           EDQNMROTH_SOL builds the EDQNM ROTH solver
!
! 2003 Pablo D. Mininni.
!      Department of Physics, 
!      Facultad de Ciencias Exactas y Naturales.
!      Universidad de Buenos Aires.
!      e-mail: mininni@df.uba.ar
!
! 15 Feb 2007: Main program for all solvers (HD/MHD/HMHD)
! 21 Feb 2007: POSIX and MPI/IO support
! 10 Mar 2007: FFTW-2.x and FFTW-3.x support
! 25 Aug 2009: Hybrid MPI/OpenMP support (D. Rosenberg & P. Mininni)
!
! References:
! Mininni PD, Gomez DO, Mahajan SM; Astrophys. J. 619, 1019 (2005)
! Gomez DO, Mininni PD, Dmitruk P; Phys. Scripta T116, 123 (2005)
! Gomez DO, Mininni PD, Dmitruk P; Adv. Sp. Res. 35, 899 (2005)
!=================================================================

!
! Definitions for conditional compilation

#ifdef HD_SOL
#define DNS_
#endif

#ifdef PHD_SOL
#define DNS_
#define SCALAR_
#endif

#ifdef MHD_SOL
#define DNS_
#define MAGFIELD_
#endif

#ifdef MHDB_SOL
#define DNS_
#define MAGFIELD_
#define UNIFORMB_
#endif

#ifdef HMHD_SOL
#define DNS_
#define MAGFIELD_
#define HALLTERM_
#endif

#ifdef ROTH_SOL
#define DNS_
#define ROTATION_
#endif 

#ifdef LAHD_SOL
#define ALPHAV_
#endif

#ifdef CAHD_SOL
#define ALPHAV_
#endif

#ifdef LHD_SOL
#define ALPHAV_
#endif

#ifdef LAMHD_SOL
#define MAGFIELD_
#define ALPHAV_
#define ALPHAB_
#endif

#ifdef EDQNMHD_SOL
#define DNS_
#define EDQNM_
#endif

#ifdef EDQNMROTH_SOL
#define DNS_
#define EDQNM_
#define ROTATION_
#endif

!
! Modules

      USE mpivars
      USE filefmt
      USE iovar
      USE grid
      USE fft
      USE ali
      USE var
      USE kes
      USE order
      USE random
      USE threads
#ifdef DNS_
      USE dns
#endif
#ifdef HALLTERM_
      USE hall
#endif
#ifdef ALPHAV_
      USE alpha
#endif
#ifdef EDQNM_
      USE edqnm
#endif

      IMPLICIT NONE

!
! Arrays for the fields and the external forcing

      COMPLEX, ALLOCATABLE, DIMENSION (:,:,:) :: vx,vy,vz
      COMPLEX, ALLOCATABLE, DIMENSION (:,:,:) :: fx,fy,fz
#ifdef SCALAR_
      COMPLEX, ALLOCATABLE, DIMENSION (:,:,:) :: th
      COMPLEX, ALLOCATABLE, DIMENSION (:,:,:) :: fs
#endif
#ifdef MAGFIELD_
      COMPLEX, ALLOCATABLE, DIMENSION (:,:,:) :: ax,ay,az
      COMPLEX, ALLOCATABLE, DIMENSION (:,:,:) :: mx,my,mz
#endif

!
! Temporal data storage arrays

      COMPLEX, ALLOCATABLE, DIMENSION (:,:,:) :: C1,C2
      COMPLEX, ALLOCATABLE, DIMENSION (:,:,:) :: C3,C4
      COMPLEX, ALLOCATABLE, DIMENSION (:,:,:) :: C5,C6
      COMPLEX, ALLOCATABLE, DIMENSION (:,:,:) :: C7,C8
      COMPLEX, ALLOCATABLE, DIMENSION (:,:,:) :: M1,M2,M3
#ifdef SCALAR_
      COMPLEX, ALLOCATABLE, DIMENSION (:,:,:) :: C20
      COMPLEX, ALLOCATABLE, DIMENSION (:,:,:) :: M7
#endif
#ifdef MAGFIELD_
      COMPLEX, ALLOCATABLE, DIMENSION (:,:,:) :: C9,C10,C11
      COMPLEX, ALLOCATABLE, DIMENSION (:,:,:) :: C12,C13,C14
      COMPLEX, ALLOCATABLE, DIMENSION (:,:,:) :: C15,C16,C17
      COMPLEX, ALLOCATABLE, DIMENSION (:,:,:) :: M4,M5,M6
#endif
#ifdef HALLTERM_
      COMPLEX, ALLOCATABLE, DIMENSION (:,:,:) :: C18
#endif
#ifdef EDQNM_ 
      COMPLEX, ALLOCATABLE, DIMENSION (:,:,:) :: C19
      DOUBLE PRECISION, ALLOCATABLE, DIMENSION (:) :: tepq,thpq,tve,tvh
      DOUBLE PRECISION, ALLOCATABLE, DIMENSION (:) :: Eold,Hold
      DOUBLE PRECISION, ALLOCATABLE, DIMENSION (:) :: Eext,Hext
      REAL, ALLOCATABLE, DIMENSION (:,:,:)         :: Eden,Hden
#endif
      REAL, ALLOCATABLE, DIMENSION (:,:,:)    :: R1,R2,R3
      REAL, ALLOCATABLE, DIMENSION (:)        :: Faux1,Faux2

!
! Auxiliary variables

      COMPLEX          :: cdump,jdump
      COMPLEX          :: cdumq,jdumq
      COMPLEX          :: cdumr,jdumr
      DOUBLE PRECISION :: tmp,tmq
      DOUBLE PRECISION :: eps,epm
      DOUBLE PRECISION :: omptime1,omptime2
!$    DOUBLE PRECISION, EXTERNAL :: omp_get_wtime

      REAL    :: dt,nu,mu,kappa
      REAL    :: kup,kdn
      REAL    :: rmp,rmq
      REAL    :: dump
      REAL    :: stat
      REAL    :: f0,u0
      REAL    :: cputime1,cputime2
      REAL    :: phase,ampl,cort
      REAL    :: fparam0,fparam1,fparam2,fparam3,fparam4
      REAL    :: fparam5,fparam6,fparam7,fparam8,fparam9
      REAL    :: vparam0,vparam1,vparam2,vparam3,vparam4
      REAL    :: vparam5,vparam6,vparam7,vparam8,vparam9
#ifdef SCALAR_
      REAL    :: skup,skdn
      REAL    :: c0,s0
      REAL    :: cparam0,cparam1,cparam2,cparam3,cparam4
      REAL    :: cparam5,cparam6,cparam7,cparam8,cparam9
      REAL    :: sparam0,sparam1,sparam2,sparam3,sparam4
      REAL    :: sparam5,sparam6,sparam7,sparam8,sparam9
#endif
#ifdef MAGFIELD_
      REAL    :: mkup,mkdn
      REAL    :: m0,a0
      REAL    :: mparam0,mparam1,mparam2,mparam3,mparam4
      REAL    :: mparam5,mparam6,mparam7,mparam8,mparam9
      REAL    :: aparam0,aparam1,aparam2,aparam3,aparam4
      REAL    :: aparam5,aparam6,aparam7,aparam8,aparam9
#endif
#ifdef UNIFORMB_
      REAL    :: bx0
      REAL    :: by0
      REAL    :: bz0
#endif
#ifdef ROTATION_
      REAL    :: omega
#endif

      INTEGER :: ini,step
      INTEGER :: tstep,cstep
      INTEGER :: sstep,fstep
      INTEGER :: bench,trans
      INTEGER :: outs,mean
      INTEGER :: seed,rand
      INTEGER :: mult
      INTEGER :: t,o
      INTEGER :: i,j,k
      INTEGER :: ki,kj,kk
      INTEGER :: tind,sind
      INTEGER :: timet,timec
      INTEGER :: times,timef
#ifdef SCALAR_
      INTEGER :: injt
#endif
#ifdef MAGFIELD_
      INTEGER :: dyna
      INTEGER :: corr
#endif
!$    INTEGER, EXTERNAL :: omp_get_max_threads

      TYPE(IOPLAN) :: planio

      CHARACTER(len=100) :: odir,idir

!
! Namelists for the input files

      NAMELIST / status / idir,odir,stat,mult,bench,outs,mean,trans
      NAMELIST / parameter / dt,step,tstep,sstep,cstep,rand,cort,seed
      NAMELIST / velocity / f0,u0,kdn,kup,nu,fparam0,fparam1,fparam2
      NAMELIST / velocity / fparam3,fparam4,fparam5,fparam6,fparam7
      NAMELIST / velocity / fparam8,fparam9,vparam0,vparam1,vparam2
      NAMELIST / velocity / vparam3,vparam4,vparam5,vparam6,vparam7
      NAMELIST / velocity / vparam8,vparam9
#ifdef SCALAR_
      NAMELIST / scalar / c0,s0,skdn,skup,kappa,cparam0,cparam1
      NAMELIST / scalar / cparam2,cparam3,cparam4,cparam5,cparam6
      NAMELIST / scalar / cparam7,cparam8,cparam9,sparam0,sparam1
      NAMELIST / scalar / sparam2,sparam3,sparam4,sparam5,sparam6
      NAMELIST / scalar / sparam7,sparam8,sparam9
      NAMELIST / inject / injt
#endif
#ifdef MAGFIELD_
      NAMELIST / magfield / m0,a0,mkdn,mkup,mu,corr,mparam0,mparam1
      NAMELIST / magfield / mparam2,mparam3,mparam4,mparam5,mparam6
      NAMELIST / magfield / mparam7,mparam8,mparam9,aparam0,aparam1
      NAMELIST / magfield / aparam2,aparam3,aparam4,aparam5,aparam6
      NAMELIST / magfield / aparam7,aparam8,aparam9
      NAMELIST / dynamo / dyna
#endif
#ifdef UNIFORMB_
      NAMELIST / uniformb / bx0,by0,bz0
#endif
#ifdef HALLTERM_
      NAMELIST / hallparam / ep,gspe
#endif
#ifdef ROTATION_
      NAMELIST / rotation / omega
#endif
#ifdef ALPHAV_
      NAMELIST / alphav / alpk
#endif
#ifdef ALPHAB_
      NAMELIST / alphab / alpm
#endif
#ifdef EDQNM_
      NAMELIST / edqnmles / kolmo,heli
#endif

!
! Initializes the MPI and I/O libraries

      CALL MPI_INIT(ierr)
      CALL MPI_COMM_SIZE(MPI_COMM_WORLD,nprocs,ierr)
      CALL MPI_COMM_RANK(MPI_COMM_WORLD,myrank,ierr)
      CALL range(1,n/2+1,nprocs,myrank,ista,iend)
      CALL range(1,n,nprocs,myrank,ksta,kend)
      CALL io_init(myrank,n,ksta,kend,planio)

!
! Initializes the FFT library
! Use FFTW_ESTIMATE in short runs and FFTW_MEASURE 
! in long runs

      nth = 1
!$    nth = omp_get_max_threads()
      CALL fftp3d_create_plan(planrc,n,FFTW_REAL_TO_COMPLEX, &
                             FFTW_MEASURE)
      CALL fftp3d_create_plan(plancr,n,FFTW_COMPLEX_TO_REAL, &
                             FFTW_MEASURE)

!
! Allocates memory for distributed blocks

      ALLOCATE( C1(n,n,ista:iend),  C2(n,n,ista:iend) )
      ALLOCATE( C3(n,n,ista:iend),  C4(n,n,ista:iend) )
      ALLOCATE( C5(n,n,ista:iend),  C6(n,n,ista:iend) )
      ALLOCATE( C7(n,n,ista:iend),  C8(n,n,ista:iend) )
      ALLOCATE( vx(n,n,ista:iend) )
      ALLOCATE( vy(n,n,ista:iend) )
      ALLOCATE( vz(n,n,ista:iend) )
      ALLOCATE( fx(n,n,ista:iend) )
      ALLOCATE( fy(n,n,ista:iend) )
      ALLOCATE( fz(n,n,ista:iend) )
#ifdef SCALAR_
      ALLOCATE( C20(n,n,ista:iend) )
      ALLOCATE( th(n,n,ista:iend) )
      ALLOCATE( fs(n,n,ista:iend) )
#endif
#ifdef MAGFIELD_
      ALLOCATE( C9(n,n,ista:iend),  C10(n,n,ista:iend) )
      ALLOCATE( C11(n,n,ista:iend), C12(n,n,ista:iend) )
      ALLOCATE( C13(n,n,ista:iend), C14(n,n,ista:iend) )
      ALLOCATE( C15(n,n,ista:iend), C16(n,n,ista:iend) )
      ALLOCATE( C17(n,n,ista:iend) )
      ALLOCATE( ax(n,n,ista:iend) )
      ALLOCATE( ay(n,n,ista:iend) )
      ALLOCATE( az(n,n,ista:iend) )
      ALLOCATE( mx(n,n,ista:iend) )
      ALLOCATE( my(n,n,ista:iend) )
      ALLOCATE( mz(n,n,ista:iend) )
#endif
#ifdef HALLTERM_
      ALLOCATE( C18(n,n,ista:iend) )
#endif
      ALLOCATE( ka(n), ka2(n,n,ista:iend) )
      ALLOCATE( R1(n,n,ksta:kend) )
      ALLOCATE( R2(n,n,ksta:kend) )
      ALLOCATE( R3(n,n,ksta:kend) )
#ifdef EDQNM_
      ALLOCATE( C19(n,n,ista:iend) )
      ALLOCATE( Eden(n,n,ista:iend) )
      ALLOCATE( Hden(n,n,ista:iend) )
      ALLOCATE( tepq(n/2+1) )
      ALLOCATE( thpq(n/2+1) )
      ALLOCATE( tve (n/2+1) )
      ALLOCATE( tvh (n/2+1) )
      ALLOCATE( Eold(n/2+1) )
      ALLOCATE( Hold(n/2+1) )
      ALLOCATE( Eext(3*(n/2+1)) )
      ALLOCATE( Hext(3*(n/2+1)) )
#endif

!
! Some constants for the FFT
!     kmax: maximum truncation for dealiasing
!     tiny: minimum truncation for dealiasing

      kmax = (float(n)/3.)**2
#ifdef EDQNM_
      kmax = (float(n)/2.-.5)**2
#endif
      tiny  = 1e-5
      tinyf = 1e-15

!
! Builds arrays with the wavenumbers and the 
! square wavenumbers

      DO i = 1,n/2
         ka(i) = float(i-1)
         ka(i+n/2) = float(i-n/2-1)
      END DO
!$omp parallel do if (iend-ista.ge.nth) private (j,k)
      DO i = ista,iend
!$omp parallel do if (iend-ista.lt.nth) private (k)
         DO j = 1,n
            DO k = 1,n
               ka2(k,j,i) = ka(i)**2+ka(j)**2+ka(k)**2
            END DO
         END DO
      END DO

! The following lines read the file 'parameter.txt'

!
! Reads general configuration flags from the namelist 
! 'status' on the external file 'parameter.txt'
!     idir : directory for unformatted input
!     odir : directory for unformatted output
!     stat : = 0 starts a new run
!            OR  gives the number of the file used to continue a run
!     mult : time step multiplier
!     bench: = 0 production run
!            = 1 benchmark run (no I/O)
!     outs : = 0 writes velocity [and vector potential (MAGFIELD_)]
!            = 1 writes vorticity [and magnetic field (MAGFIELD_)]
!            = 2 writes current density (MAGFIELD_)
!     mean : = 0 skips mean field computation
!            = 1 performs mean field computation
!     trans: = 0 skips energy transfer computation
!            = 1 performs energy transfer computation

      IF (myrank.eq.0) THEN
         OPEN(1,file='parameter.txt',status='unknown',form="formatted")
         READ(1,NML=status)
         CLOSE(1)
      ENDIF
      CALL MPI_BCAST(idir,100,MPI_CHARACTER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(odir,100,MPI_CHARACTER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(stat,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mult,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(bench,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(outs,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mean,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(trans,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)

!
! Reads parameters that will be used to control the 
! time integration from the namelist 'parameter' on 
! the external file 'parameter.txt' 
!     dt   : time step size
!     step : total number of time steps to compute
!     tstep: number of steps between binary output
!     sstep: number of steps between power spectrum output
!     cstep: number of steps between output of global quantities
!     rand : = 0 constant force
!            = 1 random phases
!            = 2 constant energy
!     cort : time correlation of the external forcing
!     seed : seed for the random number generator

      IF (myrank.eq.0) THEN
         OPEN(1,file='parameter.txt',status='unknown',form="formatted")
         READ(1,NML=parameter)
         CLOSE(1)
         dt = dt/float(mult)
         step = step*mult
         tstep = tstep*mult
         sstep = sstep*mult
         cstep = cstep*mult
         fstep = int(cort/dt)
      ENDIF
      CALL MPI_BCAST(dt,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(step,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(tstep,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(sstep,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(cstep,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fstep,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(rand,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(seed,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)

!
! Reads parameters for the velocity field from the 
! namelist 'velocity' on the external file 'parameter.txt' 
!     f0   : amplitude of the mechanical forcing
!     u0   : amplitude of the initial velocity field
!     kdn  : minimum wave number in v/mechanical forcing
!     kup  : maximum wave number in v/mechanical forcing
!     nu   : kinematic viscosity
!     fparam0-9 : ten real numbers to control properties of 
!            the mechanical forcing
!     vparam0-9 : ten real numbers to control properties of
!            the initial conditions for the velocity field

      IF (myrank.eq.0) THEN
         OPEN(1,file='parameter.txt',status='unknown',form="formatted")
         READ(1,NML=velocity)
         CLOSE(1)
      ENDIF
      CALL MPI_BCAST(f0,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(u0,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(kdn,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(kup,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(nu,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fparam0,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fparam1,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fparam2,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fparam3,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fparam4,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fparam5,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fparam6,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fparam7,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fparam8,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fparam9,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(vparam0,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(vparam1,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(vparam2,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(vparam3,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(vparam4,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(vparam5,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(vparam6,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(vparam7,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(vparam8,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(vparam9,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)

#ifdef SCALAR_
!
! Reads general configuration flags for runs with 
! a passive scalar from the namelist 'inject' on 
! the external file 'parameter.txt'
!     injt : = 0 when stat=0 generates initial v and th (SCALAR_)
!            = 1 when stat.ne.0 imports v and generates th (SCALAR_)

      IF (myrank.eq.0) THEN
         OPEN(1,file='parameter.txt',status='unknown',form="formatted")
         READ(1,NML=inject)
         CLOSE(1)
      ENDIF
      CALL MPI_BCAST(injt,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)

!
! Reads parameters for the passive scalar from the 
! namelist 'scalar' on the external file 'parameter.txt'
!     s0   : amplitude of the passive scalar source
!     c0   : amplitude of the initial concentration
!     skdn : minimum wave number in concentration/source
!     skup : maximum wave number in concentration/source
!     kappa: diffusivity
!     sparam0-9 : ten real numbers to control properties of 
!            the source
!     cparam0-9 : ten real numbers to control properties of
!            the initial concentration

      IF (myrank.eq.0) THEN
         OPEN(1,file='parameter.txt',status='unknown',form="formatted")
         READ(1,NML=scalar)
         CLOSE(1)
      ENDIF
      CALL MPI_BCAST(s0,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(c0,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(skdn,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(skup,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(kappa,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(sparam0,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(sparam1,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(sparam2,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(sparam3,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(sparam4,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(sparam5,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(sparam6,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(sparam7,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(sparam8,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(sparam9,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(cparam0,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(cparam1,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(cparam2,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(cparam3,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(cparam4,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(cparam5,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(cparam6,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(cparam7,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(cparam8,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(cparam9,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
#endif

#ifdef MAGFIELD_
!
! Reads general configuration flags for runs with 
! magnetic fields from the namelist 'dynamo' on 
! the external file 'parameter.txt'
!     dyna : = 0 when stat=0 generates initial v and B (MAGFIELD_)
!            = 1 when stat.ne.0 imports v and generates B (MAGFIELD_) 

      IF (myrank.eq.0) THEN
         OPEN(1,file='parameter.txt',status='unknown',form="formatted")
         READ(1,NML=dynamo)
         CLOSE(1)
      ENDIF
      CALL MPI_BCAST(dyna,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)

!
! Reads parameters for the magnetic field from the 
! namelist 'magfield' on the external file 'parameter.txt' 
!     m0   : amplitude of the electromotive forcing
!     a0   : amplitude of the initial vector potential
!     mkdn : minimum wave number in B/electromotive forcing
!     mkup : maximum wave number in B/electromotive forcing
!     mu   : magnetic diffusivity
!     corr : = 0 no correlation between the random phases
!            = 1 correlation in the random phases generator
!     mparam0-9 : ten real numbers to control properties of 
!            the electromotive forcing
!     aparam0-9 : ten real numbers to control properties of
!            the initial conditions for the magnetic field

      IF (myrank.eq.0) THEN
         OPEN(1,file='parameter.txt',status='unknown',form="formatted")
         READ(1,NML=magfield)
         CLOSE(1)
      ENDIF
      CALL MPI_BCAST(m0,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(a0,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mkdn,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mkup,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mu,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(corr,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mparam0,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mparam1,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mparam2,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mparam3,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mparam4,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mparam5,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mparam6,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mparam7,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mparam8,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mparam9,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(aparam0,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(aparam1,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(aparam2,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(aparam3,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(aparam4,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(aparam5,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(aparam6,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(aparam7,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(aparam8,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(aparam9,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
#endif

#ifdef UNIFORMB_
!
! Reads parameters for runs with a uniform magnetic 
! field from the namelist 'uniformb' on the external 
! file 'parameter.txt' 
!     bx0: uniform magnetic field in x
!     by0: uniform magnetic field in y
!     bz0: uniform magnetic field in z

      IF (myrank.eq.0) THEN
         OPEN(1,file='parameter.txt',status='unknown',form="formatted")
         READ(1,NML=uniformb)
         CLOSE(1)
      ENDIF
#endif

#ifdef HALLTERM_
!
! Reads parameters for runs with the Hall effect 
! from the namelist 'hallparam' on the external 
! file 'parameter.txt' 
!     ep  : amplitude of the Hall effect
!     gspe: = 0 skips generalized helicity spectrum computation
!           = 1 computes the spectrum of generalized helicity

      IF (myrank.eq.0) THEN
         OPEN(1,file='parameter.txt',status='unknown',form="formatted")
         READ(1,NML=hallparam)
         CLOSE(1)
      ENDIF
      CALL MPI_BCAST(ep,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(gspe,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
#endif

#ifdef ROTATION_
!
! Reads parameters for runs with rotation from the 
! namelist 'rotation' on the external file 'parameter.txt'
!     omega: amplitude of the uniform rotation

      IF (myrank.eq.0) THEN
         OPEN(1,file='parameter.txt',status='unknown',form="formatted")
         READ(1,NML=rotation)
         CLOSE(1)
      ENDIF
      CALL MPI_BCAST(omega,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
#endif

#ifdef ALPHAV_
!
! Reads the value of alpha for the velocity field 
! in runs using Lagrangian averaged subgrid models
!     alpk: filter length for the velocity field

      IF (myrank.eq.0) THEN
         OPEN(1,file='parameter.txt',status='unknown',form="formatted")
         READ(1,NML=alphav)
         CLOSE(1)
      ENDIF
      CALL MPI_BCAST(alpk,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
#endif

#ifdef ALPHAB_
!
! Reads the value of alpha for the magnetic field 
! in runs using Lagrangian averaged subgrid models
!     alpm: filter length for the magnetic field

      IF (myrank.eq.0) THEN
         OPEN(1,file='parameter.txt',status='unknown',form="formatted")
         READ(1,NML=alphab)
         CLOSE(1)
      ENDIF
      CALL MPI_BCAST(alpm,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
#endif

#ifdef EDQNM_
!
! Reads the value of the Kolmogorov constant and a 
! flag for the helicity LES in runs using EDQNM-based 
! LES models
!     kolmo: Kolmogorov constant
!     heli:  = 0 helicity not taken into account
!            = 1 helicity taken into account

      kolmo = 1.4    !Default value
      heli = 0       !Default value
      IF (myrank.eq.0) THEN
         OPEN(1,file='parameter.txt',status='unknown',form="formatted")
         READ(1,NML=edqnmles)
         CLOSE(1)
      ENDIF
      CALL MPI_BCAST(kolmo,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(heli,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
#endif

!
! Initializes arrays to keep track of the forcing 
! amplitude if constant energy is used, and 
! allocates arrays to compute mean flows if needed.

      ampl = 1.
      timef = fstep
      IF (rand.eq.2) THEN
         ALLOCATE( Faux1(10) )
         ALLOCATE( Faux2(10) )
         DO i = 1,10
            Faux1(i) = ampl
            Faux2(i) = 0.
         END DO
      ENDIF
      IF (mean.eq.1) THEN
         ALLOCATE( M1(n,n,ista:iend) )
         ALLOCATE( M2(n,n,ista:iend) )
         ALLOCATE( M3(n,n,ista:iend) )
!$omp parallel do if (iend-ista.ge.nth) private (j,k)
         DO i = ista,iend
!$omp parallel do if (iend-ista.lt.nth) private (k)
            DO j = 1,n
               DO k = 1,n
                  M1(k,j,i) = 0.
                  M2(k,j,i) = 0.
                  M3(k,j,i) = 0.
               END DO
            END DO
         END DO
#ifdef SCALAR_
         ALLOCATE( M7(n,n,ista:iend) )
!$omp parallel do if (iend-ista.ge.nth) private (j,k)
         DO i = ista,iend
!$omp parallel do if (iend-ista.lt.nth) private (k)
            DO j = 1,n
               DO k = 1,n
                  M7(k,j,i) = 0.
               END DO
            END DO
         END DO
#endif
#ifdef MAGFIELD_
         ALLOCATE( M4(n,n,ista:iend) )
         ALLOCATE( M5(n,n,ista:iend) )
         ALLOCATE( M6(n,n,ista:iend) )
!$omp parallel do if (iend-ista.ge.nth) private (j,k)
         DO i = ista,iend
!$omp parallel do if (iend-ista.lt.nth) private (k)
            DO j = 1,n
               DO k = 1,n
                  M4(k,j,i) = 0.
                  M5(k,j,i) = 0.
                  M6(k,j,i) = 0.
               END DO
            END DO
         END DO
#endif
      ENDIF

!
! Sets the external forcing

      INCLUDE 'initialfv.f90'           ! mechanical forcing
#ifdef SCALAR_
      INCLUDE 'initialfs.f90'           ! passive scalar source
#endif
#ifdef MAGFIELD_
      INCLUDE 'initialfb.f90'           ! electromotive forcing
#endif

! If stat=0 we start a new run.
! Generates initial conditions for the fields.

 IC : IF (stat.eq.0) THEN

      ini = 1
      sind = 0                          ! index for the spectrum
      tind = 0                          ! index for the binaries
      timet = tstep
      timec = cstep
      times = sstep
      INCLUDE 'initialv.f90'            ! initial velocity
#ifdef SCALAR_
      INCLUDE 'initials.f90'            ! initial concentration
#endif
#ifdef MAGFIELD_
      INCLUDE 'initialb.f90'            ! initial vector potential
#endif

      ELSE

! If stat.ne.0 a previous run is continued

      ini = int((stat-1)*tstep)
      tind = int(stat)
      sind = int(float(ini)/float(sstep)+1)
      WRITE(ext, fmtext) tind
      times = 0
      timet = 0
      timec = 0

      CALL io_read(1,idir,'vx',ext,planio,R1)
      CALL io_read(1,idir,'vy',ext,planio,R2)
      CALL io_read(1,idir,'vz',ext,planio,R3)
      CALL fftp3d_real_to_complex(planrc,R1,vx,MPI_COMM_WORLD)
      CALL fftp3d_real_to_complex(planrc,R2,vy,MPI_COMM_WORLD)
      CALL fftp3d_real_to_complex(planrc,R3,vz,MPI_COMM_WORLD)

      IF (mean.eq.1) THEN
         CALL io_read(1,idir,'mean_vx',ext,planio,R1)
         CALL io_read(1,idir,'mean_vy',ext,planio,R2)
         CALL io_read(1,idir,'mean_vz',ext,planio,R3)
         CALL fftp3d_real_to_complex(planrc,R1,M1,MPI_COMM_WORLD)
         CALL fftp3d_real_to_complex(planrc,R2,M2,MPI_COMM_WORLD)
         CALL fftp3d_real_to_complex(planrc,R3,M3,MPI_COMM_WORLD)
         dump = float(ini)/cstep
!$omp parallel do if (iend-ista.ge.nth) private (j,k)
         DO i = ista,iend
!$omp parallel do if (iend-ista.lt.nth) private (k)
            DO j = 1,n
               DO k = 1,n
                  M1(k,j,i) = dump*M1(k,j,i)
                  M2(k,j,i) = dump*M2(k,j,i)
                  M3(k,j,i) = dump*M3(k,j,i)
               END DO
            END DO
         END DO
      ENDIF

#ifdef SCALAR_
 INJ: IF (injt.eq.0) THEN
         CALL io_read(1,idir,'th',ext,planio,R1)
         CALL fftp3d_real_to_complex(planrc,R1,th,MPI_COMM_WORLD)
         IF (mean.eq.1) THEN
            CALL io_read(1,idir,'mean_th',ext,planio,R1)
            CALL fftp3d_real_to_complex(planrc,R1,M7,MPI_COMM_WORLD)
            dump = float(ini)/cstep
!$omp parallel do if (iend-ista.ge.nth) private (j,k)
            DO i = ista,iend
!$omp parallel do if (iend-ista.lt.nth) private (k)
               DO j = 1,n
                  DO k = 1,n
                     M7(k,j,i) = dump*M7(k,j,i)
                 END DO
               END DO
            END DO
         ENDIF
      ELSE
         INCLUDE 'initials.f90'      ! initial concentration
         ini = 1                     ! resets all counters (the
         sind = 0                    ! run starts at t=0)
         tind = 0
         timet = tstep
         timec = cstep
         times = sstep
      ENDIF INJ
#endif

#ifdef MAGFIELD_
 DYN: IF (dyna.eq.0) THEN
         CALL io_read(1,idir,'ax',ext,planio,R1)
         CALL io_read(1,idir,'ay',ext,planio,R2)
         CALL io_read(1,idir,'az',ext,planio,R3)
         CALL fftp3d_real_to_complex(planrc,R1,ax,MPI_COMM_WORLD)
         CALL fftp3d_real_to_complex(planrc,R2,ay,MPI_COMM_WORLD)
         CALL fftp3d_real_to_complex(planrc,R3,az,MPI_COMM_WORLD)
         IF (mean.eq.1) THEN
            CALL io_read(1,idir,'mean_bx',ext,planio,R1)
            CALL io_read(1,idir,'mean_by',ext,planio,R2)
            CALL io_read(1,idir,'mean_bz',ext,planio,R3)
            CALL fftp3d_real_to_complex(planrc,R1,M4,MPI_COMM_WORLD)
            CALL fftp3d_real_to_complex(planrc,R2,M5,MPI_COMM_WORLD)
            CALL fftp3d_real_to_complex(planrc,R3,M6,MPI_COMM_WORLD)
            dump = float(ini)/cstep
!$omp parallel do if (iend-ista.ge.nth) private (j,k)
            DO i = ista,iend
!$omp parallel do if (iend-ista.lt.nth) private (k)
               DO j = 1,n
                  DO k = 1,n
                     M4(k,j,i) = dump*M4(k,j,i)
                     M5(k,j,i) = dump*M5(k,j,i)
                     M6(k,j,i) = dump*M6(k,j,i)
                 END DO
               END DO
            END DO
         ENDIF
      ELSE
         INCLUDE 'initialb.f90'      ! initial vector potential
         ini = 1                     ! resets all counters (the
         sind = 0                    ! dynamo run starts at t=0)
         tind = 0
         timet = tstep
         timec = cstep
         times = sstep
      ENDIF DYN
#endif

      ENDIF IC

!
! Time integration scheme starts here.
! Does ord iterations of Runge-Kutta. If 
! we are doing a benchmark, we measure 
! cputime before starting.

      IF (bench.eq.1) THEN
         CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)
         CALL CPU_Time(cputime1)
!$       omptime1 = omp_get_wtime()
      ENDIF

 RK : DO t = ini,step

! Updates the external forcing. Every 'fsteps'
! the phase or amplitude is changed according 
! to the value of 'rand'.

         IF (timef.eq.fstep) THEN
            timef = 0

            IF (rand.eq.1) THEN      ! randomizes phases

               IF (myrank.eq.0) phase = 2*pi*randu(seed)
               CALL MPI_BCAST(phase,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
               cdump = COS(phase)+im*SIN(phase)
               jdump = conjg(cdump)
#ifdef SCALAR_
               IF (myrank.eq.0) phase = 2*pi*randu(seed)
               CALL MPI_BCAST(phase,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
               cdumr = COS(phase)+im*SIN(phase)
               jdumr = conjg(cdump)
#endif
#ifdef MAGFIELD_
               IF (myrank.eq.0) phase = 2*pi*randu(seed)
               CALL MPI_BCAST(phase,1,MPI_REAL,0,MPI_COMM_WORLD,ierr)
               cdumq = corr*cdump+(1-corr)*(COS(phase)+im*SIN(phase))
               jdumq = corr*jdump+(1-corr)*conjg(cdump)
#endif
               IF (ista.eq.1) THEN
!$omp parallel do
                  DO j = 2,n/2+1
                     fx(1,j,1) = fx(1,j,1)*cdump
                     fx(1,n-j+2,1) = fx(1,n-j+2,1)*jdump
                     fy(1,j,1) = fy(1,j,1)*cdump
                     fy(1,n-j+2,1) = fy(1,n-j+2,1)*jdump
                     fz(1,j,1) = fz(1,j,1)*cdump
                     fz(1,n-j+2,1) = fz(1,n-j+2,1)*jdump
#ifdef SCALAR_
                     fs(1,j,1) = fs(1,j,1)*cdumr
                     fs(1,n-j+2,1) = fs(1,n-j+2,1)*jdumr
#endif
#ifdef MAGFIELD_
                     mx(1,j,1) = mx(1,j,1)*cdumq
                     mx(1,n-j+2,1) = mx(1,n-j+2,1)*jdumq
                     my(1,j,1) = my(1,j,1)*cdumq
                     my(1,n-j+2,1) = my(1,n-j+2,1)*jdumq
                     mz(1,j,1) = mz(1,j,1)*cdumq
                     mz(1,n-j+2,1) = mz(1,n-j+2,1)*jdumq
#endif
                  END DO
!$omp parallel do
                  DO k = 2,n/2+1
                     fx(k,1,1) = fx(k,1,1)*cdump
                     fx(n-k+2,1,1) = fx(n-k+2,1,1)*jdump
                     fy(k,1,1) = fy(k,1,1)*cdump
                     fy(n-k+2,1,1) = fy(n-k+2,1,1)*jdump
                     fz(k,1,1) = fz(k,1,1)*cdump
                     fz(n-k+2,1,1) = fz(n-k+2,1,1)*jdump
#ifdef SCALAR_
                     fs(k,1,1) = fs(k,1,1)*cdumr
                     fs(n-k+2,1,1) = fs(n-k+2,1,1)*jdumr
#endif
#ifdef MAGFIELD_
                     mx(k,1,1) = mx(k,1,1)*cdumq
                     mx(n-k+2,1,1) = mx(n-k+2,1,1)*jdumq
                     my(k,1,1) = my(k,1,1)*cdumq
                     my(n-k+2,1,1) = my(n-k+2,1,1)*jdumq
                     mz(k,1,1) = mz(k,1,1)*cdumq
                     mz(n-k+2,1,1) = mz(n-k+2,1,1)*jdumq
#endif
                  END DO
!$omp parallel do private (k)
                  DO j = 2,n
                     DO k = 2,n/2+1
                        fx(k,j,1) = fx(k,j,1)*cdump
                        fx(n-k+2,n-j+2,1) = fx(n-k+2,n-j+2,1)*jdump
                        fy(k,j,1) = fy(k,j,1)*cdump
                        fy(n-k+2,n-j+2,1) = fy(n-k+2,n-j+2,1)*jdump
                        fz(k,j,1) = fz(k,j,1)*cdump
                        fz(n-k+2,n-j+2,1) = fz(n-k+2,n-j+2,1)*jdump
#ifdef SCALAR_
                        fs(k,j,1) = fs(k,j,1)*cdumr
                        fs(n-k+2,n-j+2,1) = fs(n-k+2,n-j+2,1)*jdumr
#endif
#ifdef MAGFIELD_
                        mx(k,j,1) = mx(k,j,1)*cdumq
                        mx(n-k+2,n-j+2,1) = mx(n-k+2,n-j+2,1)*jdumq
                        my(k,j,1) = my(k,j,1)*cdumq
                        my(n-k+2,n-j+2,1) = my(n-k+2,n-j+2,1)*jdumq
                        mz(k,j,1) = mz(k,j,1)*cdumq
                        mz(n-k+2,n-j+2,1) = mz(n-k+2,n-j+2,1)*jdumq
#endif
                     END DO
                  END DO
!$omp parallel do if (iend-2.ge.nth) private (j,k)
                  DO i = 2,iend
!$omp parallel do if (iend-2.lt.nth) private (k)
                     DO j = 1,n
                        DO k = 1,n
                           fx(k,j,i) = fx(k,j,i)*cdump
                           fy(k,j,i) = fy(k,j,i)*cdump
                           fz(k,j,i) = fz(k,j,i)*cdump
#ifdef SCALAR_
                           fs(k,j,i) = fs(k,j,i)*cdumr
#endif
#ifdef MAGFIELD_
                           mx(k,j,i) = mx(k,j,i)*cdumq
                           my(k,j,i) = my(k,j,i)*cdumq
                           mz(k,j,i) = mz(k,j,i)*cdumq
#endif
                        END DO
                     END DO
                  END DO
               ELSE
!$omp parallel do if (iend-ista.ge.nth) private (j,k)
                  DO i = ista,iend
!$omp parallel do if (iend-ista.lt.nth) private (k)
                     DO j = 1,n
                        DO k = 1,n
                           fx(k,j,i) = fx(k,j,i)*cdump
                           fy(k,j,i) = fy(k,j,i)*cdump
                           fz(k,j,i) = fz(k,j,i)*cdump
#ifdef SCALAR_
                           fs(k,j,i) = fs(k,j,i)*cdumr
#endif
#ifdef MAGFIELD_
                           mx(k,j,i) = mx(k,j,i)*cdumq
                           my(k,j,i) = my(k,j,i)*cdumq
                           mz(k,j,i) = mz(k,j,i)*cdumq
#endif
                        END DO
                     END DO
                  END DO
               ENDIF

            ELSE IF (rand.eq.2) THEN ! constant energy

#ifdef HD_SOL
              INCLUDE 'hd_adjustfv.f90'
#endif
#ifdef PHD_SOL
              INCLUDE 'hd_adjustfv.f90'
#endif
#ifdef MHD_SOL
              INCLUDE 'mhd_adjustfv.f90'
#endif
#ifdef MHDB_SOL
              INCLUDE 'mhd_adjustfv.f90'
#endif
#ifdef HMHD_SOL
              INCLUDE 'mhd_adjustfv.f90'
#endif
#ifdef ROTH_SOL
              INCLUDE 'hd_adjustfv.f90'
#endif
#ifdef LAHD_SOL
              INCLUDE 'lahd_adjustfv.f90'
#endif
#ifdef CAHD_SOL
              INCLUDE 'lahd_adjustfv.f90'
#endif
#ifdef LHD_SOL
              INCLUDE 'hd_adjustfv.f90'
#endif
#ifdef LAMHD_SOL
              INCLUDE 'lahd_adjustfv.f90'
#endif
#ifdef EDQNMHD_SOL
              INCLUDE 'edqnmhd_adjustfv.f90'
#endif
#ifdef EDQNMROTH_SOL
              INCLUDE 'edqnmhd_adjustfv.f90'
#endif

            ENDIF

         ENDIF

! Every 'tstep' steps, stores the fields 
! in binary files

         IF ((timet.eq.tstep).and.(bench.eq.0)) THEN
            timet = 0
            tind = tind+1
            IF (rand.eq.2) THEN
               CALL energy(fx,fy,fz,tmp,1)
               IF (myrank.eq.0) THEN
                  OPEN(1,file='force.txt',position='append')
                  WRITE(1,*) (t-1)*dt,sqrt(tmp)
                  CLOSE(1)
               ENDIF
            ENDIF
            WRITE(ext, fmtext) tind
!$omp parallel do if (iend-ista.ge.nth) private (j,k)
            DO i = ista,iend
!$omp parallel do if (iend-ista.lt.nth) private (k)
               DO j = 1,n
                  DO k = 1,n
                     C1(k,j,i) = vx(k,j,i)/float(n)**3
                     C2(k,j,i) = vy(k,j,i)/float(n)**3
                     C3(k,j,i) = vz(k,j,i)/float(n)**3
                  END DO
               END DO
            END DO
            IF (outs.ge.1) THEN
               CALL rotor3(C2,C3,C4,1)
               CALL rotor3(C1,C3,C5,2)
               CALL rotor3(C1,C2,C6,3)
               CALL fftp3d_complex_to_real(plancr,C4,R1,MPI_COMM_WORLD)
               CALL fftp3d_complex_to_real(plancr,C5,R2,MPI_COMM_WORLD)
               CALL fftp3d_complex_to_real(plancr,C6,R3,MPI_COMM_WORLD)
               CALL io_write(1,odir,'wx',ext,planio,R1)
               CALL io_write(1,odir,'wy',ext,planio,R2)
               CALL io_write(1,odir,'wz',ext,planio,R3)
            ENDIF
            CALL fftp3d_complex_to_real(plancr,C1,R1,MPI_COMM_WORLD)
            CALL fftp3d_complex_to_real(plancr,C2,R2,MPI_COMM_WORLD)
            CALL fftp3d_complex_to_real(plancr,C3,R3,MPI_COMM_WORLD)
            CALL io_write(1,odir,'vx',ext,planio,R1)
            CALL io_write(1,odir,'vy',ext,planio,R2)
            CALL io_write(1,odir,'vz',ext,planio,R3)
            IF (mean.eq.1) THEN
               dump = float(cstep)/t
!$omp parallel do if (iend-ista.ge.nth) private (j,k)
               DO i = ista,iend
!$omp parallel do if (iend-ista.lt.nth) private (k)
                  DO j = 1,n
                     DO k = 1,n
                        C1(k,j,i) = dump*M1(k,j,i)/float(n)**3
                        C2(k,j,i) = dump*M2(k,j,i)/float(n)**3
                        C3(k,j,i) = dump*M3(k,j,i)/float(n)**3
                     END DO
                  END DO
               END DO
               CALL fftp3d_complex_to_real(plancr,C1,R1,MPI_COMM_WORLD)
               CALL fftp3d_complex_to_real(plancr,C2,R2,MPI_COMM_WORLD)
               CALL fftp3d_complex_to_real(plancr,C3,R3,MPI_COMM_WORLD)
               CALL io_write(1,odir,'mean_vx',ext,planio,R1)
               CALL io_write(1,odir,'mean_vy',ext,planio,R2)
               CALL io_write(1,odir,'mean_vz',ext,planio,R3)
            ENDIF
#ifdef SCALAR_
!$omp parallel do if (iend-ista.ge.nth) private (j,k)
            DO i = ista,iend
!$omp parallel do if (iend-ista.lt.nth) private (k)
               DO j = 1,n
                  DO k = 1,n
                     C1(k,j,i) = th(k,j,i)/float(n)**3
                  END DO
               END DO
            END DO
            CALL fftp3d_complex_to_real(plancr,C1,R1,MPI_COMM_WORLD)
            CALL io_write(1,odir,'th',ext,planio,R1)
            IF (mean.eq.1) THEN
               dump = float(cstep)/t
!$omp parallel do if (iend-ista.ge.nth) private (j,k)
               DO i = ista,iend
!$omp parallel do if (iend-ista.lt.nth) private (k)
                  DO j = 1,n
                     DO k = 1,n
                        C1(k,j,i) = dump*M7(k,j,i)/float(n)**3
                     END DO
                  END DO
               END DO
               CALL fftp3d_complex_to_real(plancr,C1,R1,MPI_COMM_WORLD)
               CALL io_write(1,odir,'mean_th',ext,planio,R1)
            ENDIF
#endif
#ifdef MAGFIELD_
!$omp parallel do if (iend-ista.ge.nth) private (j,k)
            DO i = ista,iend
!$omp parallel do if (iend-ista.lt.nth) private (k)
               DO j = 1,n
                  DO k = 1,n
                     C1(k,j,i) = ax(k,j,i)/float(n)**3
                     C2(k,j,i) = ay(k,j,i)/float(n)**3
                     C3(k,j,i) = az(k,j,i)/float(n)**3
                  END DO
               END DO
            END DO
            IF (outs.ge.1) THEN
               CALL rotor3(C2,C3,C4,1)
               CALL rotor3(C1,C3,C5,2)
               CALL rotor3(C1,C2,C6,3)
               CALL fftp3d_complex_to_real(plancr,C4,R1,MPI_COMM_WORLD)
               CALL fftp3d_complex_to_real(plancr,C5,R2,MPI_COMM_WORLD)
               CALL fftp3d_complex_to_real(plancr,C6,R3,MPI_COMM_WORLD)
               CALL io_write(1,odir,'bx',ext,planio,R1)
               CALL io_write(1,odir,'by',ext,planio,R2)
               CALL io_write(1,odir,'bz',ext,planio,R3)
            ENDIF
            IF (outs.eq.2) THEN
               CALL laplak3(C1,C4)
               CALL laplak3(C2,C5)
               CALL laplak3(C3,C6)
               CALL fftp3d_complex_to_real(plancr,C4,R1,MPI_COMM_WORLD)
               CALL fftp3d_complex_to_real(plancr,C5,R2,MPI_COMM_WORLD)
               CALL fftp3d_complex_to_real(plancr,C6,R3,MPI_COMM_WORLD)
               CALL io_write(1,odir,'jx',ext,planio,R1)
               CALL io_write(1,odir,'jy',ext,planio,R2)
               CALL io_write(1,odir,'jz',ext,planio,R3)
            ENDIF
            CALL fftp3d_complex_to_real(plancr,C1,R1,MPI_COMM_WORLD)
            CALL fftp3d_complex_to_real(plancr,C2,R2,MPI_COMM_WORLD)
            CALL fftp3d_complex_to_real(plancr,C3,R3,MPI_COMM_WORLD)
            CALL io_write(1,odir,'ax',ext,planio,R1)
            CALL io_write(1,odir,'ay',ext,planio,R2)
            CALL io_write(1,odir,'az',ext,planio,R3)
            IF (mean.eq.1) THEN
               dump = float(cstep)/t
!$omp parallel do if (iend-ista.ge.nth) private (j,k)
               DO i = ista,iend
!$omp parallel do if (iend-ista.lt.nth) private (k)
                  DO j = 1,n
                     DO k = 1,n
                        C1(k,j,i) = dump*M4(k,j,i)/float(n)**3
                        C2(k,j,i) = dump*M5(k,j,i)/float(n)**3
                        C3(k,j,i) = dump*M6(k,j,i)/float(n)**3
                     END DO
                  END DO
               END DO
               CALL fftp3d_complex_to_real(plancr,C1,R1,MPI_COMM_WORLD)
               CALL fftp3d_complex_to_real(plancr,C2,R2,MPI_COMM_WORLD)
               CALL fftp3d_complex_to_real(plancr,C3,R3,MPI_COMM_WORLD)
               CALL io_write(1,odir,'mean_bx',ext,planio,R1)
               CALL io_write(1,odir,'mean_by',ext,planio,R2)
               CALL io_write(1,odir,'mean_bz',ext,planio,R3)
            ENDIF
#endif
         ENDIF

! Every 'cstep' steps, generates external files 
! with global quantities. If mean=1 also updates 
! the mean fields.

         IF ((timec.eq.cstep).and.(bench.eq.0)) THEN
            timec = 0
#ifdef HD_SOL
            INCLUDE 'hd_global.f90'
#endif
#ifdef PHD_SOL
            INCLUDE 'phd_global.f90'
#endif
#ifdef MHD_SOL
            INCLUDE 'mhd_global.f90'
#endif
#ifdef MHDB_SOL
            INCLUDE 'mhd_global.f90'
#endif
#ifdef HMHD_SOL
            INCLUDE 'hmhd_global.f90'
#endif
#ifdef ROTH_SOL
            INCLUDE 'hd_global.f90'
#endif
#ifdef LAHD_SOL
            INCLUDE 'lahd_global.f90'
#endif
#ifdef CAHD_SOL
            INCLUDE 'lahd_global.f90'
#endif
#ifdef LHD_SOL
            INCLUDE 'hd_global.f90'
#endif
#ifdef LAMHD_SOL
            INCLUDE 'lamhd_global.f90'
#endif
#ifdef EDQNMHD_SOL
            INCLUDE 'hd_global.f90'
#endif
#ifdef EDQNMROTH_SOL
            INCLUDE 'hd_global.f90'
#endif
            IF (mean.eq.1) THEN
!$omp parallel do if (iend-ista.ge.nth) private (j,k)
               DO i = ista,iend
!$omp parallel do if (iend-ista.lt.nth) private (k)
                  DO j = 1,n
                     DO k = 1,n
                        M1(k,j,i) = M1(k,j,i)+vx(k,j,i)
                        M2(k,j,i) = M2(k,j,i)+vy(k,j,i)
                        M3(k,j,i) = M3(k,j,i)+vz(k,j,i)
                     END DO
                  END DO
               END DO
#ifdef SCALAR_
!$omp parallel do if (iend-ista.ge.nth) private (j,k)
               DO i = ista,iend
!$omp parallel do if (iend-ista.lt.nth) private (k)
                  DO j = 1,n
                     DO k = 1,n
                        M7(k,j,i) = M7(k,j,i)+th(k,j,i)
                     END DO
                  END DO
               END DO
#endif
#ifdef MAGFIELD_
               CALL rotor3(ay,az,C1,1)
               CALL rotor3(ax,az,C2,2)
               CALL rotor3(ax,ay,C3,3)
!$omp parallel do if (iend-ista.ge.nth) private (j,k)
               DO i = ista,iend
!$omp parallel do if (iend-ista.lt.nth) private (k)
                  DO j = 1,n
                     DO k = 1,n
                        M4(k,j,i) = M4(k,j,i)+vx(k,j,i)
                        M5(k,j,i) = M5(k,j,i)+vy(k,j,i)
                        M6(k,j,i) = M6(k,j,i)+vz(k,j,i)
                     END DO
                  END DO
               END DO
#endif
            ENDIF
         ENDIF

! Every 'sstep' steps, generates external files 
! with the power spectrum.

         IF ((times.eq.sstep).and.(bench.eq.0)) THEN
            times = 0
            sind = sind+1
            WRITE(ext, fmtext) sind
#ifdef HD_SOL
            INCLUDE 'hd_spectrum.f90'
#endif
#ifdef PHD_SOL
            INCLUDE 'phd_spectrum.f90'
#endif
#ifdef MHD_SOL
            INCLUDE 'mhd_spectrum.f90'
#endif
#ifdef MHDB_SOL
            INCLUDE 'mhdb_spectrum.f90'
#endif
#ifdef HMHD_SOL
            INCLUDE 'hmhd_spectrum.f90'
#endif
#ifdef ROTH_SOL
            INCLUDE 'roth_spectrum.f90'
#endif
#ifdef LAHD_SOL
            INCLUDE 'lahd_spectrum.f90'
#endif
#ifdef CAHD_SOL
            INCLUDE 'lahd_spectrum.f90'
#endif
#ifdef LHD_SOL
            INCLUDE 'hd_spectrum.f90'
#endif
#ifdef LAMHD_SOL
            INCLUDE 'lamhd_spectrum.f90'
#endif
#ifdef EDQNMHD_SOL
            INCLUDE 'edqnmhd_spectrum.f90'
#endif
#ifdef EDQNMROTH_SOL
            INCLUDE 'edqnmroth_spectrum.f90'
#endif
         ENDIF

! Runge-Kutta step 1
! Copies the fields into auxiliary arrays

!$omp parallel do if (iend-ista.ge.nth) private (j,k)
         DO i = ista,iend
!$omp parallel do if (iend-ista.lt.nth) private (k)
         DO j = 1,n
         DO k = 1,n

#ifdef HD_SOL
         INCLUDE 'hd_rkstep1.f90'
#endif
#ifdef PHD_SOL
         INCLUDE 'phd_rkstep1.f90'
#endif
#ifdef MHD_SOL
         INCLUDE 'mhd_rkstep1.f90'
#endif
#ifdef MHDB_SOL
         INCLUDE 'mhd_rkstep1.f90'
#endif
#ifdef HMHD_SOL
         INCLUDE 'mhd_rkstep1.f90'
#endif
#ifdef ROTH_SOL
         INCLUDE 'hd_rkstep1.f90'
#endif
#ifdef LAHD_SOL
         INCLUDE 'hd_rkstep1.f90'
#endif
#ifdef CAHD_SOL
         INCLUDE 'hd_rkstep1.f90'
#endif
#ifdef LHD_SOL
         INCLUDE 'hd_rkstep1.f90'
#endif
#ifdef LAMHD_SOL
         INCLUDE 'mhd_rkstep1.f90'
#endif
#ifdef EDQNMHD_SOL
         INCLUDE 'hd_rkstep1.f90'
#endif
#ifdef EDQNMROTH_SOL
         INCLUDE 'hd_rkstep1.f90'
#endif

         END DO
         END DO
         END DO

! Runge-Kutta step 2
! Evolves the system in time

         DO o = ord,1,-1
#ifdef HD_SOL
         INCLUDE 'hd_rkstep2.f90'
#endif
#ifdef PHD_SOL
         INCLUDE 'phd_rkstep2.f90'
#endif
#ifdef MHD_SOL
         INCLUDE 'mhd_rkstep2.f90'
#endif
#ifdef MHDB_SOL
         INCLUDE 'mhdb_rkstep2.f90'
#endif
#ifdef HMHD_SOL
         INCLUDE 'hmhd_rkstep2.f90'
#endif
#ifdef ROTH_SOL
         INCLUDE 'roth_rkstep2.f90'
#endif
#ifdef LAHD_SOL
         INCLUDE 'lahd_rkstep2.f90'
#endif
#ifdef CAHD_SOL
         INCLUDE 'lahd_rkstep2.f90'
#endif
#ifdef LHD_SOL
         INCLUDE 'lhd_rkstep2.f90'
#endif
#ifdef LAMHD_SOL
         INCLUDE 'lamhd_rkstep2.f90'
#endif
#ifdef EDQNMHD_SOL
         INCLUDE 'edqnmhd_rkstep2.f90'
#endif
#ifdef EDQNMROTH_SOL
         INCLUDE 'edqnmroth_rkstep2.f90'
#endif

         END DO

         timet = timet+1
         times = times+1
         timec = timec+1
         timef = timef+1

      END DO RK

!
! End of Runge-Kutta

! Computes the benchmark

      IF (bench.eq.1) THEN
         CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)
         CALL CPU_Time(cputime2)
!$       omptime2 = omp_get_wtime()
         IF (myrank.eq.0) THEN
            OPEN(1,file='benchmark.txt',position='append')
            WRITE(1,*) n,(step-ini+1),nprocs,nth, &
                       (cputime2-cputime1)/(step-ini+1),&
                       (omptime2-omptime1)/(step-ini+1)
            CLOSE(1)
         ENDIF
      ENDIF
!
! End of MAIN3D

      CALL MPI_FINALIZE(ierr)
      CALL fftp3d_destroy_plan(plancr)
      CALL fftp3d_destroy_plan(planrc)
      DEALLOCATE( R1,R2,R3 )
      DEALLOCATE( vx,vy,vz,fx,fy,fz )
      DEALLOCATE( C1,C2,C3,C4,C5,C6,C7,C8 )
      DEALLOCATE( ka,ka2 )
      IF (mean.eq.1) DEALLOCATE( M1,M2,M3 )
      IF (rand.eq.2) DEALLOCATE( Faux1, Faux2 )
#ifdef SCALAR_
      DEALLOCATE( th,fs )
      IF (mean.eq.1) DEALLOCATE( M7 )
#endif
#ifdef MAGFIELD_
      DEALLOCATE( ax,ay,az,mx,my,mz )
      DEALLOCATE( C9,C10,C11,C12,C13,C14,C15,C16,C17 )
      IF (mean.eq.1) DEALLOCATE( M4,M5,M6 )
#endif
#ifdef HALLTERM_
      DEALLOCATE( C18 )
#endif
#ifdef EDQNM_
      DEALLOCATE( C19 )
      DEALLOCATE( tepq,thpq,tve,tvh,Eext,Hext )
#endif 

      END PROGRAM MAIN3D

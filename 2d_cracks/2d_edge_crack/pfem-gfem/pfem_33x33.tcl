# turn on creation of extract file
set env(DO_QA) ON

# set number of threads for assemply and solver
set num_threads 10
set env(ISET_NUM_THREADS) $num_threads

# If these are not set, FlexiBLAS uses its default backend. 
#set env(ISET_BLAS_BACKEND_ASSEMBLER) "OPENBLASPTHREAD"
#set env(ISET_BLAS_BACKEND_SOLVER) "BLISPTHREAD"

#################################################################################################################
# create a linear analysis object
createAnalysis linear
analysis setParallelAssemble

#################################################################################################################
# This must be set before reading the .grf file since it controls the
# type of CompEls created (selects approximation space)
parSet useCompElPfemGfem true

# Activate the use of Branch/Heaviside Pair with Geometric Enrichment
parSet useBranchHeavisideFnPairWithGeomEnrich on

#################################################################################################################
# read the model
readFile "square_2d_domain_tria_33x33.grf" phfile

#################################################################################################################
# create a function object to compute exact solution and pass it to
# analsis object
createExactSol EdgeSol2D edgeElasID 100 mode ModeI term 0  

# turn on the use of exact solution as BCs and body force
parSet exactSolAsBC true

# set quantities to be postprocessed
graphMesh appendName  Solution
#graphMesh appendName  SolU
#graphMesh appendName  SolV
graphMesh appendName  VonMises
#graphMesh appendName  Sxx
#graphMesh appendName  Syy
#graphMesh appendName  Sxy
#graphMesh appendName  Szz
#graphMesh appendName  Stress
#graphMesh appendName  Strain

graphMesh appendName  Derivative
graphMesh appendName  ElemEnergy

graphMesh appendName  TrueError
graphMesh appendName  TrueErrorDeriv

graphMesh appendName  TrueElemEnergy
#graphMesh appendName  ErrorElemEnergy
graphMesh appendName  TrueErrorElemEnergyNorm
graphMesh appendName  TrueRelErrorElemEnergyNorm

#################################################################################################################
# create a crack manager:
#
# Inclined edge crack problem, Section 6.4 of [Sanchez-Rivadeneira & Duarte, 2019]
# Must also set in section "BEGIN NODES NUMBERED" of square_2d_domain_tria_33x33.grf
# 100000001	9	8.6982233047
crackMgr2D crackMgrID 1 create straightCrackEndPoints tail 0.0 2.414213562\
                                                      tip  8.0 8.0

# Horizontal edge crack problem, Section 4 of [Sanchez-Rivadeneira & Duarte, 2019]
# Must also set in section "BEGIN NODES NUMBERED" of square_2d_domain_tria_33x33.grf
# 100000001	9	8
#crackMgr2D crackMgrID 1 create straightCrackEndPoints tail 0.0 0.0\
#                                                      tip  8.0 8.0

# crack manager options
crackMgr2D crackMgrID 1 setOptions useBranchFn true

# Set up branch function enrichment within a cylinder (geometrical enrichment)
crackMgr2D crackMgrID 1 branchFnGeometricEnrich inCylinder radius 2

# Select OD enrichment. Use straightFrontOD for 2D problems
crackMgr2D crackMgrID 1 setOptions branchFunctionType straightFrontOD

# Turn on and set tolerances for snapping of geoNods to the surface and front
crackMgr2D crackMgrID 1 setOptions snapNodesToSurfAndFront on

# Use SGFEM enrichments: hoBasis = hoBasis - pou_interpolant( hoBasis )
# This needs to be set here before "process".
# parSet SGFEMSpecialBasisEnrichments  on
# parSet SGFEMBranchFnEnrichments  on
# parSet SGFEMBranchFnEnrichmentsDiscInterp  on

# Use Shifted GFEM enrichments: hoBasis = hoBasis - hoBasis_at_node
# This needs to be set here before "process".
  parSet ShiftedSpBasisEnrichments  on
# parSet ShiftedNotBranchFnEnrichments  on

# process crack (cut elements, select enrichments, etc)
crackMgr2D crackMgrID 1  process

#################################################################################################################
# Set order of pFEM-GFEM approximation
set p_global 2
enrichApprox iso approxOrder $p_global


#################################################################################################################
# create a VTK graph mesh and connect to file 
graphMesh create "pfem_33x33.vtu"  VTKStyle

#################################################################################################################
# To activate high-order singular integration rule for integration elements with a
# node on crack front. This is needed to reproduce the results in [Sanchez-Rivadeneira & Duarte, 2019]
set sing_p_order 20
parSet singularIntegrationOrder $sing_p_order

################################################################################################################
# Assembly process:
set initTime [ clock clicks -milliseconds ]
#Assemble system of equations
# assemble
parallelAssemble
set finalTime [ clock clicks -milliseconds ]
set totalTime_pa [expr ( $finalTime - $initTime ) / 1.0e3 ]
puts stdout "\nTime spent for (parallel) Assemble command: $totalTime_pa s \n"

################################################################################################################
# Condition number computation requires MatLab
set comp_cond_num 0

if {$comp_cond_num} {
  # Obtaining the Condition Number:
  set initTime [ clock clicks -milliseconds ]
  # Use this to scale the global matrix before getting condition number
  scaleGlobalMatrix
  # Getting condition number
  set condNum [parGet condNumber]
  puts stdout "\nScaled Condition Number: $condNum \n"
  set finalTime [ clock clicks -milliseconds ]
  set totalTime_cond [expr ( $finalTime - $initTime ) / 1.0e3 ]
  puts stdout "\nTime spent for calculating condition number: $totalTime_cond s \n"
}

################################################################################################################
# Solve system of equations:
set initTime [ clock clicks -milliseconds ]
solve
set finalTime [ clock clicks -milliseconds ]
set totalTime_sol [expr ( $finalTime - $initTime ) / 1.0e3 ]
puts stdout "\nTime spent for solve command: $totalTime_sol s \n"

################################################################################################################
# work of applied loads:
#work

################################################################################################################
# strainEnergy computed from the stress and strain in each element:
parallelStrainEnergyAndNorms addIntOrder 10

################################################################################################################
# Dump postprocessing quantities to file
graphMesh postProcess resolution  0 sampleInside

# Print the L infinity norm of various quantities to the screen
LinfNorm solution
LinfNorm derivative
LinfNorm trueError
LinfNorm trueErrorDeriv
LinfNorm clear

exit

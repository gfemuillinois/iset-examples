# ************************** Compact_Tension_Mode_I_II_pfem-GFEM.tcl **************************

# turn on creation of extract file
set env(DO_QA) ON

set num_threads 10
# set number of threads for assembly and solver
set env(ISET_NUM_THREADS) $num_threads

# Set these variables according to the problem you want to solve

# Name of the .crf file that contains the crack triangulation.
set crackFile "benchmark5b_initial_surf_after_remesh.crf"

# Name of the folder where results (.vtu, .vtk, etc. files) will be stored.
set resultsFolder "Results_2026_11"
file mkdir $resultsFolder

# Name of the .grf file that contains the finite element mesh, materials, and boundary conditions.
set domainFile "benchmark5b.grf"

# ------------ create a linear analysis object ------------
createAnalysis linear
analysis setParallelAssemble

# ------------ Use a pFEM-GFEM approximation space ----------
parSet useCompElPfemGfem true

# --- all non-polynomial enrichments are shifted by their nodal values. This improves conditioning ----------
parSet ShiftedSpBasisEnrichments true

# ------------ read the model ------------
readFile "$domainFile" phfile


# ------------ set quantities to be postprocessed ------------
graphMesh appendName  Solution
graphMesh appendName  Sxx
graphMesh appendName  Syy
graphMesh appendName  Szz
graphMesh appendName  VonMises

# ------------ If wants to see input geomesh and bcs ------------
set printInputGMesh true
if { $printInputGMesh == true } {
  graphMesh create "$resultsFolder/benchmark5b_geomesh.vtu" VTKStyle
  graphMesh postProcess resolution 0
  # Uncomment if want to quit
#  exit
}

# ------------ refine mesh globally ------------
# WARNING: Dirichlet BC must be assigned to the nodes created with the mesh refinement
# This is NOT done by the "refine" command!
set nref 0
for {set iref 0} {$iref < $nref} {incr iref} {
  refine all
}
meshReport

# Maximum number of crack propagation steps.
# Adjust based on target crack length and value of delta_a_max_law set below
# Use this for delta_a_max_law 0.1
#set num_steps 110
# Use this for delta_a_max_law 0.2
set num_steps 60
# Use this to solve the problem only once and check everything.
#set num_steps 1

# set resulting p order. Going over p = 3 may cause conditioning problems
set p_global 2
set p_loc_crack_front 3

# CPU time used for complete simulation
set totalTime 0

######################################################################
#   Setup for Crack       
######################################################################

#
# Compact tension test specimen:
# domain dimension: 63.5 * 60.96 * 3
# initial notch dimension: 22.86 *4 *3 @ y = mid height of the specimen
# initial length of the crack = 13.47; length of the crack front = 3
#
# length of initial crack front in mm
set initialCrackFrontLength 3

# Limit for length of crack front edges (defined by edges of facets along the crack front).
# Around 1/20 of length of initial crack front
set frontEdgeLengthLimit [ expr $initialCrackFrontLength / 20  ]

# Frequency of surface remesh (if doing remesh): after first step 
# and after remesh_surface_freq steps thereafter
set remesh_surface_freq  10

# Maximum allowed number of remeshings to be performed during entire simulation.
set max_num_remeshings $num_steps

# ------------ to use crack surface remeshing (set to true or false) ------------
set useRemeshCrackSurface false

# This should be set to false when re-starting simulation: starting_step != 0  below
# WARNING: Turn this to false and use the remeshed surface!!
set remeshInputCrackSurface false

# ------------ limit for length of edges of crack surface facets (enforced when remeshing) ------------
# this regards the size of the crack surface facets not at the front.
# it is normally bigger than frontEdgeLengthLimit but not too much, otherwise we may get
# facets with extreme aspect ratio
set mycrackSurfEdgeLength [ expr 1.3*$frontEdgeLengthLimit ]

# ------------ Whether to preserve current crack front when remeshing ------------
# Needed only in mixed-mode problems with sharp turns that need to be preserved.
# If set to true, code below will preserve only the crack front at the first step!
set storeCrackFront false

# ------------ Parameters for scaling law along crack front (Paris type law) ------------
# Same as in Faisal's paper and QA problems for MTS and MERR.
set mym 1.0
set myC 1.0
set myR 0.0

# ------------ Fracture thoughness of material. Only relevant for stable crack propagation problems ------------
# Value from Faisal's paper in kJ/m^2 = kN/m = N/mm
set myGc 0.285
# Near-zero to avoid crack arrest. Crack arrest can be determined aposteriori
#set myGc 1e-10

# ------------ Maximum deltaA for each step ------------
# initial length of the crack 
set initialCrackLength_a_o  13.3
#
# Adjust as needed, based on the size of the crack
#set delta_a_max_law [ expr  $initialCrackLength_a_o / 20 ]
# Accurate crack path
#set delta_a_max_law 0.1
# Quick solution
set delta_a_max_law 0.2

# ------------ Index of starting step. This is useful when re-starting a simulation using a .crf
# created by a previous run ------------
set starting_step 0
if { $starting_step == 0 } {

  crackMgr crackMgrID 1 create crackFile "$crackFile"

} else {
  puts stdout "\ncrackfile: $crackFile\_$starting_step \n\n"
  crackMgr crackMgrID 1 create crackFile "$crackFile\_$starting_step"
}

# ------------ Post Process first crack file ------------
if { $starting_step == 0 } {
  crackMgr crackMgrID 1 postSurface "$resultsFolder/benchmark5b_crackProp_initial_surf.vtu" VTUStyle
} else {
  crackMgr crackMgrID 1 postSurface "$resultsFolder/benchmark5b_crackProp_initial_surf_$starting_step.vtu" VTUStyle
}

# Activate algorithms that handle crack front turning sharp corners
crackMgr crackMgrID 1 setOptions domainBoundaryIsComplex true

# Split crack front stretches if needed
set env(CRACKFRONTMAYSPLIT) OFF

# Use non-scaled tolerance for checking the volume of integration descendants
# Default = false (recommended)
crackMgr crackMgrID 1 setOptions useScaledTolForCellVolCheck false

# ------------ do NOT extract at crack front points on the boundary ------------
# This is usually required for surface breaking cracks since extraction 
# at boundary points is not always possible.
crackMgr crackMgrID 1 setOptions numFrontEndVertToSkip 1

# ------------ Whether to use MLS to extrapolate SIF values to front-end vertices that were skipped during extraction.
# If this parameter is set to false, the SIF values at front-end vertices that were skipped during extraction,
# are taken as the same value at the last front-end vertex that was not skipped. This is useful for problems with
# SIFs that are known to be nearly constant along the crack front.
crackMgr crackMgrID 1 setOptions useMLSForSkippedFrontEndVert true

# ------------ apply Moving Least Square approximation to extracted SIFs ------------
# this must be used if we use option numFrontEndVertToSkip
crackMgr crackMgrID 1 setOptions useMLSForExtraction true

# ------------ Use MLS for the geometrical position of the front vertices ------------
# It improves the shape of the front and distributes the crack front 
# vertices with a equal spacing.
crackMgr crackMgrID 1 setOptions useMLSForCrackFrontVertices true

# How the crack front vertices will be distributed along 
# the crack front after each propagation step
# Must set "useMLSForCrackFrontVertices true" to activate this
crackMgr crackMgrID 1 setOptions MLS_DistribCrackFrontVerts QuasiUniform

# ------------ Number of sampling points at the interior of each crack front edge when dumping SIF data
crackMgr crackMgrID 1 setOptions MLS_numSamplePointsFrontEdges 0

# ------------ to use crack surface remeshing (set to true or false) ------------
crackMgr crackMgrID 1 setOptions useRemeshCrackSurface $useRemeshCrackSurface

# ------------ limit for crack surface edge size when remeshing ------------
crackMgr crackMgrID 1 setOptions crackSurfEdgeLength $mycrackSurfEdgeLength

# ------------ Whether to preserve current crack front when remeshing ------------
crackMgr crackMgrID 1 setOptions storeCrackFront $storeCrackFront

# ------------ Front will be refined if edges are longer than this limit ------------
crackMgr crackMgrID 1 setOptions frontEdgeLengthLimit $frontEdgeLengthLimit

# ------------ Remesh initial crf file ------------
# WARNING: I can use this because of classified nodes defined in .crf. Otherwise facets will be missing.
# The use of "classified nodes" here is a workaround for remeshing of crack surface (CGAL) function.
if {$remeshInputCrackSurface == true} {
  crackMgr crackMgrID 1 remeshCrackSurface 
  
  crackMgr crackMgrID 1 postSurface "$resultsFolder/benchmark5b_crackProp_initial_surf_after_remesh.vtu" VTUStyle
  crackMgr crackMgrID 1 postSurface "$resultsFolder/benchmark5b_crackProp_initial_surf_after_remesh.crf" crfStyle
}

# ------------ Don't let very stretched surface facets appear along the crack front ------------
# Set this to activate use of PAS (Propagate And Stretch). Otherwise only PAE
# (Propagate And Extrude == add layer of facets along crack front) is used.
#
# If displacement at a front vertex is larger than this tolerance, a new layer
# of facets and vertices are created. Otherwise the front vertex is stretched.
# If frontStretchTol 0.0 --> PAE always used;  If frontStretchTol = 100.0 --> PAS always used;
# Must also set accumulatedCrackFrontAdvanceLimit to a large value to force PAS for all propagation steps.
#
# PAE or PAS
crackMgr crackMgrID 1 setOptions frontStretchTol 20.0
#
# PAE (but not guaranteed). Code may use PAS to avoid degenerated facets: it enforces
# a minimum value of frontStretchTol 10.0.
#crackMgr crackMgrID 1 setOptions frontStretchTol 10.0
crackMgr crackMgrID 1 setOptions accumulatedCrackFrontAdvanceLimit [ expr 0.8*$frontEdgeLengthLimit ]
# PAS
#crackMgr crackMgrID 1 setOptions frontStretchTol 200.0
#crackMgr crackMgrID 1 setOptions accumulatedCrackFrontAdvanceLimit [ expr 1000*$frontEdgeLengthLimit ]


# ------------ Setting to use planar cuts away from crack front ------------
crackMgr crackMgrID 1 setOptions usePlanarCutsSignedDist true

# ------------ Setting Branch function type ------------
crackMgr crackMgrID 1 setOptions useBranchFn true
crackMgr crackMgrID 1 setOptions branchFunctionType curvedFrontOD6

# --- Use {Branch, Heaviside} pair in elements fully cut by crack surface and in the geometrical enrichment zone.
# This improves accuracy of solution w.out adding too many dofs.
parSet useBranchHeavisideFnPairWithGeomEnrich true

# --- Snapp to the crack surface nodes that are close to it ---
# This improves conditioning of global matrix
crackMgr crackMgrID 1 setOptions snapNodesToSurfAndFront snappingTolSurf 0.05 snappingTolFront 0.05

# ------------ Enrich all nodes within a cylinder around crack front ------------
# Tip: Radius = 4*maxEdgeLen, or a fraction of the initial crack size
#crackMgr crackMgrID 1 branchFnGeometricEnrich inCylinder radius [expr 0.5*$initialCrackFrontLength]

# ------------ Enrich nodes of elements around crack front
set numElemLayersBranchFnEnrich 5
crackMgr crackMgrID 1 branchFnGeometricEnrich numElemLayers $numElemLayersBranchFnEnrich


# ------------ create crackGrowthLaw object ------------
# Same as in Faisal's paper and QA problems for MTS and MERR.
crackMgr crackMgrID 1 crGrowthPhysicsLaw create
crackMgr crackMgrID 1 crGrowthPhysicsLaw crGrowthType StableCrackGrowth Gc_material $myGc
crackMgr crackMgrID 1 crGrowthPhysicsLaw crFrontScalingLaw ParisLaw C $myC m $mym R $myR

crackMgr crackMgrID 1 crGrowthPhysicsLaw crFrontIncrementType fixedDeltaA delta_a_max $delta_a_max_law

# Select criterion for crack growth direction
crackMgr crackMgrID 1 crGrowthPhysicsLaw crGrowthDirCriterion MTS

# --- Kinking angle less than this will be ignored. Small angles are often the effect of noise K_II
#     Default = 2 degrees
# Not needed if we set ignoreKII true (see below)
crackMgr crackMgrID 1 crGrowthPhysicsLaw frontKinkingAngleLimitDEG 0.0
# --- Twisting angle less than this will be ignored. Use large value since there is no twisting in this problem.
# Not needed if we set ignoreKIII true (see below)
#crackMgr crackMgrID 1 crGrowthPhysicsLaw frontTwistingAngleLimitDEG 40.0

# --- Print this so we can check it
crackMgr crackMgrID 1 crGrowthPhysicsLaw print

# ------------ Set to ignore KII if consistent with problem ------------
crackMgr crackMgrID 1 setOptions ignoreKII false

# ------------ Set to ignore KIII if consistent with problem ------------
crackMgr crackMgrID 1 setOptions ignoreKIII true
 
# ------------ counter of number of remeshes performed ------------
set remesh_counter 0

# Used to name the crack surface file of the last propagation step or arrested crack
set final_crack_prop_step  $starting_step

# ------------ loop over the crack front advancement steps ------------
for {set i_step $starting_step} {$i_step < $num_steps} {incr i_step} {
 
  puts stdout "\n\n********************************************* "
  puts stdout "\nStarting Crack Propagation Step $i_step "
  puts stdout "\n********************************************* \n\n"

  # refine 3-D GFEM elements cut by crack surface
  set nrefSurface 0
  for {set iref 0} {$iref < $nrefSurface} {incr iref} {
    crackMgr crackMgrID 1 refineMesh crackSurface
  }

  # ------------ refine 3-D GFEM mesh around crack front ------------
  # Tip: Choose close to 1.5% - 3% of characteristic crack size
  # For example, radius of circular crack, or length of an edge crack.
  # Check SIFs on crack front. Adjust the refinement if needed.
  # 
  crackMgr crackMgrID 1 refineMesh crackFronts maxEdgeLen [expr 0.02 * $initialCrackLength_a_o ]

  # meshReport

  # ------------ Post process crack surface at this step ------------
  # It is the initial crack or the one that was propagated at the previous step
  crackMgr crackMgrID 1 postSurface "$resultsFolder/benchmark5b_crackProp_surf_$i_step.vtu" VTUStyle

  set initTime [ clock clicks -milliseconds ]

  #  ------------  Turn on and set scaled tolerances for snapping of geoNods to the crack surface and front
  crackMgr crackMgrID 1 setOptions snapNodesToSurfAndFront snappingTolSurf 0.05 snappingTolFront 0.05

  # ------------ process crack (cut elements, select enrichments, etc) ------------
  crackMgr crackMgrID 1 process 

  set finalTime [ clock clicks -milliseconds ]
  set totalTime_cp [expr ( $finalTime - $initTime ) / 1.0e3 ]
  puts stdout "\nTime spent for crack process command (step $i_step): $totalTime_cp s \n"

  # ------------ set polynomial order of the approximation ------------
  enrichApprox iso approxOrder $p_global

  # ------------ Enrich all nodes within a cylinder around crack front ------------
  # Tip: Radius = 4*maxEdgeLen, or a fraction of the initial crack size
  # crackMgr crackMgrID 1 enrichApprox inCylinder radius [expr 0.5*$initialCrackFrontLength] iso approxOrder $p_loc_crack_front
  
  # ------------ Enrich nodes of elements around crack front
  set n_layers_enrich_front 5
  crackMgr crackMgrID 1 enrichApprox numElemLayers $n_layers_enrich_front iso approxOrder $p_loc_crack_front

  # Set enrichment order of nodes with Pt BC to zero
  set set_p_0_at_Pt_BC "true"
  
  if { $set_p_0_at_Pt_BC != "false" } {

    # Choose A or B for Cases A and B described below
    set nodes_with_p0 "A"
    
    if { $nodes_with_p0 == "A" } {
      # CASE A: set to p = 0 the nodes on the edges with end nodes with prescribed Pt BCs.

      # Nodes in lower hole with Pt BC
      enrichCompNod inBBox xyzMin 12.0 10.0 -0.3 \
                           xyzMax 13.5 11.0  3.3 \
                           iso order 0
      # WARNING: These are vertex nodes only!
      # enrichCompNod cnode 442 iso order 0
      # enrichCompNod cnode 444 iso order 0
      # enrichCompNod cnode 447 iso order 0

      # Nodes in upper hole with Pt BC
      enrichCompNod inBBox xyzMin 12.0 50.0 -0.3 \
                           xyzMax 13.5 51.5  3.3 \
                           iso order 0
      
      # WARNING: These are vertex nodes only!
      # enrichCompNod cnode 745 iso order 0
      # enrichCompNod cnode 746 iso order 0
      # enrichCompNod cnode 748 iso order 0

    } elseif { $nodes_with_p0 == "B" } {
      # CASE B: set to p = 0 all the nodes within a BBox contining the nodes with Pt BC.
      #         Aim to include elements connected to nodes with prescribed Pt BCs

      # Nodes near lower hole
      enrichCompNod inBBox xyzMin 10.5 8.0 -0.3 \
                           xyzMax 14.9 10.8 3.3 \
                           iso order 0
  
      # Nodes near upper hole
      enrichCompNod inBBox xyzMin 10.5 50.0 -0.3 \
                           xyzMax  14.9 53.0 3.3 \
                           iso order 0

  
    } else {
      puts stdout "\n\nInvalid value for nodes_with_p0 = $nodes_with_p0 \n\n"
    };              
  }
  
  # ------------ Creates the GraphMesh ------------
  graphMesh create "$resultsFolder/PostProcessMesh_benchmark5b_crackProp_$i_step.vtu"  VTKStyle


  # ------------ Assemble ------------
  set initTime [ clock clicks -milliseconds ]
  assemble
  set finalTime [ clock clicks -milliseconds ]
  set totalTime_pa [expr ( $finalTime - $initTime ) / 1.0e3 ]
  puts stdout "\nTime spent for assemble command (step $i_step): $totalTime_pa s \n"

  # ------------ Solve ------------
  set initTime [ clock clicks -milliseconds ]
  solve
  set finalTime [ clock clicks -milliseconds ]
  set totalTime_sol [expr ( $finalTime - $initTime ) / 1.0e3 ]
  puts stdout "\nTime spent for solve command (step $i_step): $totalTime_sol s \n"

  # ------------ work of applied (distributed) loads ------------
  #work

  # ------------ reaction forces at nodes with Pt Displacement BC ------------

  # ------------ reaction forces ------------

  # Nodes in lower hole with Pt BC
  computeNodReaction inBBox xyzMin 12.0 10.0 -0.3 \
                            xyzMax 13.5 11.0  3.3 \

  # Same thing if mesh was not refined in this region
  #computeNodReaction cnode 442
  #computeNodReaction cnode 444
  #computeNodReaction cnode 447

  # Nodes in upper hole with Pt BC
  computeNodReaction inBBox xyzMin 12.0 50.0 -0.3 \
                            xyzMax 13.5 51.5  3.3 \

  # Same thing if mesh was not refined in this region
  #computeNodReaction cnode 745
  #computeNodReaction cnode 746
  #computeNodReaction cnode 748
  
  # Extract solution so we can compute the COD
  # Point on lower face of crack (notch) mouth (not at lower support)
  extractQuantity Solution point 12.7 28.48 1.5
  # Point on upper face of crack (notch) mouth (not at upper support)
  extractQuantity Solution point 12.7 32.48 1.5


  # ------------ Generate Post Process VTK of global mesh
  graphMesh postProcess resolution 0 sampleInside

  # ------------ Print the L infinity norm of various quantities to the screen ------------
  LinfNorm solution

    # dump more extract data to extract file 
  extractFile create


  ########################################################################
  ###################### ADVANCE FRONT WITH Physics ######################
  ########################################################################
  # 

  if { $i_step != 0 } {
    # do not store Front unless this is the initial step
    crackMgr crackMgrID 1 setOptions storeCrackFront false
  }

  crackMgr crackMgrID 1 setOptions useRemeshCrackSurface false
  if { $useRemeshCrackSurface == true } {
    if { $i_step == 0 || [expr $i_step % $remesh_surface_freq] == 0 } {
      if { $remesh_counter < $max_num_remeshings } {
      	puts stdout "\n\ncrack surface will be remeshed at this step = $i_step\n"
      	crackMgr crackMgrID 1 setOptions useRemeshCrackSurface true
      	incr remesh_counter
      }
    }
  }

  # ------------ advance front with DCM ------------

  # ------------ Get min edge length ------------
  set minEdgeLen [parGet minEdgeLen]
  puts stdout "\n minEdgeLen = $minEdgeLen"

  # ------------ Values for DCM extraction ------------
  set dist [expr 4.0*$minEdgeLen] 
  set deltaD [expr 0.1*$minEdgeLen]  
  set num 11
  
  puts stdout "\n extrDist_min = $dist"
  puts stdout " deltaDist = $deltaD"

  set initTime [ clock clicks -milliseconds ]

  crackMgr crackMgrID 1 advanceFront DCM extrDist_min $dist deltaDist  $deltaD numExtrPoints $num 

  set finalTime [ clock clicks -milliseconds ]
  set totalTime_afp [expr ( $finalTime - $initTime ) / 1.0e3 ]
  puts stdout "\nTime spent for advanceFront command (step $i_step): $totalTime_afp s \n"

  # Crack surface was advanced using solution computed at this step. This is the index for the new surface
  set final_crack_prop_step [expr $i_step + 1]
  
  ########################################################################
  ##################### Finished Advancing crack #########################
  ########################################################################

  # Checking if the fracture has arrested
  set hasCrackArrested [crackMgr crackMgrID 1 parGet isCrackArrested ]
  if { $hasCrackArrested == "true" } {
    puts stdout "\n********************************************************"
    puts stdout "The fracture has arrested or fully cut the domain. Finishing code and exiting...\n"
    break
  }

  # ------------ prepare crack manager for next step ------------
  crackMgr crackMgrID 1 cleanUp afterPropagation

  # ------------ unrefine global mesh ------------
  unRefine toInitialMesh

  # ------------ compute total time estimate for simulation step ------------
  set totalTime_step [expr $totalTime_cp + $totalTime_pa + $totalTime_sol + $totalTime_afp ]
  puts stdout "\nTime spent for current step (step $i_step): $totalTime_step s\n"

  # ------------ compute total time estimate for entire simulation until current step ------------
  # (accounting for major steps only) and print to screen
  set totalTime [expr $totalTime + $totalTime_step ]
  puts stdout "\nTime spent for entire simulation until current step (step $i_step): $totalTime s\n"

}

# ------------ Post process the crack surface at the last step ------------
crackMgr crackMgrID 1 postSurface "$resultsFolder/benchmark5b_crackProp_surf_$final_crack_prop_step.vtu" VTUStyle
crackMgr crackMgrID 1 postSurface "$resultsFolder/benchmark5b_crackProp_surf_$final_crack_prop_step.crf" crfStyle


# ------------ print total time estimate for entire simulation step ------------
# (accounting for major steps only) 
puts stdout "\nTime spent for entire simulation ($final_crack_prop_step steps): $totalTime s\n"

# ------------ END ------------
exit


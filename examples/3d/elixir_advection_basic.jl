
using OrdinaryDiffEq
using Trixi

###############################################################################
# semidiscretization of the linear advection equation

advectionvelocity = (1.0, 1.0, 1.0)
equations = LinearScalarAdvectionEquation3D(advectionvelocity)

# Create DG solver with polynomial degree = 3 and Lax-Friedrichs flux as surface flux
solver = DGSEM(3, flux_lax_friedrichs)

coordinates_min = (-1, -1, -1) # minimum coordinates (min(x), min(y), min(z))
coordinates_max = ( 1,  1,  1) # maximum coordinates (max(x), max(y), max(z))

# Create a uniformely refined mesh with periodic boundaries
mesh = TreeMesh(coordinates_min, coordinates_max,
                initial_refinement_level=3,
                n_cells_max=30_000) # set maximum capacity of tree data structure

# A semidiscretization collects data structures and functions for the spatial discretization
semi = SemidiscretizationHyperbolic(mesh, equations, initial_condition_convergence_test, solver)


###############################################################################
# ODE solvers, callbacks etc.

# Create ODE problem with time span from 0.0 to 1.0
ode = semidiscretize(semi, (0.0, 1.0));

# At the beginning of the main loop, the SummaryCallback prints a summary of the simulation setup
# and resets the timers
summary_callback = SummaryCallback()

# The StepsizeCallback handles the re-calculcation of the maximum Δt after each time step
stepsize_callback = StepsizeCallback(cfl=1.2)

# The SaveSolutionCallback allows to save the solution to a file in regular intervals
save_solution = SaveSolutionCallback(interval=100,
                                     solution_variables=:primitive)

# The AnalysisCallback allows to analyse the solution in regular intervals and prints the results
analysis_callback = AnalysisCallback(semi, interval=100)

# Create a CallbackSet to collect all callbacks such that they can be passed to the ODE solver
callbacks = CallbackSet(summary_callback, stepsize_callback, save_solution, analysis_callback)


###############################################################################
# run the simulation

# OrdinaryDiffEq's `solve` method evolves the solution in time and executes the passed callbacks
sol = solve(ode, CarpenterKennedy2N54(williamson_condition=false),
            dt=1.0, # solve needs some value here but it will be overwritten by the stepsize_callback
            save_everystep=false, callback=callbacks);

# Print the timer summary
summary_callback()

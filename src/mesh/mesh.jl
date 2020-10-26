include("abstract_tree.jl")
include("serial_tree.jl")
include("parallel_tree.jl")
include("parallel.jl")

# Composite type to hold the actual tree in addition to other mesh-related data
# that is not strictly part of the tree.
mutable struct TreeMesh{TreeType<:AbstractTree}
  tree::TreeType
  current_filename::String
  unsaved_changes::Bool
  first_cell_by_rank::OffsetVector{Int, Vector{Int}}
  n_cells_by_rank::OffsetVector{Int, Vector{Int}}

  function TreeMesh{TreeType}(n_cells_max::Integer) where TreeType
    # Create mesh
    m = new()
    m.tree = TreeType(n_cells_max)
    m.current_filename = ""
    m.unsaved_changes = false
    m.first_cell_by_rank = OffsetVector(Int[], 0)
    m.n_cells_by_rank = OffsetVector(Int[], 0)

    return m
  end

  function TreeMesh{TreeType}(n_cells_max::Integer, domain_center::AbstractArray{Float64},
                              domain_length, periodicity=true) where TreeType
    # Create mesh
    m = new()
    m.tree = TreeType(n_cells_max, domain_center, domain_length, periodicity)
    m.current_filename = ""
    m.unsaved_changes = false
    m.first_cell_by_rank = OffsetVector(Int[], 0)
    m.n_cells_by_rank = OffsetVector(Int[], 0)

    return m
  end
end

const TreeMesh1D = TreeMesh{TreeType} where {TreeType <: AbstractTree{1}}
const TreeMesh2D = TreeMesh{TreeType} where {TreeType <: AbstractTree{2}}
const TreeMesh3D = TreeMesh{TreeType} where {TreeType <: AbstractTree{3}}

# Constructor for passing the dimension and mesh type as an argument
TreeMesh(::Type{TreeType}, args...) where TreeType = TreeMesh{TreeType}(args...)

# Constructor accepting a single number as center (as opposed to an array) for 1D
function TreeMesh{TreeType}(n::Int, center::Real, len::Real, periodicity=true) where {TreeType<:AbstractTree{1}}
  return TreeMesh{TreeType}(n, [convert(Float64, center)], len, periodicity)
end


@inline Base.ndims(mesh::TreeMesh) = ndims(mesh.tree)


# Generate initial mesh
function generate_mesh()
  # Get number of spatial dimensions
  ndims_ = parameter("ndims")

  # Get maximum number of cells that should be supported
  n_cells_max = parameter("n_cells_max")

  # Get domain boundaries
  coordinates_min = parameter("coordinates_min")
  coordinates_max = parameter("coordinates_max")

  # Domain length is calculated as the maximum length in any axis direction
  domain_center = @. (coordinates_min + coordinates_max) / 2
  domain_length = maximum(coordinates_max .- coordinates_min)

  # By default, mesh is periodic in all dimensions
  periodicity = parameter("periodicity", true)

  # Create mesh
  if mpi_isparallel()
    tree_type = ParallelTree{ndims_}
  else
    tree_type = SerialTree{ndims_}
  end
  @timeit timer() "creation" mesh = TreeMesh(tree_type, n_cells_max, domain_center,
                                             domain_length, periodicity)

  # Create initial refinement
  # initial_refinement_level = parameter("initial_refinement_level")
  # @timeit timer() "initial refinement" for l = 1:initial_refinement_level
  #   refine!(mesh.tree)
  # end

  # Apply refinement patches
  @timeit timer() "refinement patches" for patch in parameter("refinement_patches", [])
    mpi_isparallel() && error("non-uniform meshes not supported in parallel")
    if patch["type"] == "box"
      refine_box!(mesh.tree, patch["coordinates_min"], patch["coordinates_max"])
    else
      error("unknown refinement patch type '$(patch["type"])'")
    end
  end

  # Apply coarsening patches
  @timeit timer() "coarsening patches" for patch in parameter("coarsening_patches", [])
    mpi_isparallel() && error("non-uniform meshes not supported in parallel")
    if patch["type"] == "box"
      coarsen_box!(mesh.tree, patch["coordinates_min"], patch["coordinates_max"])
    else
      error("unknown coarsening patch type '$(patch["type"])'")
    end
  end

  # Partition mesh
  if mpi_isparallel()
    partition!(mesh)
  end

  return mesh
end


# Load existing mesh from file
load_mesh(restart_filename) = load_mesh(restart_filename, mpi_parallel())
function load_mesh(restart_filename, mpi_parallel::Val{false})
  # Get number of spatial dimensions
  ndims_ = parameter("ndims")

  # Get maximum number of cells that should be supported
  n_cells_max = parameter("n_cells_max")

  # Create mesh
  @timeit timer() "creation" mesh = TreeMesh(SerialTree{ndims_}, n_cells_max)

  # Determine mesh filename
  filename = get_restart_mesh_filename(restart_filename, Val(false))
  mesh.current_filename = filename
  mesh.unsaved_changes = false

  # Open mesh file
  h5open(filename, "r") do file
    # Set domain information
    mesh.tree.center_level_0 = read(attrs(file)["center_level_0"])
    mesh.tree.length_level_0 = read(attrs(file)["length_level_0"])
    mesh.tree.periodicity    = Tuple(read(attrs(file)["periodicity"]))

    # Set length
    n_cells = read(attrs(file)["n_cells"])
    resize!(mesh.tree, n_cells)

    # Read in data
    mesh.tree.parent_ids[1:n_cells] = read(file["parent_ids"])
    mesh.tree.child_ids[:, 1:n_cells] = read(file["child_ids"])
    mesh.tree.neighbor_ids[:, 1:n_cells] = read(file["neighbor_ids"])
    mesh.tree.levels[1:n_cells] = read(file["levels"])
    mesh.tree.coordinates[:, 1:n_cells] = read(file["coordinates"])
  end

  return mesh
end


# Obtain the mesh filename from a restart file
get_restart_mesh_filename(restart_filename) = get_restart_mesh_filename(restart_filename, mpi_parallel())
function get_restart_mesh_filename(restart_filename, mpi_parallel::Val{false})
  # Get directory name
  dirname, _ = splitdir(restart_filename)

  # Read mesh filename from restart file
  mesh_file = ""
  h5open(restart_filename, "r") do file
    mesh_file = read(attrs(file)["mesh_file"])
  end

  # Construct and return filename
  return joinpath(dirname, mesh_file)
end

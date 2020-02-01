module Io

using ..Jul1dge
using ..DgMod
import ..Equation
using Plots
import GR

export plot2file

function plot2file(dg, filename)
  gr()
  GR.inline("png")
  x = dg.nodecoordinate[:]
  y = zeros(length(x), Equation.nvars(dg))
  s = syseqn(dg)
  nnodes = polydeg(dg) + 1
  for v = 1:Equation.nvars(dg)
    for c in 1:dg.ncells
      for i = 1:nnodes
        y[(c - 1) * nnodes + i, v] = dg.u[v, i, c]
      end
    end
    plot(x, y, label=s.varnames[:], xlims=(-10.5, 10.5), ylims=(-1, 2),
         size=(1600,1200), thickness_scaling=3)
  end
  savefig(filename)
end

end

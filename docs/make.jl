using Documenter, FranklinContent
FranklinContent.franklincontent_hfuncs()

# generate index.md
#
@inline docitem(item) =  "\n```@docs\n$(item)\n```\n"

c = IOBuffer()
exps = Set(names(FranklinContent)[2:end])
# first exported
for sym in exps
    write(c, docitem(sym))
end

for sym in names(FranklinContent; all=true)
    sym ∈ exps && continue
    syms = string(sym)
    if startswith(syms, "hfun_") ||
        startswith(syms, "lx_")
        write(c, docitem(syms))
    end
end
write("src/index.md", String(take!(c)))
close(c)

# [sym for sym in names(@__MODULE__; all=true) if startswith(string(sym), "hfun_")]

makedocs(sitename="Documentation for the FranklinContent Plugin", pages=["API" => "index.md" ])

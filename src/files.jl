using ResumableFunctions

extension(url::String) = try
    match(r"\.[A-Za-z0-9]+$", url).match
catch
    ""
end

@resumable function walkfiles(root; exts=Set((".md", ".html")),
                              ex_dirs::AbstractSet=Set(),
                              dirs::Union{AbstractSet,Nothing}=nothing,
                              subdir=false)
    """
iterate over files in a directory, recursively and selectively by extension name and dir name
"""
    for p in readdir(root)
        path = joinpath(root, p)
        # directory, not excluded
        if isdir(path)
            name = splitpath(p)[end]
            if in(name, ex_dirs)
                continue # requires ResumableFunctions > 0.0.6
            elseif subdir || in(name, dirs)
                # resumable functions doesn't support recursive generators
                for f in collect(walkfiles(path; exts, ex_dirs, dirs, subdir=true))
                    @yield f
                end
            end
            # file, only included
        elseif in(extension(splitpath(p)[end]), exts)
            @yield path
        end
    end
end

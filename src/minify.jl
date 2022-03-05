module FranklinMinify

include("files.jl")
using PyCall: pyimport
using Conda: pip
using Franklin: path

const rx_tags = Dict(
    "" => r"",
    "<script>" =>r"^<script>",
    "<style>" => r"^<style>",
    "</script>" => r"</script>$",
    "</style>" => r"</style>$",
)

function load_html_minify()
	try
        return pyimport("minify_html")
    catch
        pip("install", "minify-html")
        return pyimport("minify_html")
    end
end

function minify_website(;minify_css=true, minify_js=true, minify_kwargs...)
    site = path(:site)
    @assert isdir(site)
    # remove toplevel paths
    for path in readdir(site)
        f = joinpath(site, path)
        islink(f) && rm(f)
    end
    minify = load_html_minify().minify
    buf = IOBuffer()
    for file in walkfiles(site;
                          exts=Set((".html", ".css", ".js")),
                          subdir=true)
        if endswith(file, ".css")
            opentag = "<style>"
            closetag = "</style>"
        elseif endswith(file, ".js")
            opentag = "<script>"
            closetag = "</script>"
        else
            opentag = ""
            closetag = ""
        end
        println(buf, opentag, read(file, String), closetag)
        min = minify(;code=String(take!(buf)),
                     minify_css,
                     minify_js,
                     minify_kwargs...)
        min = replace(min, rx_tags[opentag] => "")
        min = replace(min, rx_tags[closetag] => "")
        write(file, min)
    end
    close(buf)
end

export minify_website

end

module AMP

using Gumbo
using Cascadia
using Cascadia: matchFirst
using HTTP
using AbstractTrees: PreOrderDFS
using Pkg: project
using FranklinContent: walkfiles, islink, isldjson

const root_dir = Ref("")

function set_root(root=dirname(project().path))
    root_dir[] = root
end

skip_nodes = Set(HTMLElement{sym} for sym in [:iframe, :applet, :audio, :canvas, :embed, :video, :img, :button, :form])

const sel_body = sel"body"
const sel_head = sel"head"
const amp_doc = HTMLDocument("html", HTMLElement(:html))
const amp_head = HTMLElement(:head)
push!(amp_doc.root, amp_head)
const amp_body = HTMLElement(:body)
push!(amp_doc.root, amp_body)

function amp_template()
    html = amp_doc.root
    empty!(html.children)
    empty!(html.attributes)
    empty!(amp_head.children)
    empty!(amp_body.children)

    setattr!(html, "amp", "")
    push!(html, amp_head)
    push!(html, amp_body)
    # amp js
    ampjs = HTMLElement(:script)
    setattr!(ampjs, "async", "")
    setattr!(ampjs, "src", "https://cdn.ampproject.org/v0.js")
    push!(amp_head, ampjs)

    # charset
    charset = HTMLElement(:meta)
    setattr!(charset, "charset", "utf-8")
    push!(amp_head, charset)

    # viewport
    viewport = HTMLElement(:meta)
    setattr!(viewport, "name", "viewport")
    setattr!(viewport, "content", "width=device-width,minimum-scale=1,initial-scale=1")
    push!(amp_head, viewport)

    # amp styles
    # amp-custom goes before boilerplate
    push!(amp_head, style_el)
    style1 = HTMLElement(:style)
    setattr!(style1, "amp-boilerplate", "")
    push!(style1.children, HTMLText("body{-webkit-animation:-amp-start 8s steps(1,end) 0s 1 normal both;-moz-animation:-amp-start 8s steps(1,end) 0s 1 normal both;-ms-animation:-amp-start 8s steps(1,end) 0s 1 normal both;animation:-amp-start 8s steps(1,end) 0s 1 normal both}@-webkit-keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}@-moz-keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}@-ms-keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}@-o-keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}@keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}"))
    push!(amp_head, style1)

    style2 = HTMLElement(:style)
    setattr!(style2, "amp-boilerplate", "")
    push!(style2.children, HTMLText("body{-webkit-animation:none;-moz-animation:none;-ms-animation:none;animation:none}"))
    style2wrapper = HTMLElement(:noscript)
    push!(style2wrapper.children, style2)
    push!(amp_head, style2wrapper)

    (html, amp_head, amp_body)
end

const styles_str = Ref("")
const styles_scripts = Vector{String}()
const style_el = HTMLElement(:style)
setattr!(style_el, "amp-custom", "")
setattr!(style_el, "type", "text/css")

function fetch_style(el, styles)
    style_source = getattr(el, "href")
    if startswith(style_source, "/")
        push!(styles,
              read(joinpath(root_dir[], lstrip(style_source, '/')),
                   String))
    else
        push!(styles,
              String(HTTP.get(style_source).body))
    end
end

function process_head(in_head, out_head, styles)
    canonical_unset = true
    title_unset = true
    for el in in_head.children
        tp = typeof(el)
        if tp ∈ skip_nodes continue end
        if tp === HTMLElement{:link}
            if canonical_unset && islink(el, "canonical")
                push!(out_head, el)
                canonical_unset = false
            elseif islink(el, "stylesheet")
                fetch_style(el, styles)
            else
                push!(out_head, el)
            end
        elseif title_unset && tp === HTMLElement{:title}
            push!(out_head, el)
            title_unset = false
        elseif tp === HTMLElement{:script} &&
            isldjson(el)
            push!(out_head, el)
        elseif tp === HTMLElement{:meta} &&
            getattr(el, "name", "") === "viewport"
            continue
        else
            push!(out_head, el)
        end
    end
end

function recursive_check(el)
    if typeof(el) <: HTMLElement
        if length(el.children) > 0
            for c in el.children
                recursive_check(c)
            end
        else
            @assert typeof(el) ∉ skip_nodes
        end
    end
end

function process_body(in_el, out_body, out_head, styles, lv=false)
    l = length(in_el.children)
    n = 1
    while n <= l
        el = in_el.children[n]
        tp = typeof(el)
        if tp ∈ skip_nodes
            deleteat!(in_el.children, n)
            l -= 1
            continue
        elseif tp === HTMLElement{:link} &&
            (islink(el, "stylesheet") ||
            (islink(el, "preload") && getattr(el, "as") == "style"))
            fetch_style(el, styles)
            deleteat!(in_el.children, n)
            l -= 1
        elseif tp === HTMLElement{:style}
            # NOTE: this is supposed to be a text element
            push!(styles, el.children[1].text)
            deleteat!(in_el.children, n)
            l -= 1
        elseif tp === HTMLElement{:script}
            # only include ld+json scripts, ignore the rest
            isldjson(el) && push!(out_head, el)
            deleteat!(in_el.children, n)
            l -= 1
        else
            if tp !== HTMLText
                delete!(el.attributes, "onclick")
                length(el.children) !== 0 && process_body(el, out_body, out_head, styles, true)
            end
            # only add top level children
            lv || push!(out_body, el)
            n += 1
        end
    end
end

function amppage(file)
    html = parsehtml(read(file, String))
    in_body, in_head = (matchFirst(sel_body, html.root),
                        matchFirst(sel_head, html.root))
    (out_html, out_head, out_body) = amp_template()
    setattr!(out_html, "amp", "")
    for (a, v) in html.root.attributes
        setattr!(out_html, a, v)
    end

    empty!(styles_scripts)
    styles_str[] = ""

    process_head(in_head, out_head, styles_scripts)

    process_body(in_body, out_body, out_head, styles_scripts)

    # add remaining styles to head
    ss = styles_str[] = join(styles_scripts, "\n") |>
        # NOTE: the replacement should be ordered from most frequent to rarest
        # # remove troublesome animations
        x -> replace(x, r"\s*?@(\-[a-zA-Z]+-)?keyframes\s+?.+?{\s*?.+?({.+?})+?\s*?}"s => "") |>
        # # remove !important hints
        x -> replace(x, r"!important" => "") |>
        # remove charset since not allowed
        x -> replace(x, r"@charset\s+\"utf-8\"\s*;?"i => "")
    # Ensure CSS is less than maximum amp size of 75KB
    # NOTE: this doesn't take into account inline css
    @assert length(ss) < 75000
    empty!(style_el.children)
    push!(style_el, HTMLText(ss))

    string(amp_doc)
end

function ampdir(target; dirs=["posts", "tag", "reads", "_rss"])
    @assert isdir(target) "Path $target is not a valid directory"
    dir = isdirpath(target) ? dirname(target) : target
    rpl = Regex("^$dir/") => ""
    cwd = pwd()
    cd(dir)

    amp_dir = joinpath(dir, "amp")
    if !isdir(amp_dir) mkpath(amp_dir) end
    proc_dirs = Dict{String, Nothing}()

    try
        for file in walkfiles(dir; exts=Set((".html",)),
                              dirs=Set(dirs),
                              ex_dirs=Set(["amp"]),
                              subdir=false)
            html = amppage(file)
            out_file = joinpath(amp_dir, replace(file, rpl))
            out_dir = dirname(out_file)
            if out_dir ∉ keys(proc_dirs) && !isdir(out_dir)
                mkpath(out_dir)
                proc_dirs[out_dir] = nothing
            end
            write(out_file, html)
        end
    finally
        cd(cwd)
    end
end

end

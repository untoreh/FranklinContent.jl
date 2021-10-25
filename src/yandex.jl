module Yandex
using Gumbo
using Cascadia
using Franklin: globvar, locvar, pagevar, path
using JSON
using FranklinContent: walkfiles, islink, isldjson

const header = HTMLElement(:header)
const heading = HTMLText("")
const subheading = HTMLText("")
const figure = HTMLElement(:figure)
const image = HTMLElement(:image)
const menu = HTMLElement(:menu)
const crumbs_html = HTMLElement(:div)
const crumbs_links = Vector{Tuple{String, String}}()
const crumbs_io = IOBuffer()
const a_tag = HTMLElement(:a)
const page_url = Ref("")
const page_date = Ref("")
const page_id = Ref("")
const page_descr = Ref("")
const page_lang = Ref("")
const page_kws = []
const turbo_dir = Ref("")

skip_nodes = Set(HTMLElement{sym} for sym in [:style, :iframe, :applet, :audio, :canvas, :embed, :video, :img, :button, :form])

@doc "Convert a string to an HTMLText object."
macro ht_str(text)
    quote
        HTMLText($text)
    end
end

@doc "Set up yandex turbo page header elements."
function init_header()
    empty!(header.children)
    empty!(header.attributes)
    h1 = HTMLElement(:h1)
    push!(h1, heading)
    push!(header, h1)

    h2 = HTMLElement(:h2)
    push!(h2, subheading)
    push!(header, h2)

    push!(figure, image)
    push!(header, figure)

    setattr!(crumbs_html, "data-block", "breadcrumblist")
    push!(header, menu)
    push!(header, crumbs_html)
end

function set_header(;title::AbstractString,
                    subtitle::AbstractString="",
                    img_url::AbstractString="",
                    menu_links::AbstractVector=[])
    heading.text = title
    subheading.text = subtitle
    setattr!(image, "src", img_url)
    @debug @assert length(a_tag.attributes) === 0 && length(a_tag.children) === 0
    empty!(menu.children)
    for link in menu_links
        a = deepcopy(a_tag)
        setattr!(a, "src", link)
        push!(menu, a)
    end
    empty!(crumbs_html.children)
    for (_, link) in crumbs_links
        a = deepcopy(a_tag)
        setattr!(a, "src", link)
        push!(crumbs_html, a)
    end
end

@inline function is_script_id(el, tp, id="")
    tp === HTMLElement{:script} &&
        getattr(el, "id", "") === id
end

function process_head(in_head)
    canonical_unset = true
    title_unset = true
    title = ""
    subtitle = ""
    sub_unset = true
    empty!(crumbs_links)
    crumbs_unset = true
    date_unset = true
    empty!(page_kws)
    for el in in_head.children
        tp = typeof(el)
        if tp ∈ skip_nodes continue end
        if title_unset && tp === HTMLElement{:title}
            title = text(el)
            title_unset = false
            # use the meta "description" tag for the subtitle
        elseif canonical_unset &&
            tp === HTMLElement{:link} &&
            islink(el, "canonical")
            page_url[] = getattr(el, "href", "")
            canonical_unset = false
        elseif sub_unset && tp === HTMLElement{:meta} && hasattr(el, "description")
            subtitle = getattr(el, "description")
            sub_unset = false
            # get page published date
        elseif date_unset && is_script_id(el, tp, "ldj-webpage")
            data = el |> text |> JSON.parse
            page_date[] = data["datePublished"]
            date_unset= false
            page_id[] = data["mainEntityOfPage"]["@id"]
            append!(page_kws, data["keywords"])
            # parse the markup for breadcrumbs
        elseif crumbs_unset && is_script_id(el, tp, "ldj-breadcrumbs")
            data = el |> text |> JSON.parse
            for list_el in data["itemListElement"]
                push!(crumbs_links, (list_el["name"], list_el["item"]))
            end
            crumbs_unset = false
        end
        title_unset || sub_unset || crumbs_unset || break
    end
    menu_links = globvar(:menu; default=[])
    set_header(;title, subtitle, img_url=locvar(:image; default=globvar(:author_image)), menu_links)
end

function breadcrumbs_tags()
	for (name, link) in crumbs_links
        write(crumbs_io, "<breadcrumb url=\"")
        write(crumbs_io, link)
        write(crumbs_io, "\" text=\"")
        write(crumbs_io, name)
        write(crumbs_io, "\" />")
    end
    String(take!(crumbs_io))
end

# function yandex_related(file)

# end

const content_sel = Selector("body")
const head_sel = Selector("head")
const turbo_item_content = HTMLElement(:body)
const io_item = IOBuffer()
@doc "Generates a turbo page feed item from a html file."
function turboitem(file; cosel=content_sel)
    html = parsehtml(read(file, String))
    # content = Cascadia.matchFirst(cosel, html.root)
    head = Cascadia.matchFirst(head_sel, html.root)
    body = Cascadia.matchFirst(sel"body", html.root)

    empty!(turbo_item_content.children)
    empty!(turbo_item_content.attributes)

    page_lang[] = getattr(html.root, "lang")
    process_head(head)
   """
<item turbo="true">
            <!-- Page information -->
            <turbo:extendedHtml>true</turbo:extendedHtml>
            <link>$(page_url[])</link>
            <language>$(page_lang[])</language>
            <!-- <turbo:source></turbo:source> -->
            <!-- <turbo:topic></turbo:topic> -->
            <pubDate>$(page_date[])</pubDate>
            <author>$(globvar(:author))</author>
            <metrics>
                <yandex schema_identifier="$(page_id[])">
                    <breadcrumblist>
                        $(breadcrumbs_tags())
                    </breadcrumblist>
                </yandex>
            </metrics>
            <!-- <yandex:related></yandex:related> -->
            <turbo:content>
                <![CDATA[
                    $(header)
                    $(body)
                ]]>
            </turbo:content>
</item>
"""
end

@inline get_file_feed(dir, n) = joinpath(dir, "turbo-$n.xml")

function init_feed(io)
	"""<?xml version = "1.0" encoding = "UTF-8"?>
    <rss xmlns:yandex="http://news.yandex.ru"
    xmlns:media="http://search.yahoo.com/mrss/"
    xmlns:turbo="http://turbo.yandex.ru"
    version="2.0">
    <channel>
        <!-- Information about the source site  -->
        <title>$(globvar(:website_title))</title>
        <link>$(globvar(:website_url))</link>
        <description>$(globvar(:website_description))</description>
        <language>$(globvar(:lang_code))</language>
        <!-- <turbo:analytics></turbo:analytics> <turbo:adNetwork></turbo:adNetwork> -->
    """ |> x -> write(io, x)
end

function write_feed(io, dir, file_feed, feed_counter)
end

@doc "Create yandex turbo pages for a directory, outputs an RSS feed.
These feeds need to be added to https://webmaster.yandex.com under 'Data Sources' tab."
function turbodir(target=nothing; extensions=[".html"], dirs=["posts", "tag", "reads", "_rss"], ex_dirs=["amp"])
    isnothing(target) && begin target = path(:site) end
    @assert isdir(target) "Path $target is not a valid directory"
    turbo_dir[] = dir = isdirpath(target) ? dirname(target) : target
    rpl = Regex("^$dir/") => ""
    cwd = pwd()
    cd(dir)

    item_counter = 0
    feed_counter = 1
    init_header()
    file_feed = get_file_feed(dir, feed_counter)
    io_feed = IOBuffer()
    init_feed(io_feed)
    try
        proc_dirs = Dict{String, Nothing}()
        for file in walkfiles(dir; exts=Set(extensions),
                              dirs=Set(dirs),
                              ex_dirs=Set(ex_dirs),
                              subdir=false)
            basename(file) === "404.html" && continue
            out_file = joinpath(dir, replace(file, rpl))
            out_dir = dirname(out_file)
            if out_dir ∉ keys(proc_dirs) && !isdir(out_dir)
                mkpath(out_dir)
                proc_dirs[out_dir] = nothing
            end
            item = turboitem(file)
            (item_counter > 999 ||
                io_feed.size + sizeof(item) > Int(15e6)) && begin
                item_counter = 0
                write(io_feed, "</channel></rss>")
                write(file_feed, String(take!(io_feed)))
                init_feed(io_feed)
                feed_counter += 1
                file_feed = get_file_feed(dir, feed_counter)
            end
            write(io_feed, item)
            item_counter += 1
        end
        write(io_feed, "</channel></rss>")
        write(file_feed, String(take!(io_feed)))
        if feed_counter > 100
            @warn "Yandex only support 100 feed lists."
        end
    finally
        cd(cwd)
        close(io_feed)
    end
end

end

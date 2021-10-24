module FranklinContent

using FranklinUtils
using Franklin; const fr = Franklin;
using DataStructures:DefaultDict
using Franklin: convert_md, convert_html, pagevar, globvar, locvar, path, refstring
using Dates: DateFormat, Date
using Memoization
using Gumbo: HTMLElement, getattr

macro unimp(fname)
    quote
        function $(esc(fname))()
            throw("unimplemented")
        end
    end
end

@doc "Wrapper for Franklin.locvar."
function hfun_locvar(args)
	name = args[1];
    locvar(Symbol(name))
end

@doc "Text wrapped in an HTML tag with a specified color."
function hfun_color(args)
    txt = args[1]
    color = args[2]
    return "<span color=\"$color\">$txt</span>"
end

@doc "Prepend `website_url` to PATH."
@memoize function website_url(path)
    joinpath(globvar(:website_url), path)
end

@doc "Process a franklin markdown page and return the output HTML."
function page_content(loc::String)
    raw = read((path(:folder) * "/" * loc * ".md"), String)
    m = convert_md(raw; isinternal=true)
    # remove all `{{}}` functions
    m = replace(m, r"{{.*?}}" => "")
    convert_html(m)
end

@doc "The page description, otherwise the website description."
function hfun_page_desc()
	desc = locvar(:rss_description)
    if desc === ""
        return globvar(:website_description)
    end
    desc
end


@doc "All the posts files (.md) in the `:posts_path` directory."
function iter_posts()
    posts_list = globvar(:posts_path) |> dirname |> basename |> readdir
    filter!(f -> endswith(f, ".md") && f != "index.md" && !startswith(f, "."), posts_list)
    return posts_list
end

@doc "HTML list of recent posts.
arg1: the root path of all the posts
arg2: how many posts to display"
function hfun_recent_posts(m::Vector{String})
    @assert length(m) < 3 "only two arguments allowed for recent posts (the number of recent posts to pull and the path)"
    n = parse(Int64, m[1])
    posts_path = length(m) == 1 ? "posts/" : m[2]
    list = readdir(dirname(posts_path))
    filter!(f -> endswith(f, ".md") && f != "index.md" && !startswith(f, "."), list)
    markdown = ""
    posts = []
    df = DateFormat("mm/dd/yyyy")
    for (_, post) in enumerate(list)
        fi = posts_path * splitext(post)[1]
        push!(
            posts,
            (
                title = pagevar(fi, :title),
                link = fi,
                date = pagevar(fi, :date),
                description = pagevar(fi, :rss_description),
            ),
        )
    end
    # pull all posts if n <= 0

    n = n >= 0 ? n : length(posts) + 1
    for ele in
        view(sort(posts, by=x -> Date(x.date, df), rev=true), 1:min(length(posts), n))
        markdown *= "* [($(ele.date)) $(ele.title)](../$(ele.link)) -- _$(ele.description)_ \n"
    end

    return fd2html(markdown, internal=true)
end

function tags_sorter(p)
    pvd = pagevar(p, "date")
    if isnothing(pvd)
        return Date(Dates.unix2datetime(stat(p * ".md").ctime))
    end
    return pvd
end

function hfun_taglist_desc(tags::AbstractVector)
    hfun_taglist_desc(tags[1])
end

@doc "All the pages for a particular tag."
function hfun_taglist_desc(tag::Union{Nothing,AbstractString}=nothing)
    if isnothing(tag)
        tag = locvar(:fd_tag)
        if isnothing(tag)
            throw("need a tag")
        end
    end

    c = IOBuffer()
    write(c, "<ul>")

    all_tags = globvar(:fd_tag_pages)
    # tags have yet to be processed
    if isnothing(all_tags)
        all_tags = fr.invert_dict(globvar(:fd_page_tags))
    end
    tag ∉ keys(all_tags) && begin
        @warn "tag: $tag not found"
        return ""
    end
    rpaths = all_tags[tag]
    sort!(rpaths, by=tags_sorter, rev=false)

    for rpath in rpaths
        title = pagevar(rpath, "title")
        if isnothing(title)
            title = "/$rpath/"
        end
        url = get_url(rpath)
        desc = pagevar(rpath, "rss_description")
        write(c, "<li><a href=\"$url\">$title</a> -- $desc </li>")
    end
    write(c, "</ul>")
    html = String(take!(c))
    close(c)
    return html
end

@doc "The base font size for tags in the tags cloud (rem)."
const tag_cloud_font_size = 1;

@doc "Tag list to display in the post footer."
function hfun_addtags()
    if is_post()
        c = IOBuffer()
        write(c, "<div id=\"post-tags-list\">\nPost Tags:\n")
        for tag in locvar(:tags)
            println(c, "<span class=\"post-tag\">", tag_link(tag), ", </span>")
        end
        # remove comma at the end
        str = chop(String(take!(c)); tail=10) * "</span></div>"
        close(c)
        str
    else
        ""
    end
end

@doc "The HTML link to a page display all the tags."
function tag_link(tag, font_size::Union{Float64,Nothing}=nothing)
    style = ""
    if !isnothing(font_size)
        style = "font-size: $(font_size)rem"
    end
    link = join([globvar(:website_url), globvar(:tag_page_path), tag], "/")
    "<a href=\"$link\" style=\"$style\"> $tag </a>"
end

@doc "Tag cloud, tags with font size dependent on the number of posts that use it."
function hfun_tags_cloud()
    tags = DefaultDict{String,Int}(0)
    # count all the tags
    for p in iter_posts()
        fi = "posts/" * splitext(p)[1]
        for t in pagevar(fi, :tags)
            tags[t] += 1
        end
    end
    ordered_tags = [k for k in keys(tags)]
    sort!(ordered_tags)
    # normalize counts
    counts = [tags[t] for t in ordered_tags]
    min, max = extrema(counts)
    sizes = @. ((counts - min) / (max - min)) + 1
    # make html with inline size based on counts
    c = IOBuffer()
    write(c, "<div id=tag_cloud>")
    icon = ""
    tag_path = globvar(:tag_page_path)
    for (n, (tag, count)) in enumerate(zip(ordered_tags, counts))
        icon_name = icons_tags[tag]
        if icon_name !== ""
            icon = "<i class=\"fa $icon_name icon\"></i>"
        else
            icon = ""
        end
        write(
            c,
            "<a href=\"$(joinpath("/", tag_path, tag))\" style=\"font-size: $(sizes[n] * tag_cloud_font_size)rem\"> $icon $tag </a>",
        )
    end
    write(c, "</div>")
    str = String(take!(c))
    close(c)
    str
end

@doc "The absolute or relative post link from a file path."
function post_link(file_path, code=""; rel=true, amp=false)
    let name = splitext(file_path)[1]
        joinpath(rel ? "/" : globvar(:website_url),
                 amp ? "amp/" : "",
                 code,
                 replace(name, r"(index|404)$" => ""))
    end
end

@doc "HTML for the page title, using `rss_description` for the subtitle."
function hfun_post_title()
    path = locvar(:fd_rpath)
    if (!isnothing(match(r"posts/.+", path)) && path !== "posts/index.html")

        link = post_link(path)
        title = locvar(:title)
        desc = locvar(:rss_description)
        "
            <div>
            <h1 id=\"title\"><a href=\"$link\">$title</a></h1>
            <blockquote id=\"page-description\" style=\"font-style: italic;\">
                $desc
            </blockquote>
            </div>
          "
    else
        ""
    end
end

@doc "A colored (var(--\$color)) star."
function hfun_star(args)
    color = args[1]
    "<span style=\"color:var(--$color); margin-left: 0.2rem;\"><i class=\"fa fa-star\" aria-hidden=\"true\"></i></span>"
end

@doc "The tag of the current page, none otherwise."
function hfun_tag_title(prefix="Tag: ", default="Tags")
    # NOTE: franklin as {{if else}} and {{isdef}}
    c = IOBuffer()
    write(c, "<div id=\"tag-name\">")
    let tag = locvar(:fd_tag),
        prefix = tag === "about" || tag === "lightbulbs" ? "" : prefix
        if tag != ""
            write(c, prefix)
            write(c, tag)
        else
            # write(c, locvar(:title))
            write(c, default)
        end
        write(c, "</div>")
    end
    str = String(take!(c))
    close(c)
    str
end

@doc "The (modified) biographic details from the field `bio.md` located in the :assets franklin folder."
function hfun_insert_bio()
    let bio = read(joinpath(path(:assets), "bio.md"), String) |>
        x -> convert_md(x; isinternal=true)
        replace(bio, "{{bio_link}}" => """<a title="Geo Link" rel="nofollow noopener noreferrer" href="$(locvar(:geo_link))"
target="_blank"><i class="fas fa-fw fa-map-marker-alt" aria-hidden="true"></i></a>
""")
    end
end

@doc "The evaluated `place.html` file located in the :layout franklin folder."
function hfun_about_place()
    joinpath(path(:layout), "place.html") |>
        x -> read(x, String) |>
        fr.convert_html
end

@doc "Check if page is an index page."
function is_index(path)
    !isnothing(match(r".*/index\.(html|md)", path))
end

@doc "Regex expression for posts path"
@memoize function posts_path_rgx(posts_path)
    Regex("$(lstrip(posts_path, '/'))/.+")
end

@doc "Check if page is a post."
function is_post()
    path = locvar(:fd_rpath)
    (!isnothing(match(posts_path_rgx(globvar(:posts_path)), path)) && !is_index(path))
end

@doc "Check if page is a tags page."
function is_tag(tag)
    path = locvar(:fd_rpath)
    !isnothing(match(r"$tag/index.(html|md)", path))
end

@doc "The utteranc.es comments widget (if the page is a post)."
function hfun_addcomments()
    if is_post()
        html_str = """
        <script src="https://utteranc.es/client.js"
            repo="untoreh/untoreh.github.io"
            issue-term="pathname"
            label="Comment"
            crossorigin="anonymous"
            async>
        </script>
    """
        return html_str
    else
        ""
    end
end

@doc "Add edited date at appropriate pages."
function hfun_editedpage(tag="lightbulbs")
    if is_post() || is_tag(tag)
        locvar(:fd_mtime)
    else
        ""
    end
end

@doc "Inserts a file relative to the current page."
function hfun_insert_path(args)
    (pwd(), dirname(locvar(:fd_rpath)), args[1]) |> (x) -> joinpath(x...) |> readlines |> join
end

# TODO:remove stylings
@doc "IMG html tag, where the `alt` attribute defaults to the image name."
function hfun_insert_img(args)
    if args[2] === "none"
        "<img alt=\"$(splitext(args[1])[1])\" " *
            " src=\"/assets/posts/img/$(args[1])\"" *
            " style=\"float: none; padding: 0.5rem; " *
            " margin-left:auto; margin-right: auto; display: block; \">"
    else
        "<img alt=\"$(splitext(args[1])[1])\" " *
            " src=\"/assets/posts/img/$(args[1])\" " *
            " style=\"float: $(args[2]); padding: 0.5rem;\">"
    end
end

@doc "A dict mapping of tag names to font-awesome icons."
icons_tags =
    DefaultDict("",
                Dict(
                    "programming" => "fas fa-code",
                    "about" => "fas fa-wrench",
                    "lightbulbs" => "fas fa-lightbulb",
                    "apps" => "fab fa-android",
                    "crypto" => "fab fa-bitcoin",
                    "guides" => "fas fa-directions",
                    "hosting" => "fas fa-server",
                    "linux" => "fab fa-linux",
                    "mobile" => "fas fa-mobile-alt",
                    "net" => "fas fa-network-wired",
                    "nice-to-haves" => "fas fa-candy-cane",
                    "opinions" => "fas fa-blog",
                    "philosophy" => "fas fa-pen-alt",
                    "poetry" => "fas fa-feather",
                    "shell" => "fas fa-user-ninja",
                    "cooking" => "fas fa-utensils",
                    "games" => "fas fa-gamepad",
                    "software" => "fas fa-code-branch",
                    "stats" => "fas fa-chart-bar",
                    "tech" => "fas fa-pager",
                    "agri" => "fas fa-tree",
                    "things-that-should-not-be published" => "fas fa-comment-dots",
                    "tools" => "fas fa-tools",
                    "trading" => "fas fa-chart-line"
                ))
@doc "Wraps the `icon_tags` dict."
hfun_icon_tag(tag) = icons_tags[tag]

@doc "Either the article image, or the author image or the website logo."
function image_url()
    locvar(:images;
           default=[globvar(:author_image;
                            default=globvar(:logo))]) |>
                                first |>
                                x -> joinpath(globvar(:website_url), lstrip(x, '/'))
end

@doc "Wrapper to call an arbitrary function as an latex function."
function lx_fun(com::Franklin.LxCom, _)
    args = lxproc(com) |> split
    let f = getfield(Main, Symbol(args[1]))
        length(args) > 1 ? f(args[2:end]...) : f()
    end
end

@doc "A canonical link html element"
function canonical_link_el(url::AbstractString="")
    ln = HTMLElement(:link)
    ln.attributes["rel"] = "canonical"
    ln.attributes["href"] = url
    ln
end

@doc "The canonical url from franklin current (local) page vars."
@inline function canonical_url(;code="", amp=false)
    locvar(:fd_rpath; default="") |> x -> post_link(x, code; rel=false, amp)
end

@doc "The canonical url of a given file path."
@inline function canonical_url(path; code="", amp=false)
    post_link(path, code; rel=false, amp)
end

@doc "The html link tag for the current canonical url."
function hfun_canonical_link()
	"<link rel=\"canonical\" href=\"" *
        canonical_url() *
        "\">"
end

@doc "The html link tag for the canonical url of the current TAG page."
function hfun_canonical_link_tag()
    tag_path = joinpath(locvar(:tag_page_path), locvar(:fd_tag))
	"<link rel=\"canonical\" href=\"" *
        canonical_url(tag_path) *
        "\">"
end

@doc "The html link tag for the canonical url of the given path."
function hfun_canonical_link(args)
	"<link rel=\"canonical\" href=\"" *
        canonical_url(args[1]) *
        "\">"
end

@memoize function feed_name(parts...)
    joinpath(parts..., globvar(:rss_file) * ".xml")
end

@doc "The RSS feed link tag."
function hfun_rss_link()
    "<link rel=\"alternate\" type=\"application/rss+xml\" href=\"" *
         feed_name(globvar(:website_url)) * "\" title=\"$(globvar(:website_title))\">"
end

function hfun_rss_link_tag()
    "<link rel=\"alternate\" type=\"application/rss+xml\" href=\"" *
       feed_name(globvar(:website_url), globvar(:tag_page_path), refstring(locvar(:fd_tag))) *
       "\" title=\"$(globvar(:website_title))\">"
end

function hfun_rss_url()
	(isnothing(locvar(:fd_tag)) &&
        feed_name(globvar(:website_url))) ||
        feed_name(globvar(:website_url), globvar(:tag_page_path))
end

@doc "The html link tag for the AMP url of the current page."
function hfun_amp_link()
    # @show keys(fr.LOCAL_VARS)
	"<link rel=\"amphtml\" href=\"" *
        canonical_url(;amp=true) *
        "\">"
end

@doc "The html link tag for the AMP url of the given path."
function hfun_amp_link(args)
	"<link rel=\"amphtml\" href=\"" *
        canonical_url(args[1] ;amp=true) *
        "\">"
end

@doc "The html link tag for the AMP url of the current TAG path."
function hfun_amp_link_tag()
    tag_path = joinpath(locvar(:tag_page_path), locvar(:fd_tag))
	"<link rel=\"amphtml\" href=\"" *
        canonical_url(tag_path ;amp=true) *
        "\">"
end

@doc "A breadcrumbs list (title, path), where the last element is left to be filled."
function base_crumbs()
	[("Home", globvar(:website_url)),
     ("Posts List", joinpath(globvar(:website_url),
                             globvar(:posts_path))),
     ("", "")]
end

@doc "Breadcrumbs for the current page being evaluated."
function post_crumbs()
    crumbs = base_crumbs()
    crumbs[end] = (locvar(:title; default=""), canonical_url())
    crumbs
end

function tags_crumbs()
    tag_path = joinpath(locvar(:tag_page_path), locvar(:fd_tag))
    [("Home", globvar(:website_url)),
     ("Tags List", joinpath(globvar(:website_url), globvar(:tag_page_path))),
     (locvar(:fd_tag; default=""), canonical_url(tag_path))]
end

function hfun_insertsearch()
    if locvar(:fd_rpath) === "search.md"
        return read(joinpath(fr.path(:layout), "lunr_include.html"), String)
    end
    ""
end

function franklincontent_hfuncs()
    for sym in names(@__MODULE__; all=true)
        if startswith(string(sym), "hfun_")
            @eval export $sym
        end
    end
end

@inline function isldjson(el::HTMLElement)
    getattr(el, "type", "") === "application/ld+json"
end

@inline function islink(el::HTMLElement, rel="canonical")
    getattr(el, "rel", "") === rel
end

function load_amp()
    include(joinpath(dirname(@__FILE__), "amp.jl"))
    @eval export AMP
end

function load_minify()
    include(joinpath(dirname(@__FILE__), "minify.jl"))
    @eval export FranklinMinify
end

function load_yandex()
    include(joinpath(dirname(@__FILE__), "yandex.jl"))
    @eval export Yandex
end

function load_opg()
    include(joinpath(dirname(@__FILE__), "opg.jl"))
    @eval export OPG
end

export tags_crumbs, post_crumbs, page_content, iter_posts, tag_link, post_link, is_index, is_post, is_tag, lx_fun

include("files.jl")

end # module

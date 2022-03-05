module OPG

using Gumbo
using Memoization
using Franklin: globvar, locvar
using FranklinContent: @unimp, is_post, is_index, post_link, image_url

const tbuf = IOBuffer()

export hfun_opg_prefix, hfun_opg_franklin

@memoize function _prefix(;article, website, book, profile, video, music)
    prefix = "og: https://ogp.me/ns#"
    article && (prefix *= " article: http://ogp.me/ns/article#")
    book && (prefix *= " book: http://ogp.me/ns/book#")
    profile && (prefix *= " profile: http://ogp.me/ns/profile#")
    website && (prefix *= " website: http://ogp.me/ns/website#")
    music && (prefix *= " music: http://ogp.me/ns/music#")
    video && (prefix *= " video: http://ogp.me/ns/video#")
    prefix
end

function hfun_opg_prefix()
    _prefix(;article=true, website=true, book=false, profile=false, video=false, music=false)
end

@doc "Encloses a property and its content into a meta tag."
@inline function write_meta_tag(prop, content)
    write(tbuf, "<meta property=\"og:")
    write(tbuf, prop)
    write(tbuf, "\" content=\"")
    write(tbuf, content)
    write(tbuf, "\" />\n")
end

function _basic(;title, type, url, image, prefix="")
    if prefix !== ""
        write_meta_tag("$(prefix):title", title)
        write_meta_tag("$(prefix):type", type)
        write_meta_tag("$(prefix):url", url)
        write_meta_tag("$(prefix):image", image)
    else
        write_meta_tag("title", title)
        write_meta_tag("type", type)
        write_meta_tag("url", url)
        write_meta_tag("image", image)
    end
end

function _optional(;description, site_name, locale, audio, video, determiner)
    isempty(description) || write_meta_tag("description", description)
    isempty(site_name) || write_meta_tag("site_name", site_name)
    isempty(locale) || write_meta_tag("locale", locale)
    isempty(audio) || write_meta_tag("audio", audio)
    isempty(video) || write_meta_tag("audio", video)
    isempty(determiner) || write_meta_tag("audio", determiner)
end

@doc "Generates an HTML String containing opengraph meta tags for one item."
function opengraph_tags(as_string=false;title, type, url, image, description="", site_name="",
                        locale="", audio="", video="", determiner="")
    _basic(; title, type, url, image)
    _optional(; description, site_name, locale, audio, video, determiner)
    as_string && String(take!(tbuf))
end

@doc "Writes the additional metadata structures to the specified PROP."
function structure(prop; url, secure_url="", mime="", width="", height="", alt="")
        write_meta_tag("$(prop):url", url)
        isempty(secure_url) ||
            write_meta_tag("$(prop):secure_url", secure_url)
        isempty(mime) ||
            write_meta_tag("$(prop):type", mime)
        prop === "audio" && return
        isempty(width) ||
            write_meta_tag("$(prop):width", width)
        isempty(height) ||
            write_meta_tag("$(prop):height", height)
        isempty(alt) ||
            write_meta_tag("$(prop):alt", alt)
end

@doc "Write meta tags for an article object type."
function article(;title, type, url, image, author, tag=[], section="", pub, mod, exp="")
    _basic(;title, type, url, image, prefix="article")
    write_meta_tag("article:author", author)
    write_meta_tag("article:published_time", pub)
    write_meta_tag("article:modified_time", mod)
    isempty(exp) || write_meta_tag("article:expiration_time", exp)
    isempty(section) || write_meta_tag("article:section", section)
    for t in tag
        write_meta_tag("article:tag", t)
    end
end

@doc "Twitter card meta tags"
function twitter_meta(prop, content)
    write(tbuf, "<meta name=\"twitter:")
    write(tbuf, prop)
    write(tbuf, "\" content=\"")
    write(tbuf, content)
    write(tbuf, "\"/>")
end

@memoize function _franklin_langs()
    [lang_name for (lang_name, _) in globvar(:languages)]
end

@doc "Meta tags for franklin site."
function hfun_opg_franklin()
    path = locvar(:fd_rpath)
    locale = globvar(:locale; default="en_US")
    image = image_url()
    if is_post()
        title=locvar(:title)
        description=locvar(:rss_description)
        type="article"
        url=post_link(path; rel=false)
        site_name=globvar(:website_title)
        opengraph_tags(;title, type, url, image, description, site_name, locale)
    else
        title=globvar(:website_title)
        description=globvar(:website_description)
        type="website"
        url=globvar(:website_url)
        opengraph_tags(;title, type, url, image, description, locale)
    end
    twitter_meta("card", "summary")
    twitter_meta("creator", globvar(:twitter_user))

    String(take!(tbuf))
end

@unimp music_song
@unimp music_album
@unimp music_playlist
@unimp music_radio_station
@unimp video_movie
@unimp video_episode
@unimp video_tv_show
@unimp video_other
@unimp profile
@unimp book
@unimp profile

end

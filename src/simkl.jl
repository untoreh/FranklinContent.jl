module Simkl

using HTTP
using JSON
using Dates: now
using Base64

const redirect_uri = Ref("urn:ietf:wg:oauth:2.0:oob")
const simkl_oauth = "https://simkl.com/oauth/authorize"
const simkl_pin = "https://api.simkl.com/oauth/pin"
const simkl_all_items = "https://api.simkl.com/sync/all-items"

const cache_path = Ref(get(ENV, "XDG_CACHE_HOME", "$(ENV["HOME"])/.cache"))
const creds_path = Ref(joinpath(cache_path[], "simkl_creds.json"))
const items_path = Ref(joinpath(cache_path[], "simkl_items.json"))
const creds = IdDict{String, String}()
merge!(creds, JSON.parse(read(creds_path[], String)))
const access_token = Ref(get(creds, "access_token", ""))
const headers = []
const imdb_url =

@inline function tv_url(ids)
    if "imdb" ∈ keys(ids)
        "https://www.imdb.com/title/" * ids["imdb"]
    elseif "tvdbslug" ∈ keys(ids)
        "https://www.thetvdb.com/series/" * ids["tvdbslug"]
    elseif "anidb" ∈ keys(ids)
        "https://anidb.net/anime/" * ids["anidb"]
    else
        ""
    end
end

@inline function simkl_url(type, show::String)
    "https://simkl.com/" * type * "/" * show
end

function get_simkl_pin()
    query = Dict("client_id" => creds["client_id"],
                 "redirect_uri" => redirect_uri[])
    res = HTTP.request("GET", simkl_pin, headers; query)
    body = JSON.parse(String(res.body))
    body["user_code"], body["verification_url"]
end

function get_simkl_token(code)
    query = Dict("client_id" => creds["client_id"])
    res = HTTP.request("GET", joinpath(simkl_pin, code), headers; query)
    body = JSON.parse(String(res.body))
    get(body, "access_token", "")
end

function set_headers!()
    empty!(headers)
    push!(headers, "Content-Type" => "application/json")
    # push!(headers, "Authorization" => "Bearer $(base64encode(access_token[]))")
    push!(headers, "Authorization" => "Bearer $(access_token[])")
    # push!(headers, "Authorization" => "Bearer $(base64encode(creds["client_secret"]))")
    push!(headers, "simkl-api-key" => creds["client_id"])
end

@doc "Checks if an ACCESS_TOKEN key is present in the file pointed by CREDS_PATH. If not present initiate
a pin verification procedure."
function simkl_auth()
    token = ""
    if isempty(get(creds, "access_token", ""))
        code, url = get_simkl_pin()
        display("Verify pin: $code at $url")
        sl = 1
        while true
            token = get_simkl_token(code)
            isempty(token) || break
            sleep(sl)
            sl += 1
        end
        creds["code"] = code
        creds["access_token"] = token
        access_token[] = token
        write(creds_path[], JSON.json(creds))
        display("Saved new access token to $(creds_path[])")
    else
        display("Access token already available.")
    end
    set_headers!()
end

function simkl_fetch_all_items(type="", status="")
    date_from = get(creds, "date_from", "")
    query = Dict()
    isempty(date_from) || begin
	    query["date_from"] = date_from
        if isfile(items_path[])
            prev_items = JSON.parse(read(items_path[], String))
        else
            prev_items = nothing
        end
    end
    set_headers!()
    res = HTTP.request("GET", joinpath(simkl_all_items, type, status), headers; query)
    if isnothing(prev_items)
        items_str = String(res.body)
        write(items_path[], items_str)
        prev_items = JSON.parse(items_str)
    else
        items = JSON.parse(String(res.body))
        if !isnothing(items)
            merge!(prev_items, items)
            write(items_path[], prev_items)
        end
    end
    creds["date_from"] = string(now())
    write(creds_path[], JSON.json(creds))
    prev_items
end

function simkl_get_all_items(update=false; kwargs...)
    if update || !isfile(items_path[])
        simkl_fetch_all_items(;kwargs...)
    else
	    JSON.parse(read(items_path[], String))
    end
end


@doc "Generates an HTML list of completed shows with links to simkl and imdb."
function simkl_completed_shows_list(types=["shows", "anime"], status=["completed", "watching"])
    io = IOBuffer()
	all_items = simkl_get_all_items()
    write(io, "<div class=\"shows_list\">")
    for tp in types
        el_tp = tp === "movies" ? "movie" : "show"
        type_items = all_items[tp]
        if length(type_items) > 0
            write(io, "<h3>")
            write(io, titlecase(tp))
            write(io, "</h3><ul id=\"$(tp)\">")
        for itm in type_items
            if itm["status"] ∈ status
                write(io, "<li class=\"show\">")
                ids = itm[el_tp]["ids"]
                write(io, "<a class=\"simkl\" href=\"$(simkl_url(tp, string(ids["simkl"])))\" >")
                write(io, itm[el_tp]["title"])
                write(io, "</a>")
                write(io, "<a class=\"imdb\" href=\"$(tv_url(ids))\">")
                write(io, "<i class=\"fas fa-film\"></i>")
                write(io, "</a>")
                write(io, "</li>")
            end
        end
            write(io, "</ul>")
        end
    end
    write(io, "</div>")
    list = String(take!(io))
    close(io)
    list
end

function hfun_simkl_list()
	simkl_completed_shows_list()
end

# howcomp = 0
# watched_shows = Set()
# for el in items["shows"]
#     if el["status"] === "completed"
#         title = el["show"]["title"]
#         display(title)
#         push!(watched_shows, title)
#         howcomp += 1
#     end
# end
# @show "you have watched $howcomp shows"

export hfun_simkl_list

end

module IndexNow

using Franklin; const fr = Franklin

const apikey = Ref("")
const search_engines = (
    "bing.com",
    "yandex.com",
)

@doc "Set the indexnow apikey, if KEY is empty use the environment variable INDEXNOW_APIKEY."
function set_apikey!(key="")
	apikey[] = isempty(key) ? get(ENV, "INDEXNOW_APIKEY", "") : key
    try
	    k = read(joinpath(:folder ∈ fr.PATHS ? fr.path(:folder) : pwd(), "$(apikey).txt"), String)
        @assert apikey[] === k
    catch
        throw("Couldn't find the api key text file, ensure it is present in website root directory.")
    end
end

function push_urls(urls=[])
    for u in urls

    end
end

end

module TwitterCard

using Conda
using PyCall: pyimport

const tbuf = IOBuffer()

function twitter_meta(prop, content)
    write(tbuf, "<meta name=\"twitter:")
    write(tbuf, prop)
    write(tbuf, "\" content=\"")
    write(tbuf, content)
    write(tbuf, "\"></meta>")
end

function twitter_card(content)
    twitter_meta("card", "summary")
end

function get_twitter_tools()
    try
        return pyimport("twitter")
    catch
        Conda.pip("install", "twitter")
        return pyimport("twitter")
    end
end

end

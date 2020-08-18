module Downloader

export download

include("Curl/Curl.jl")
using .Curl

function download(
    multi::Multi,
    url::AbstractString,
    io::IO,
    headers = Union{}[],
)
    easy = Easy()
    set_url(easy, url)
    for hdr in headers
        add_header(easy, hdr)
    end
    add_handle(multi, easy)
    for buf in easy.channel
        write(io, buf)
    end
    remove_handle(multi, easy)
    return io
end

end # module

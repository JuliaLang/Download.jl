include("setup.jl")

@testset "Downloads.jl" begin
    @testset "libcurl configuration" begin
        julia = "$(VERSION.major).$(VERSION.minor)"
        @test Curl.USER_AGENT == "curl/$(Curl.CURL_VERSION) julia/$julia"
        if VERSION > v"1.6-"
            @test Curl.SYSTEM_SSL == Sys.iswindows() | Sys.isapple()
        end
    end

    @testset "API coverage" begin
        value = "Julia is great!"
        base64 = "SnVsaWEgaXMgZ3JlYXQh"
        url = "$server/base64/$base64"
        headers = ["Foo" => "Bar"]
        # test with one argument
        path = download(url)
        @test isfile(path)
        @test value == read(path, String)
        rm(path)
        # with headers
        path = download(url, headers=headers)
        @test isfile(path)
        @test value == read(path, String)
        rm(path)

        @testset "Download with auto extension" begin
            url_CD = "$server/response-headers?Content-Disposition="
            path = download("$(url_CD)filename%3DJulia.jpg")
            @test isfile(path)
            @test endswith(path, ".jpg")
            rm(path)
            path = download("$(url_CD)filename*%3DJulia.jpg")
            @test isfile(path)
            @test endswith(path, ".jpg")
            rm(path)
            path = download("$server/robots.txt")
            @test isfile(path)
            @test endswith(path, ".txt")
            rm(path)
            path = download(server)
            # response.url protects against adding domain as extension
            @test !endswith(path, "org")
            rm(path)
        end
        # test with two arguments
        arg_writers() do path, output
            @arg_test output begin
                @test output == download(url, output)
            end
            @test isfile(path)
            @test value == read(path, String)
            rm(path)
            # with headers
            @arg_test output begin
                @test output == download(url, output, headers=headers)
            end
            @test isfile(path)
            @test value == read(path, String)
            rm(path)
        end

        # not an API test, but a convenient place to test this
        @testset "follow redirects" begin
            redirect = "$server/redirect-to?url=$(url_escape(url))"
            path = download(redirect)
            @test isfile(path)
            @test value == read(path, String)
            rm(path)
        end
    end

    @testset "get request" begin
        url = "$server/get"
        json = download_json(url)
        @test json["url"] == url
        resp = request(url)
        @test resp isa Response
        @test resp.proto == "https"
        @test resp.status == 200
    end

    # https://github.com/JuliaLang/Downloads.jl/issues/131
    @testset "head request" begin
        url = server * "/image/jpeg"
        output = IOBuffer()
        resp = request(url; method="HEAD", output=output)
        @test resp isa Response
        @test resp.proto == "https"
        @test resp.status == 200
        @test isempty(take!(output)) # no output from a `HEAD`
        len = parse(Int, Dict(resp.headers)["content-length"])

        # when we make a `GET` instead of a `HEAD`, we get a body with the content-length
        # returned from the `HEAD` request.
        resp = request(url; method="GET", output=output)
        bytes = take!(output)
        @test length(bytes) == len
    end

    @testset "put request" begin
        url = "$server/put"
        data = "Hello, world!"
        resp, json = request_json(url, input=IOBuffer(data))
        @test json["url"] == url
        @test json["data"] == data
    end

    @testset "post request" begin
        url = "$server/post"
        data = "Hello, world!"
        resp, json = request_json(url, input=IOBuffer(data), method="POST")
        @test json["url"] == url
        @test json["data"] == data
    end

    @testset "put from file" begin
        url = "$server/put"
        file = tempname()
        write(file, "Hello, world!")
        resp, json = request_json(url, input=file)
        @test json["url"] == url
        @test json["data"] == read(file, String)
        rm(file)
    end

    @testset "redirected get" begin
        url = "$server/get"
        redirect = "$server/redirect-to?url=$(url_escape(url))"
        json = download_json(url)
        @test json["url"] == url
    end

    @testset "redirected put" begin
        url = "$server/put"
        redirect = "$server/redirect-to?url=$(url_escape(url))"
        data = "Hello, world!"
        resp, json = request_json(redirect, input=IOBuffer(data))
        @test json["url"] == url
        @test json["data"] == data
    end

    @testset "redirected post" begin
        url = "$server/post"
        redirect = "$server/redirect-to?url=$(url_escape(url))"
        data = "Hello, world!"
        resp, json = request_json(redirect, input=IOBuffer(data), method="POST")
        @test json["url"] == url
        @test json["data"] == data
    end

    @testset "redirected put from file" begin
        url = "$server/put"
        redirect = "$server/redirect-to?url=$(url_escape(url))"
        file = tempname()
        write(file, "Hello, world!")
        resp, json = request_json(redirect, input=file)
        @test json["url"] == url
        @test json["data"] == read(file, String)
    end

    @testset "headers" begin
        url = "$server/headers"

        @testset "set headers" begin
            headers = ["Foo" => "123", "Header" => "VaLuE", "Empty" => ""]
            json = download_json(url, headers = headers)
            for (key, value) in headers
                @test header(json["headers"], key) == value
            end
            @test header(json["headers"], "Accept") == "*/*"
            @test header(json["headers"], "User-Agent") == Curl.USER_AGENT
        end

        @testset "override default header" begin
            headers = [
                "Accept"     => "application/tar"
                "User-Agent" => "MyUserAgent/1.0"
            ]
            json = download_json(url, headers = headers)
            @test header(json["headers"], "Accept") == "application/tar"
            @test header(json["headers"], "User-Agent") == "MyUserAgent/1.0"
        end

        @testset "override default header with empty value" begin
            headers = [
                "Accept"     => ""
                "User-Agent" => ""
            ]
            json = download_json(url, headers = headers)
            @test header(json["headers"], "Accept") == ""
            @test header(json["headers"], "User-Agent") == ""
        end

        @testset "delete default header" begin
        headers = [
            "Accept"     => nothing
            "User-Agent" => nothing
        ]
        json = download_json(url, headers = headers)
            @test !("Accept" in keys(json["headers"]))
            @test !("User-Agent" in keys(json["headers"]))
        end

        @testset "HTTP/2 user agent bug" begin
            json = download_json(url)
            @test header(json["headers"], "User-Agent") == Curl.USER_AGENT
            @sync for _ = 1:2
                @async begin
                    json = download_json(url)
                    @test header(json["headers"], "User-Agent") == Curl.USER_AGENT
                end
            end
        end
    end

    @testset "session support" begin
        downloader = Downloader()

        # This url will redirect to /cookies, which echoes the set cookies as json
        set_cookie_url = "$server/cookies/set?k1=v1&k2=v2"
        cookies = download_json(set_cookie_url, downloader=downloader)
        @test get(cookies, "k1", "") == "v1"
        @test get(cookies, "k2", "") == "v2"

        # As the handle is destroyed, subsequent requests have no cookies
        cookie_url = "$server/cookies"
        cookies = download_json(cookie_url, downloader=downloader)
        @test isempty(cookies)
    end

    @testset "netrc support" begin
        user = "gVvkQiHN62"
        passwd = "dlctfSMTno8n"
        auth_url = "$server/basic-auth/$user/$passwd"
        resp = request(auth_url)
        @test resp isa Response
        @test resp.status == 401  # no succesful authentication

        # Setup .netrc
        hostname = match(r"^\w+://([^/]+)"i, server).captures[1]
        netrc = tempname()
        open(netrc, "w") do io
            write(io, "machine $hostname login $user password $passwd\n")
        end

        # Setup config to point to custom .netrc (normally in ~/.netrc)
        downloader = Downloads.Downloader()
        downloader.easy_hook = (easy, info) ->
            Curl.setopt(easy, Curl.CURLOPT_NETRC_FILE, netrc)

        resp = request(auth_url, throw=false, downloader=downloader)
        @test resp isa Response
        @test resp.status == 200  # succesful authentication

        # Cleanup
        rm(netrc)
    end

    @testset "file protocol" begin
        @testset "success" begin
            path = tempname()
            data = rand(UInt8, 256)
            write(path, data)
            temp = download("file://$path")
            @test data == read(temp)
            output = IOBuffer()
            resp = request("file://$path", output = output)
            @test resp isa Response
            @test resp.proto == "file"
            @test resp.status == 0
            @test take!(output) == data
            rm(path)
        end
        @testset "failure" begin
            path = tempname()
            @test_throws RequestError download("file://$path")
            @test_throws RequestError request("file://$path")
            output = IOBuffer()
            resp = request("file://$path", output = output, throw = false)
            @test resp isa RequestError
        end
    end

    @testset "errors" begin
        @test_throws ArgumentError download("ba\0d")
        @test_throws ArgumentError download("good", "ba\0d")

        err = @exception download("xyz://domain.invalid")
        @test err isa RequestError
        @test err.code != 0
        @test startswith(err.message, "Protocol \"xyz\" not supported")
        @test err.response.proto === nothing

        err = @exception request("xyz://domain.invalid", input = IOBuffer("Hi"))
        @test err isa RequestError
        @test err.code != 0
        @test startswith(err.message, "Protocol \"xyz\" not supported")
        @test err.response.proto === nothing

        err = @exception download("https://domain.invalid")
        @test err isa RequestError
        @test err.code != 0
        @test startswith(err.message, "Could not resolve host")
        @test err.response.proto === nothing

        err = @exception request("https://domain.invalid", input = IOBuffer("Hi"))
        @test err isa RequestError
        @test err.code != 0
        @test startswith(err.message, "Could not resolve host")
        @test err.response.proto === nothing

        err = @exception download("$server/status/404")
        @test err isa RequestError
        @test err.code == 0 && isempty(err.message)
        @test err.response.status == 404
        @test contains(err.response.message, r"^HTTP/\d+(?:\.\d+)?\s+404\b")
        @test err.response.proto === "https"

        resp = request("$server/get", input = IOBuffer("Hi"))
        @test resp isa Response
        @test resp.status == 405
        @test contains(resp.message, r"^HTTP/\d+(?:\.\d+)?\s+405\b")
        @test err.response.proto === "https"

        path = tempname()
        @test_throws RequestError download("$server/status/404", path)
        @test !ispath(path)
    end

    @testset "concurrent requests" begin
        mine = Downloader()
        for downloader in (nothing, mine)
            have_lsof = Sys.which("lsof") !== nothing
            count_tcp() = Base.count(x->contains("TCP",x), split(read(`lsof -p $(getpid())`, String), '\n'))
            if have_lsof
                n_tcp = count_tcp()
            end
            delay = 2
            count = 100
            url = "$server/delay/$delay"
            t = @elapsed @sync for id = 1:count
                @async begin
                    json = download_json("$url?id=$id", downloader = downloader)
                    @test get(json["args"], "id", nothing) == ["$id"]
                end
            end
            @test t < 0.9*count*delay
            if have_lsof
                @test n_tcp == count_tcp()
            end
        end
    end

    @testset "request API" begin
        @testset "basic request usage" begin
            for status in (200, 300, 400)
                url = "$server/status/$status"
                resp, body = request_body(url)
                @test resp.url == url
                @test resp.status == status
                test_response_string(resp.message, status)
                @test all(hdr isa Pair{String,String} for hdr in resp.headers)
                headers = Dict(resp.headers)
                @test "content-length" in keys(headers)
            end
        end

        @testset "custom headers" begin
            url = "$server/response-headers?FooBar=VaLuE"
            resp, body = request_body(url)
            @test resp.url == url
            @test resp.status == 200
            test_response_string(resp.message, 200)
            headers = Dict(resp.headers)
            @test headers["foobar"] == "VaLuE"
        end

        @testset "url for redirect" begin
            url = "$server/get"
            redirect = "$server/redirect-to?url=$(url_escape(url))"
            resp, json = request_json(redirect)
            @test resp.url == url
            @test resp.status == 200
            test_response_string(resp.message, 200)
            @test json["url"] == url
        end

        @testset "timeouts" begin
            url = "$server/delay/2"
            @testset "download" begin
                @test_throws ArgumentError download(url, devnull, timeout = -1)
                @test_throws ArgumentError download(url, devnull, timeout = 0)
                @test_throws RequestError download(url, devnull, timeout = 1)
                @test_throws RequestError download(url, devnull, timeout = 0.5)
                @test download(url, devnull, timeout = 100) == devnull
                @test download(url, devnull, timeout = Inf) == devnull
            end
            @testset "request(throw = true)" begin
                @test_throws ArgumentError request(url, timeout = -1)
                @test_throws ArgumentError request(url, timeout = 0)
                @test_throws RequestError request(url, timeout = 1)
                @test_throws RequestError request(url, timeout = 0.5)
                @test request(url, timeout = 100) isa Response
                @test request(url, timeout = Inf) isa Response
            end
            @testset "request(throw = false)" begin
                @test request(url, throw = false, timeout = 1) isa RequestError
                @test request(url, throw = false, timeout = 0.5) isa RequestError
                @test request(url, throw = false, timeout = 100) isa Response
                @test request(url, throw = false, timeout = Inf) isa Response
            end
        end

        @testset "progress" begin
            url = "https://httpbingo.org/drip"
            progress = []
            dl_funcs = [
                download,
                (url; progress) ->
                    request(url, output=devnull, progress=progress)
            ]
            p_funcs = [
                (prog...) -> push!(progress, prog),
                (total, now) -> push!(progress, (total, now)),
                (total, now, _, _) -> push!(progress, (total, now)),
            ]
            for f in dl_funcs, p in p_funcs
                @testset "request" begin
                    empty!(progress)
                    f(url; progress = p)
                    @test progress[1][1] == 0
                    @test progress[1][2] == 0
                    @test progress[end][1] == 10
                    @test progress[end][2] == 10
                    @test issorted(p[1] for p in progress)
                    @test issorted(p[2] for p in progress)
                end
            end
        end
    end

    save_env = get(ENV, "JULIA_SSL_NO_VERIFY_HOSTS", nothing)
    delete!(ENV, "JULIA_SSL_NO_VERIFY_HOSTS")

    @testset "bad TLS" begin
        urls = [
            "https://wrong.host.badssl.com"
            "https://untrusted-root.badssl.com"
        ]
        @testset "bad TLS is rejected" for url in urls
            resp = request(url, throw=false)
            @test resp isa RequestError
            @test resp.code == Curl.CURLE_PEER_FAILED_VERIFICATION
        end
        @testset "easy hook work-around" begin
            local url
            easy_hook = (easy, info) -> begin
                Curl.set_ssl_verify(easy, false)
                @test info.url == url
            end
            # downloader-specific easy hook
            downloader = Downloader()
            downloader.easy_hook = easy_hook
            for outer url in urls
                resp = request(url, throw=false, downloader=downloader)
                @test resp isa Response
                @test resp.status == 200
            end
            # default easy hook
            Downloads.EASY_HOOK[] = easy_hook
            Downloads.DOWNLOADER[] = nothing
            for outer url in urls
                resp = request(url, throw=false)
                @test resp isa Response
                @test resp.status == 200
            end
            Downloads.DOWNLOADER[] = nothing
            Downloads.EASY_HOOK[] = nothing
        end
        ENV["JULIA_SSL_NO_VERIFY_HOSTS"] = "**.badssl.com"
        @testset "SSL no verify override" for url in urls
            resp = request(url, throw=false)
            @test resp isa Response
            @test resp.status == 200
        end
        delete!(ENV, "JULIA_SSL_NO_VERIFY_HOSTS")
    end

    @testset "SNI required" begin
        url = "https://juliahub.com" # anything served by CloudFront
        # secure verified host request
        resp = request(url, throw=false, downloader=Downloader())
        @test resp isa Response
        @test resp.status == 200
        # insecure unverified host request
        ENV["JULIA_SSL_NO_VERIFY_HOSTS"] = "**"
        resp = request(url, throw=false, downloader=Downloader())
        @test resp isa Response
        @test resp.status == 200
    end

    if save_env !== nothing
        ENV["JULIA_SSL_NO_VERIFY_HOSTS"] = save_env
    else
        delete!(ENV, "JULIA_SSL_NO_VERIFY_HOSTS")
    end

    @__MODULE__() == Main && @testset "ftp download" begin
        url = "ftp://xmlsoft.org/libxslt/libxslt-1.1.33.tar.gz"
        file = Downloads.download(url)
        @test isfile(file)
        @test filesize(file) == 3444093
        head = String(read!(open(file), Vector{UInt8}(undef, 16)))
        @test head == "\x1f\x8b\b\0\xa5T.\\\x02\x03\xec]{s۶"
    end

    @testset "grace cleanup" begin
        dl = Downloader(grace=1)
        Downloads.download("https://httpbingo.org/drip"; downloader=dl)
        Downloads.download("https://httpbingo.org/drip"; downloader=dl)
    end
end

Downloads.DOWNLOADER[] = nothing
GC.gc(true)

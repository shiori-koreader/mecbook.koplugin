local Client = require("api.client")

local json = {
    encode = function(t) return "ENC:" .. tostring(t.bookId) end,
    decode = function(s)
        if s == "{ok}" then return { ok = true } end
        if s == "{tok}" then return { token = "NEW" } end
        error("not json")
    end,
}

local function make(responses, extra)
    local env = { reqs = {}, sleeps = {}, tokens = nil }
    local i = 0
    local deps = {
        transport = function(req)
            env.reqs[#env.reqs + 1] = req
            i = i + 1
            return responses[i] or responses[#responses]
        end,
        json = json,
        sleep = function(s) env.sleeps[#env.sleeps + 1] = s end,
        version = "1.0",
        token = "OLD",
        refresh_token = "RT",
        on_tokens = function(t, r) env.tokens = { t, r } end,
    }
    for k, v in pairs(extra or {}) do deps[k] = v end
    env.c = Client.new(deps)
    return env
end

describe("client", function()
    it("sends the plugin user agent and bearer token", function()
        local env = make({ { code = 200, body = "{ok}" } })
        local ok, data = env.c:me()
        assert.is_true(ok)
        assert.is_true(data.ok)
        assert.equals("Mozilla/5.0 (X11; Linux x86_64) mecbook-koreader/1.0", env.reqs[1].headers["User-Agent"])
        assert.equals("Bearer OLD", env.reqs[1].headers["Authorization"])
        assert.equals("https://meclivros.mec.gov.br/api/backend/auth/me", env.reqs[1].url)
    end)

    it("refreshes once on 401 and retries with the new token", function()
        local env = make({
            { code = 401, body = "" },
            { code = 200, body = "{tok}", headers = { ["set-cookie"] = "refresh_token=RT2; Path=/" } },
            { code = 200, body = "{ok}" },
        })
        local ok = env.c:me()
        assert.is_true(ok)
        assert.equals(3, #env.reqs)
        assert.equals("Bearer NEW", env.reqs[3].headers["Authorization"])
        assert.same({ "NEW", "RT2" }, env.tokens)
    end)

    it("reads the new token from Set-Cookie", function()
        local env = make({
            { code = 401, body = "" },
            { code = 200, body = "", headers = { ["set-cookie"] = { "auth_token=FROMCOOKIE; Path=/" } } },
            { code = 200, body = "{ok}" },
        })
        assert.is_true(env.c:me())
        assert.equals("Bearer FROMCOOKIE", env.reqs[3].headers["Authorization"])
    end)

    it("gives up after a failed refresh", function()
        local env = make({ { code = 401, body = "" }, { code = 401, body = "" } })
        local ok, _, code = env.c:me()
        assert.is_false(ok)
        assert.equals(401, code)
        assert.equals(2, #env.reqs)
    end)

    it("stops everything after a 403", function()
        local env = make({ { code = 403, body = "waf" } })
        local ok, data = env.c:me()
        assert.is_false(ok)
        assert.equals("blocked", data)
        env.c:active_rentals()
        env.c:get_raw("/x")
        assert.equals(1, #env.reqs)
    end)

    it("backs off exponentially on 5xx for GET", function()
        local env = make({ { code = 503 }, { code = 502 }, { code = 200, body = "{ok}" } })
        assert.is_true(env.c:me())
        assert.same({ 1, 2 }, env.sleeps)
    end)

    it("gives up after three failed attempts", function()
        local env = make({ { code = 500 } })
        assert.is_false(env.c:me())
        assert.equals(3, #env.reqs)
    end)

    it("retries on network errors", function()
        local env = make({ { code = nil }, { code = 200, body = "{ok}" } })
        assert.is_true(env.c:me())
    end)

    it("never retries a POST", function()
        local env = make({ { code = 500, body = "" } })
        assert.is_false(env.c:checkout(7))
        assert.equals(1, #env.reqs)
        assert.equals("ENC:7", env.reqs[1].body)
    end)

    it("rejects truncated downloads", function()
        local env = make({ { code = 200, body = "abc", headers = { ["content-length"] = "10" } } })
        local ok, err = env.c:get_raw("https://meclivros.mec.gov.br/epub-proxy/x")
        assert.is_false(ok)
        assert.equals("incomplete_content", err)
    end)

    it("escapes search queries", function()
        local env = make({ { code = 200, body = "{ok}" } })
        env.c:search("dom casmurro", 1, 20)
        assert.equals("https://meclivros.mec.gov.br/api/backend/books/search?query=dom%20casmurro&page=1&limit=20", env.reqs[1].url)
    end)
end)

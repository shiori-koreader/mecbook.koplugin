local Client = {}
Client.__index = Client

local ORIGIN = "https://meclivros.mec.gov.br"
local MAX_ATTEMPTS = 3

-- deps:
--   transport({method,url,headers,body}) -> {code=number|nil, headers={}, body=string}
--   json.encode / json.decode
--   sleep(seconds)
--   version, token, refresh_token, on_tokens(token, refresh_token)
function Client.new(deps)
    local self = setmetatable({}, Client)
    self.transport, self.json, self.sleep = deps.transport, deps.json, deps.sleep or function() end
    self.user_agent = "Mozilla/5.0 (X11; Linux x86_64) mecbook-koreader/" .. (deps.version or "0")
    self.token, self.refresh_token, self.on_tokens = deps.token, deps.refresh_token, deps.on_tokens
    self.origin = deps.origin or ORIGIN
    self.blocked = false
    return self
end

local function cookie(headers, name)
    local set = headers and headers["set-cookie"]
    if type(set) == "table" then set = table.concat(set, "; ") end
    return type(set) == "string" and set:match(name .. "=([^;%s]+)") or nil
end

function Client:_send(method, path, body)
    local url = path:sub(1, 4) == "http" and path or (self.origin .. path)
    local headers = { ["User-Agent"] = self.user_agent, ["Accept"] = "application/json, */*" }
    if self.token and self.token ~= "" then headers["Authorization"] = "Bearer " .. self.token end
    local encoded
    if body ~= nil then
        encoded = self.json.encode(body)
        headers["Content-Type"] = "application/json"
    end
    return self.transport({ method = method, url = url, headers = headers, body = encoded })
end

function Client:_refresh()
    if not self.refresh_token or self.refresh_token == "" then return false end
    local res = self.transport({
        method = "POST",
        url = self.origin .. "/api/auth/refresh",
        headers = { ["User-Agent"] = self.user_agent, ["Cookie"] = "refresh_token=" .. self.refresh_token },
    })
    if res.code == 403 then self.blocked = true end
    if not res.code or res.code < 200 or res.code >= 300 then return false end

    local token
    if res.body and res.body ~= "" then
        local ok, data = pcall(self.json.decode, res.body)
        if ok and type(data) == "table" then
            token = data.token or data.access_token or data.auth_token
                or (type(data.data) == "table" and (data.data.token or data.data.access_token)) or nil
        end
    end
    token = token or cookie(res.headers, "auth_token")
    self.refresh_token = cookie(res.headers, "refresh_token") or self.refresh_token
    if not token then return false end
    self.token = token
    if self.on_tokens then self.on_tokens(self.token, self.refresh_token) end
    return true
end

-- Returns res (transport result) after applying the policies: stop on 403, one refresh on 401,
-- backoff on 5xx/network errors (GET only: retrying a POST could repeat a checkout or return).
function Client:_run(method, path, body)
    if self.blocked then return { code = 403, blocked = true } end
    local res
    for attempt = 1, MAX_ATTEMPTS do
        res = self:_send(method, path, body)
        if res.code == 403 then
            self.blocked = true
            return res
        end
        if res.code == 401 and not self._refreshed then
            self._refreshed = true
            local refreshed = self:_refresh()
            self._refreshed = false
            if not refreshed then return res end
            res = self:_send(method, path, body)
        end
        local transient = res.code == nil or res.code >= 500
        if not transient or method ~= "GET" or attempt == MAX_ATTEMPTS then return res end
        self.sleep(2 ^ (attempt - 1))
    end
    return res
end

-- Returns ok, data, code. `data` is the decoded JSON body (or the raw body if it is not JSON).
function Client:request(method, path, body)
    local res = self:_run(method, path, body)
    if res.blocked or res.code == 403 then return false, "blocked", 403 end
    if not res.code then return false, "network_error", nil end
    local data = res.body
    if data and data ~= "" then
        local ok, decoded = pcall(self.json.decode, data)
        if ok and decoded ~= nil then data = decoded end
    end
    return res.code >= 200 and res.code < 300, data, res.code
end

function Client:get_raw(url)
    local res = self:_run("GET", url)
    if res.blocked or res.code == 403 then return false, "blocked", 403 end
    if not res.code then return false, "network_error", nil end
    if res.code < 200 or res.code >= 300 then return false, res.body, res.code end
    local expected = tonumber(res.headers and res.headers["content-length"])
    if expected and #res.body ~= expected then return false, "incomplete_content", res.code end
    return true, res.body, res.code
end

function Client:me() return self:request("GET", "/api/backend/auth/me") end
function Client:search(query, page, limit)
    local q = tostring(query):gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end)
    return self:request("GET", string.format("/api/backend/books/search?query=%s&page=%d&limit=%d", q, page or 1, limit or 20))
end
function Client:manifest(book_id) return self:request("GET", "/api/backend/books/" .. book_id .. "/manifest") end
function Client:active_rentals() return self:request("GET", "/api/backend/rentals?status=active") end
function Client:checkout(book_id) return self:request("POST", "/api/backend/rentals/checkout", { bookId = book_id }) end
function Client:extend(rental_id) return self:request("POST", "/api/backend/rentals/" .. rental_id .. "/extend") end
function Client:return_rental(rental_id) return self:request("POST", "/api/backend/rentals/" .. rental_id .. "/return") end

-- The platform only enables a return after 90% read, judged from the progress the reader reports.
function Client:report_progress(book_id, fraction, updated_at)
    local ok, data, code = self:request("POST", "/api/backend/books/" .. book_id .. "/reading", {
        progress_reader = {
            latest_device = "web",
            updated_at = updated_at,
            total_progression = fraction,
        },
    })
    if not ok then return ok, data, code end
    return self:request("POST", "/api/backend/events", {
        events = { { event_type = "book.read.progress", book_id = tostring(book_id),
            percent = math.floor(fraction * 100), platform = "web" } },
    })
end

return Client

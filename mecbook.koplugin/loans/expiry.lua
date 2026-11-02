local M = {}

local DAY = 86400

local function days_from_civil(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

-- Done by hand because os.time() depends on the device timezone.
function M.parse_iso(s)
    if type(s) ~= "string" then return nil end
    local y, mo, d, rest = s:match("^(%d%d%d%d)-(%d%d)-(%d%d)(.*)$")
    if not y then return nil end
    local h, mi, sec = 0, 0, 0
    local tz = 0
    if rest ~= "" then
        local hh, mm, tail = rest:match("^[T ](%d%d):(%d%d)(.*)$")
        if not hh then return nil end
        h, mi = tonumber(hh), tonumber(mm)
        local ss, tail2 = tail:match("^:(%d%d)(.*)$")
        if ss then sec, tail = tonumber(ss), tail2 end
        tail = tail:gsub("^%.%d+", "")
        if tail ~= "" and tail ~= "Z" then
            local sign, oh, om = tail:match("^([+-])(%d%d):?(%d%d)$")
            if not sign then return nil end
            tz = (tonumber(oh) * 3600 + tonumber(om) * 60) * (sign == "+" and 1 or -1)
        end
    end
    local days = days_from_civil(tonumber(y), tonumber(mo), tonumber(d))
    return days * DAY + h * 3600 + mi * 60 + sec - tz
end

function M.due_from_days_remaining(now, days_remaining)
    return now + days_remaining * DAY
end

function M.days_left(due, now)
    if now >= due then return 0 end
    return math.ceil((due - now) / DAY)
end

return M

local M = {}

local function dump(v, out)
    local t = type(v)
    if t == "table" then
        out[#out + 1] = "{"
        for k, val in pairs(v) do
            out[#out + 1] = "[" .. (type(k) == "number" and tostring(k) or string.format("%q", k)) .. "]="
            dump(val, out)
            out[#out + 1] = ","
        end
        out[#out + 1] = "}"
    elseif t == "string" then
        out[#out + 1] = string.format("%q", v)
    else
        out[#out + 1] = tostring(v)
    end
end

function M.encode(tbl)
    local out = { "return " }
    dump(tbl, out)
    return table.concat(out)
end

function M.decode(s)
    local fn = loadstring(s)
    if not fn then return nil end
    setfenv(fn, {})
    local ok, res = pcall(fn)
    return ok and type(res) == "table" and res or nil
end

return M

local M = {}

local MAX_CHARS = 50

local function slug(title)
    local s = tostring(title or ""):gsub('[%c/\\:*?"<>|]', " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    local out, n = {}, 0
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        n = n + 1
        if n > MAX_CHARS then break end
        out[n] = ch
    end
    return (table.concat(out):gsub("[%s.]+$", ""))
end

function M.new(data_dir)
    local cache = data_dir .. "/.mecbook"
    return {
        cache_dir = cache,
        archive_dir = cache .. "/meta",
        state_file = cache .. "/state.lua",
        book = function(book_id, title)
            local name = slug(title)
            if name ~= "" then name = name .. " - " end
            return cache .. "/" .. name .. tostring(book_id) .. ".epub"
        end,
        archive = function(book_id) return cache .. "/meta/" .. tostring(book_id) .. ".lua" end,
    }
end

return M

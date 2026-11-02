local M = {}

function M.new(data_dir)
    local cache = data_dir .. "/.mecbook"
    return {
        cache_dir = cache,
        archive_dir = cache .. "/meta",
        state_file = cache .. "/state.lua",
        book = function(book_id) return cache .. "/" .. tostring(book_id) .. ".epub" end,
        archive = function(book_id) return cache .. "/meta/" .. tostring(book_id) .. ".lua" end,
    }
end

return M

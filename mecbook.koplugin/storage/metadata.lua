local M = {}

-- adapter (KOReader side, see main.lua):
--   find(path)    -> sidecar file of the book, or nil
--   target(path)  -> sidecar file the book would use now (honours the sidecar location setting)
--   read(file)    -> Lua table stored in a sidecar file, or nil
--   copy(src,dst) -> ok
--   exists(file)  -> bool
--   purge(path)   -> removes the book's sidecar and its reading-history entry
function M.new(paths, adapter)
    local self = {}

    function self.progress(path)
        local file = adapter.find(path)
        local data = file and adapter.read(file)
        return data and data.percent_finished or nil
    end

    function self.archive(book_id, path)
        local file = adapter.find(path)
        if file then adapter.copy(file, paths.archive(book_id)) end
    end

    function self.restore(book_id, path)
        local saved = paths.archive(book_id)
        if adapter.exists(saved) then return adapter.copy(saved, adapter.target(path)) end
        return false
    end

    function self.forget(path)
        adapter.purge(path)
    end

    return self
end

return M

local M = {}

local DIR_NAME = ".mecbook"

local function inside(path, cache_dir)
    if type(path) ~= "string" then return false end
    return path == cache_dir
        or path:sub(1, #cache_dir + 1) == cache_dir .. "/"
        or path:find("/" .. DIR_NAME .. "/", 1, true) ~= nil
        or path:sub(-#DIR_NAME - 1) == "/" .. DIR_NAME
end

M.inside = inside

-- Classes are injected so this runs under busted. Patching the classes covers every instance.
function M.install(file_chooser, file_manager, cache_dir)
    -- A method renamed in another KOReader version is skipped: wrapping a missing one would break the file manager.
    local function wrap(class, name, make)
        local original = class[name]
        if type(original) == "function" then class[name] = make(original) end
    end

    wrap(file_chooser, "show_dir", function(original)
        return function(self, name)
            if name == DIR_NAME then return false end
            return original(self, name)
        end
    end)

    wrap(file_chooser, "changeToPath", function(original)
        return function(self, path, focused)
            if inside(path, cache_dir) then
                path = cache_dir:match("(.*)/[^/]*$")
                focused = nil
            end
            return original(self, path, focused)
        end
    end)

    for _, name in ipairs({ "moveFile", "copyRecursive", "copyFileFromTo" }) do
        wrap(file_manager, name, function(original)
            return function(self, from, to)
                if inside(from, cache_dir) then return false end
                return original(self, from, to)
            end
        end)
    end
end

return M

local Cache = require("guard.cache")

describe("cache guard", function()
    local cache = "/k/koreader/.mecbook"

    it("detects paths inside the cache", function()
        assert.is_true(Cache.inside(cache, cache))
        assert.is_true(Cache.inside(cache .. "/x - 1.epub", cache))
        assert.is_true(Cache.inside("/k/koreader/../koreader/.mecbook/a.epub", cache))
        assert.is_false(Cache.inside("/k/koreader/.mecbook2/a.epub", cache))
        assert.is_false(Cache.inside("/k/books/a.epub", cache))
        assert.is_false(Cache.inside(nil, cache))
    end)

    it("skips methods missing in this KOReader version", function()
        local chooser, fm = {}, {}
        assert.has_no.errors(function() Cache.install(chooser, fm, cache) end)
        assert.is_nil(chooser.show_dir)
        assert.is_nil(fm.moveFile)
    end)

    it("hides the folder, redirects navigation and blocks copy and move", function()
        local calls = {}
        local chooser = {
            show_dir = function() return true end,
            changeToPath = function(_, path) calls.path = path end,
        }
        local fm = {}
        for _, n in ipairs({ "moveFile", "copyRecursive", "copyFileFromTo" }) do
            fm[n] = function() calls[n] = true; return true end
        end
        Cache.install(chooser, fm, cache)

        assert.is_false(chooser:show_dir(".mecbook"))
        assert.is_true(chooser:show_dir("Books"))

        chooser:changeToPath(cache .. "/meta")
        assert.equals("/k/koreader", calls.path)
        chooser:changeToPath("/k/books")
        assert.equals("/k/books", calls.path)

        for _, n in ipairs({ "moveFile", "copyRecursive", "copyFileFromTo" }) do
            assert.is_false(fm[n](fm, cache .. "/a.epub", "/k/books"))
            assert.is_nil(calls[n])
            assert.is_true(fm[n](fm, "/k/books/b.epub", "/k/other"))
            assert.is_true(calls[n])
        end
    end)
end)

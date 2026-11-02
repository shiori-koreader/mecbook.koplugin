local Zip = require("epub.zip")
local Builder = require("epub.builder")

local manifest_response = {
    selfHref = "http://alb/webpub/QUJD/manifest.json",
    manifest = {
        metadata = { title = "Dom Casmurro", author = { "Machado" }, language = "pt-BR", identifier = "urn:x:1" },
        readingOrder = { { href = "ch1.xhtml", type = "application/xhtml+xml" } },
        resources = { { href = "img/a b.png", type = "image/png" }, { href = "~readium/x" } },
        toc = { { href = "ch1.xhtml", title = "Um" } },
    },
}
local function fetch(url) return true, "DATA:" .. url end

describe("zip", function()
    it("computes the standard crc32", function()
        assert.equals(0xCBF43926, Zip.crc32("123456789"))
    end)
    it("starts with mimetype stored", function()
        local z = Zip.build({ { name = "mimetype", data = "application/epub+zip" } })
        assert.equals("PK\3\4", z:sub(1, 4))
        assert.equals("mimetype", z:sub(31, 38))
        assert.equals("application/epub+zip", z:sub(39, 58))
    end)
end)

describe("builder", function()
    it("is byte-identical for the same input", function()
        local a = Builder.build(7, manifest_response, "https://o", fetch)
        local b = Builder.build(7, manifest_response, "https://o", fetch)
        assert.equals(a, b)
    end)
    it("requests resources through the epub-proxy, skipping readium internals", function()
        local urls = {}
        Builder.build(7, manifest_response, "https://o", function(u) urls[#urls + 1] = u; return true, "x" end)
        assert.same({ "https://o/epub-proxy/webpub/QUJD/ch1.xhtml", "https://o/epub-proxy/webpub/QUJD/img/a%20b.png" }, urls)
    end)
    it("aborts when a resource fails", function()
        local z, err = Builder.build(7, manifest_response, "https://o", function() return false end)
        assert.is_nil(z)
        assert.equals("download_failed", err)
    end)
    it("can be cancelled from the progress callback", function()
        local z, err = Builder.build(7, manifest_response, "https://o", fetch, function() return false end)
        assert.is_nil(z)
        assert.equals("cancelled", err)
    end)
    it("rejects a manifest without selfHref", function()
        local _, err = Builder.build(7, { manifest = manifest_response.manifest }, "https://o", fetch)
        assert.equals("no_base_url", err)
    end)
end)

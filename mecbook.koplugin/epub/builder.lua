-- Adapted from meclivros.koplugin (MIT, Copyright (c) 2026 Luiz Correia).
local Zip = require("epub.zip")

local M = {}

local CONTAINER_XML = [[<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>]]

local function xml_escape(s)
    if s == nil then return "" end
    return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
end

local function encode_path(path)
    local parts = {}
    for seg in (path .. "/"):gmatch("([^/]*)/") do
        parts[#parts + 1] = (seg:gsub("[^A-Za-z0-9%-%._~]", function(c)
            return string.format("%%%02X", c:byte())
        end))
    end
    return table.concat(parts, "/")
end

local function norm_href(h)
    return (h:gsub("^/+", ""))
end

local function href_to_id(h)
    return "id_" .. h:gsub("[^A-Za-z0-9_]", "_")
end

local function meta_string(value)
    if type(value) == "string" then return value end
    if type(value) ~= "table" then return nil end
    local parts = {}
    for _, v in ipairs(value) do
        if type(v) == "string" then
            parts[#parts + 1] = v
        elseif type(v) == "table" and v.name then
            parts[#parts + 1] = v.name
        end
    end
    if #parts > 0 then return table.concat(parts, ", ") end
    return value.name
end

function M.base_url(origin, self_href)
    local b64 = self_href and self_href:match("/webpub/([^/]+)/manifest%.json")
    if not b64 then return nil end
    return origin .. "/epub-proxy/webpub/" .. b64 .. "/"
end

function M.collect_items(manifest)
    local seen, items, order = {}, {}, {}
    local function add(entry, in_spine)
        local href = norm_href(entry.href or "")
        if href == "" or href:match("^~readium") or href:match("^https?://") then return end
        if in_spine then order[#order + 1] = href end
        if not seen[href] then
            seen[href] = true
            items[#items + 1] = { href = href, type = entry.type or "application/octet-stream" }
        end
    end
    for _, e in ipairs(manifest.readingOrder or {}) do add(e, true) end
    for _, e in ipairs(manifest.resources or {}) do add(e, false) end
    return items, order
end

local function build_nav(manifest, title, language)
    local function render(nodes)
        local out = { "<ol>" }
        for _, n in ipairs(nodes) do
            local li = '<li><a href="' .. xml_escape(encode_path(norm_href(n.href or "#"))) .. '">'
                .. xml_escape(n.title or n.label or "") .. "</a>"
            if n.children and #n.children > 0 then li = li .. render(n.children) end
            out[#out + 1] = li .. "</li>"
        end
        out[#out + 1] = "</ol>"
        return table.concat(out)
    end
    local toc = manifest.toc
    local body
    if type(toc) == "table" and #toc > 0 then
        body = render(toc)
    else
        body = '<ol><li><a href="#">' .. xml_escape(title) .. "</a></li></ol>"
    end
    return table.concat({
        '<?xml version="1.0" encoding="utf-8"?>\n',
        '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="',
        xml_escape(language), '" lang="', xml_escape(language), '">\n',
        '<head><meta charset="utf-8"/><title>', xml_escape(title), '</title></head>\n',
        '<body><nav epub:type="toc" id="toc"><h1>Sumário</h1>', body, '</nav></body></html>',
    })
end

-- crengine builds the table of contents from the NCX more reliably than from nav.xhtml.
local function build_ncx(manifest, title, identifier)
    local toc = manifest.toc
    if type(toc) ~= "table" or #toc == 0 then return nil end
    local points, n = {}, 0
    local function walk(nodes)
        for _, node in ipairs(nodes) do
            n = n + 1
            local label = xml_escape(node.title or node.label or "")
            if label == "" then label = "Seção " .. n end
            points[#points + 1] = string.format(
                '<navPoint id="np%d" playOrder="%d"><navLabel><text>%s</text></navLabel><content src="%s"/></navPoint>',
                n, n, label, xml_escape(encode_path(norm_href(node.href or ""))))
            if node.children and #node.children > 0 then walk(node.children) end
        end
    end
    walk(toc)
    return table.concat({
        '<?xml version="1.0" encoding="utf-8"?>\n',
        '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">\n',
        '<head><meta name="dtb:uid" content="', xml_escape(identifier), '"/></head>\n',
        '<docTitle><text>', xml_escape(title), '</text></docTitle>\n',
        '<navMap>\n', table.concat(points, "\n"), '\n</navMap>\n</ncx>\n',
    })
end

local function build_opf(meta, items, order, has_ncx)
    local man = { '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>' }
    if has_ncx then
        man[#man + 1] = '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
    end
    for _, it in ipairs(items) do
        man[#man + 1] = string.format('<item id="%s" href="%s" media-type="%s"/>',
            href_to_id(it.href), xml_escape(encode_path(it.href)), xml_escape(it.type))
    end
    local spine = {}
    for _, href in ipairs(order) do
        spine[#spine + 1] = string.format('<itemref idref="%s"/>', href_to_id(href))
    end
    return table.concat({
        '<?xml version="1.0" encoding="utf-8"?>\n',
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">\n',
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n',
        '<dc:identifier id="pub-id">', xml_escape(meta.identifier), '</dc:identifier>\n',
        '<dc:title>', xml_escape(meta.title), '</dc:title>\n',
        '<dc:creator>', xml_escape(meta.author), '</dc:creator>\n',
        '<dc:language>', xml_escape(meta.language), '</dc:language>\n',
        '</metadata>\n<manifest>\n', table.concat(man, "\n"), '\n</manifest>\n',
        has_ncx and '<spine toc="ncx">\n' or '<spine>\n', table.concat(spine, "\n"), '\n</spine>\n</package>\n',
    })
end

-- fetch(url) -> ok, bytes_or_err. progress(i, total, title) returns false to cancel.
-- Any missing resource aborts: a partial book would also change the bytes that annotations depend on.
function M.build(book_id, manifest_response, origin, fetch, progress)
    local manifest = type(manifest_response) == "table" and manifest_response.manifest
    if type(manifest) ~= "table" then return nil, "invalid_manifest" end
    local base = M.base_url(origin, manifest_response.selfHref)
    if not base then return nil, "no_base_url" end
    local items, order = M.collect_items(manifest)
    if #items == 0 then return nil, "empty_manifest" end

    local md = manifest.metadata or {}
    local meta = {
        title = meta_string(md.title) or "Livro",
        author = meta_string(md.author) or "",
        language = meta_string(md.language) or "pt",
        identifier = meta_string(md.identifier) or ("mecbook:" .. tostring(book_id)),
    }
    local ncx = build_ncx(manifest, meta.title, meta.identifier)

    local entries = {
        { name = "mimetype", data = "application/epub+zip" },
        { name = "META-INF/container.xml", data = CONTAINER_XML },
        { name = "content.opf", data = build_opf(meta, items, order, ncx ~= nil) },
        { name = "nav.xhtml", data = build_nav(manifest, meta.title, meta.language) },
    }
    if ncx then entries[#entries + 1] = { name = "toc.ncx", data = ncx } end

    for i, it in ipairs(items) do
        if progress and progress(i, #items, meta.title) == false then return nil, "cancelled" end
        local ok, content = fetch(base .. encode_path(it.href))
        if not ok then return nil, "download_failed" end
        entries[#entries + 1] = { name = it.href, data = content }
    end
    return Zip.build(entries), meta.title
end

return M

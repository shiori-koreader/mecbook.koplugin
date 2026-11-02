local bit = require("bit")

local M = {}

local crc_table = {}
for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
        if bit.band(c, 1) == 1 then
            c = bit.bxor(bit.rshift(c, 1), 0xEDB88320)
        else
            c = bit.rshift(c, 1)
        end
    end
    crc_table[i] = c
end

function M.crc32(data)
    local c = 0xFFFFFFFF
    for i = 1, #data do
        c = bit.bxor(crc_table[bit.band(bit.bxor(c, data:byte(i)), 0xFF)], bit.rshift(c, 8))
    end
    return bit.bxor(c, 0xFFFFFFFF) % 4294967296
end

local function u16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
local function u32(n)
    n = n % 4294967296
    return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216))
end

local DOS_TIME = 0
local DOS_DATE = 0x0021 -- 1980-01-01, fixed so the same input always gives the same bytes
local UTF8_FLAG = 0x0800

-- shortcut: entries are stored, not deflated; add compression if EPUB size becomes a problem on the device.
function M.build(entries)
    local out, central, offset = {}, {}, 0
    for _, e in ipairs(entries) do
        local crc = M.crc32(e.data)
        local name, size = e.name, #e.data
        local header = table.concat({
            u32(0x04034b50), u16(20), u16(UTF8_FLAG), u16(0), u16(DOS_TIME), u16(DOS_DATE),
            u32(crc), u32(size), u32(size), u16(#name), u16(0), name,
        })
        out[#out + 1] = header
        out[#out + 1] = e.data
        central[#central + 1] = table.concat({
            u32(0x02014b50), u16(20), u16(20), u16(UTF8_FLAG), u16(0), u16(DOS_TIME), u16(DOS_DATE),
            u32(crc), u32(size), u32(size), u16(#name), u16(0), u16(0), u16(0), u16(0), u32(0),
            u32(offset), name,
        })
        offset = offset + #header + size
    end
    local central_data = table.concat(central)
    out[#out + 1] = central_data
    out[#out + 1] = table.concat({
        u32(0x06054b50), u16(0), u16(0), u16(#entries), u16(#entries),
        u32(#central_data), u32(offset), u16(0),
    })
    return table.concat(out)
end

return M

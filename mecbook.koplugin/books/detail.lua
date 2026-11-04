local Detail = {}

local MAX_DESCRIPTION = 350

local function join(list)
    if type(list) == "table" then return table.concat(list, ", ") end
    return list
end

local function shorten(text)
    text = text:gsub("%s+", " ")
    if #text <= MAX_DESCRIPTION then return text end
    -- Cutting by bytes can split a UTF-8 character; dropping the last partial word removes it.
    return (text:sub(1, MAX_DESCRIPTION):gsub("%s+%S*$", "")) .. "…"
end

function Detail.summary(book)
    local facts = {}
    if book.publisher then facts[#facts + 1] = book.publisher end
    if type(book.published_date) == "string" and #book.published_date >= 4 then
        facts[#facts + 1] = book.published_date:sub(1, 4)
    end
    if book.page_count and book.page_count > 0 then facts[#facts + 1] = book.page_count .. " páginas" end

    local a = type(book.availability) == "table" and book.availability or {}
    local public_domain = book.is_public_domain == true
    local borrowable = public_domain or not (book.rent_unavailable or a.available == false)

    local status
    if public_domain then
        status = "Domínio público · sem prazo e sem limite"
    elseif borrowable then
        status = "Livro licenciado · empréstimo de 14 dias"
    else
        status = "Sem cópias disponíveis agora"
        if a.waitlistCount and a.waitlistCount > 0 then status = status .. " · fila de espera: " .. a.waitlistCount end
    end

    local full_description = type(book.description) == "string" and book.description ~= "" and book.description or nil
    local description = full_description and shorten(full_description)

    return {
        title = book.title or book.book_title or "(sem título)",
        authors = join(book.authors),
        facts = table.concat(facts, " · "),
        categories = join(book.categories),
        status = status,
        description = description,
        full_description = full_description,
        truncated = full_description ~= nil and #full_description:gsub("%s+", " ") > MAX_DESCRIPTION,
        borrowable = borrowable,
        public_domain = public_domain,
    }
end

return Detail

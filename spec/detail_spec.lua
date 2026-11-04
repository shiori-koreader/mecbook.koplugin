local Detail = require("books.detail")

local licensed = {
    title = "Neuromancer", authors = { "William Gibson" }, publisher = "Aleph", published_date = "20150916",
    page_count = 312, categories = { "Ficção Científica" }, is_public_domain = false, description = "Resumo",
    availability = { available = true, copiesAvailable = 5138, totalCopies = 5200, waitlistCount = 0 },
}

describe("detail.summary", function()
    it("organises a licensed book without exposing the copy count", function()
        local d = Detail.summary(licensed)
        assert.is_true(d.borrowable)
        assert.is_false(d.public_domain)
        assert.equals("Neuromancer", d.title)
        assert.equals("William Gibson", d.authors)
        assert.equals("Aleph · 2015 · 312 páginas", d.facts)
        assert.equals("Ficção Científica", d.categories)
        assert.equals("Livro licenciado · empréstimo de 14 dias", d.status)
        assert.is_nil(d.status:find("5138", 1, true))
    end)
    it("flags a book with no copies and shows the waitlist", function()
        local b = setmetatable({ rent_unavailable = true, availability = { available = false, waitlistCount = 3 } },
            { __index = licensed })
        local d = Detail.summary(b)
        assert.is_false(d.borrowable)
        assert.equals("Sem cópias disponíveis agora · fila de espera: 3", d.status)
    end)
    it("marks public domain as open and borrowable", function()
        local d = Detail.summary({ title = "Dom Casmurro", is_public_domain = true })
        assert.is_true(d.public_domain)
        assert.is_true(d.borrowable)
        assert.equals("Domínio público · sem prazo e sem limite", d.status)
    end)
    it("shortens long descriptions", function()
        local d = Detail.summary({ title = "T", description = string.rep("palavra ", 200) })
        assert.is_true(#d.description < 400)
        assert.is_true(d.description:find("…", 1, true) ~= nil)
    end)
end)

describe("detail.summary synopsis", function()
    it("keeps the full text and flags only long descriptions as truncated", function()
        local long = Detail.summary({ title = "T", description = string.rep("palavra ", 200) })
        assert.is_true(long.truncated)
        assert.is_true(#long.full_description > #long.description)
        local short = Detail.summary({ title = "T", description = "linha um\n\nlinha dois" })
        assert.is_false(short.truncated)
    end)
end)

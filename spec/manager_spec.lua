local Manager = require("loans.manager")
local Rentals = require("loans.rentals")
local Serialize = require("storage.serialize")
local Paths = require("storage.paths")
local Metadata = require("storage.metadata")

local DAY = 86400

local function setup(now, loan)
    local env = { now = now, files = { ["/c/7.epub"] = true }, calls = {}, saved = nil }
    local deps = {
        clock = function() return env.now end,
        store = { load = function() return loan and { loan = loan } or nil end, save = function(t) env.saved = t end },
        fs = {
            exists = function(p) return env.files[p] == true end,
            remove = function(p) env.files[p] = nil; env.calls[#env.calls + 1] = "remove" end,
        },
        meta = {
            progress = function() return 0.42 end,
            archive = function() env.calls[#env.calls + 1] = "archive" end,
            forget = function() env.calls[#env.calls + 1] = "forget" end,
        },
    }
    env.m = Manager.new(deps)
    return env
end

local function loan(due) return { rental_id = 9, book_id = 7, title = "Livro", due = due, path = "/c/7.epub" } end

describe("manager.check", function()
    it("does nothing without a loan", function()
        assert.is_nil(setup(0).m:check())
    end)
    it("removes an expired book: progress read, metadata archived and purged, then file deleted", function()
        local env = setup(1000, loan(1000))
        local r = env.m:check()
        assert.equals("removed", r.kind)
        assert.equals("expired", r.reason)
        assert.equals(0.42, r.percent)
        assert.same({ "archive", "forget", "remove" }, env.calls)
        assert.is_nil(env.m:loan())
        assert.is_nil(env.saved.loan)
    end)
    it("warns once per threshold, without removing", function()
        local env = setup(1000, loan(1000 + 2 * DAY))
        local r = env.m:check()
        assert.equals("expiring", r.kind)
        assert.equals(2, r.days)
        assert.equals(1000 + 2 * DAY, r.due)
        assert.same({}, env.calls)
        assert.is_nil(env.m:check())
    end)
    it("warns at each configured threshold as the due date approaches", function()
        local env = setup(0, loan(10 * DAY))
        env.m:set_warn_days({ 7, 1 })
        assert.is_nil(env.m:check())
        env.now = 3 * DAY
        assert.equals("expiring", env.m:check().kind)
        assert.is_nil(env.m:check())
        env.now = 9.5 * DAY
        assert.equals("expiring", env.m:check().kind)
        assert.is_nil(env.m:check())
    end)
    it("warns once when several thresholds are crossed at the same time", function()
        local env = setup(9.5 * DAY, loan(10 * DAY))
        env.m:set_warn_days({ 7, 3, 1 })
        assert.equals("expiring", env.m:check().kind)
        assert.is_nil(env.m:check())
    end)
    it("never warns with no thresholds", function()
        local env = setup(9.5 * DAY, loan(10 * DAY))
        env.m:set_warn_days({})
        assert.is_nil(env.m:check())
    end)
    it("warns again after a renewal moves the due date", function()
        local env = setup(9 * DAY, loan(10 * DAY))
        assert.equals("expiring", env.m:check().kind)
        env.m:sync({ { id = 9, due = 20 * DAY } })
        env.now = 18 * DAY
        assert.equals("expiring", env.m:check().kind)
    end)
    it("is quiet when far from expiry", function()
        assert.is_nil(setup(0, loan(10 * DAY)).m:check())
    end)
    it("drops the loan when the file is gone", function()
        local env = setup(0, loan(10 * DAY))
        env.files["/c/7.epub"] = nil
        assert.is_nil(env.m:check())
        assert.is_nil(env.m:loan())
    end)
end)

describe("manager.before_open", function()
    it("refuses an expired book and removes it", function()
        local env = setup(2000, loan(1000))
        local ok, r = env.m:before_open("/c/7.epub")
        assert.is_false(ok)
        assert.equals("expired", r.reason)
        assert.is_nil(env.files["/c/7.epub"])
    end)
    it("allows a valid book and unrelated files", function()
        local env = setup(0, loan(10 * DAY))
        assert.is_true(env.m:before_open("/c/7.epub"))
        assert.is_true(env.m:before_open("/other.epub"))
    end)
end)

describe("manager.sync", function()
    it("removes the book when the rental is gone from the server", function()
        local env = setup(0, loan(10 * DAY))
        local r = env.m:sync({})
        assert.equals("returned", r.reason)
        assert.is_nil(env.files["/c/7.epub"])
    end)
    it("keeps the book and takes the server due date", function()
        local env = setup(0, loan(10 * DAY))
        assert.is_nil(env.m:sync({ { id = 9, due = 20 * DAY } }))
        assert.equals(20 * DAY, env.m:loan().due)
    end)
    it("tracks whether the server allows renewal", function()
        local env = setup(0, loan(10 * DAY))
        env.m:sync({ { id = 9, can_extend = true } })
        assert.is_true(env.m:loan().can_extend)
    end)
    it("compares ids as strings", function()
        local env = setup(0, loan(10 * DAY))
        assert.is_nil(env.m:sync({ { id = "9" } }))
    end)
    it("syncs at most once per hour", function()
        local env = setup(5000, loan(10 * DAY))
        assert.is_true(env.m:needs_sync())
        env.m:sync({ { id = 9 } })
        env.now = 5000 + 3599
        assert.is_false(env.m:needs_sync())
        env.now = 5000 + 3600
        assert.is_true(env.m:needs_sync())
    end)
end)

describe("manager.return_loan", function()
    it("deletes only when the server accepts", function()
        local env = setup(0, loan(10 * DAY))
        local r, err = env.m:return_loan(function() return false, "boom" end)
        assert.is_nil(r)
        assert.equals("boom", err)
        assert.is_true(env.files["/c/7.epub"])
        r = env.m:return_loan(function(l) assert.equals(9, l.rental_id); return true end)
        assert.equals("returned_here", r.reason)
        assert.is_nil(env.files["/c/7.epub"])
    end)
end)

describe("rentals.normalize", function()
    it("prefers a date field over days_remaining", function()
        local r = Rentals.normalize({ id = 1, book_id = 2, book_title = "T", due_date = "1970-01-02T00:00:00Z", days_remaining = 9 }, 0)
        assert.equals(DAY, r.due)
        assert.equals("T", r.title)
    end)
    it("falls back to days_remaining", function()
        assert.equals(3 * DAY + 100, Rentals.normalize({ id = 1, days_remaining = 3 }, 100).due)
    end)
    it("reads either list shape", function()
        assert.equals(1, #Rentals.list({ rentals = { { id = 1 } } }, 0))
        assert.equals(1, #Rentals.list({ data = { { id = 1 } } }, 0))
    end)
end)

describe("storage", function()
    it("round-trips state", function()
        local t = { last_sync = 5, loan = { title = 'a "quoted" \n title', due = 12.5 } }
        assert.same(t, Serialize.decode(Serialize.encode(t)))
        assert.is_nil(Serialize.decode("garbage ("))
    end)
    it("keeps books in a hidden dir", function()
        local p = Paths.new("/data")
        assert.equals("/data/.mecbook/7.epub", p.book(7))
        assert.equals("/data/.mecbook/meta/7.lua", p.archive(7))
    end)
    it("archives, restores and reads progress through the adapter", function()
        local copies = {}
        local files = { ["/side/a.lua"] = { percent_finished = 0.3 }, ["/arch/7.lua"] = true }
        local p = { archive = function() return "/arch/7.lua" end }
        local md = Metadata.new(p, {
            find = function() return "/side/a.lua" end,
            target = function() return "/side/new.lua" end,
            read = function(f) return files[f] end,
            copy = function(a, b) copies[#copies + 1] = a .. ">" .. b; return true end,
            exists = function(f) return files[f] ~= nil end,
            purge = function() end,
        })
        assert.equals(0.3, md.progress("/b.epub"))
        md.archive(7, "/b.epub")
        assert.is_true(md.restore(7, "/b.epub"))
        assert.same({ "/side/a.lua>/arch/7.lua", "/arch/7.lua>/side/new.lua" }, copies)
    end)
end)

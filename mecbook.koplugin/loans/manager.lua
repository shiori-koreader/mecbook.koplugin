local expiry = require("loans.expiry")

local Manager = {}
Manager.__index = Manager

local HOUR = 3600
local DAY = 86400

-- deps:
--   clock()                      -> epoch seconds
--   store.load() / store.save(t) -> persisted table
--   fs.remove(path), fs.exists(path)
--   meta.progress(path) -> percent|nil, meta.archive(book_id, path), meta.forget(path)
function Manager.new(deps, opts)
    opts = opts or {}
    local self = setmetatable({}, Manager)
    self.clock, self.store, self.fs, self.meta = deps.clock, deps.store, deps.fs, deps.meta
    self:set_warn_days(opts.warn_days or { 3 })
    self.sync_interval = opts.sync_interval or HOUR
    self.state = self.store.load() or {}
    return self
end

function Manager:set_warn_days(days)
    self.warn_days = {}
    for i, d in ipairs(days) do self.warn_days[i] = d end
    table.sort(self.warn_days)
end

function Manager:loan()
    return self.state.loan
end

function Manager:_save()
    self.store.save(self.state)
end

-- Removal order matters: read progress, archive the metadata, purge the sidecar (it needs the file to
-- locate a hash-based sidecar), then delete the file.
function Manager:_remove(reason)
    local loan = self.state.loan
    local removal = {
        reason = reason,
        title = loan.title,
        book_id = loan.book_id,
        percent = self.meta.progress(loan.path),
    }
    self.meta.archive(loan.book_id, loan.path)
    self.meta.forget(loan.path)
    self.fs.remove(loan.path)
    self.state.loan = nil
    self:_save()
    return removal
end

function Manager:start(loan)
    self.state.loan = loan
    self:_save()
end

-- Returns nil, {kind="expiring", title, days} or a removal table (kind="removed").
function Manager:check()
    local loan = self.state.loan
    if not loan then return nil end
    local now = self.clock()
    if not self.fs.exists(loan.path) then
        self.state.loan = nil
        self:_save()
        return nil
    end
    local remaining = loan.due - now
    if remaining <= 0 then
        local removal = self:_remove("expired")
        removal.kind = "removed"
        return removal
    end
    loan.warned = loan.warned or {}
    local hit = false
    for _, d in ipairs(self.warn_days) do
        if remaining <= d * DAY and not loan.warned[d] then
            loan.warned[d] = true
            hit = true
        end
    end
    if hit then
        self:_save()
        return { kind = "expiring", title = loan.title, due = loan.due, days = expiry.days_left(loan.due, now) }
    end
end

-- Returns true to allow opening, or false plus the removal that just happened.
function Manager:before_open(path)
    local loan = self.state.loan
    if not loan or loan.path ~= path then return true end
    local result = self:check()
    if result and result.kind == "removed" then return false, result end
    return true
end

function Manager:needs_sync()
    return self.clock() - (self.state.last_sync or 0) >= self.sync_interval
end

-- rentals: normalized active rentals from the server. Returns a removal table or nil.
function Manager:sync(rentals)
    self.state.last_sync = self.clock()
    local loan = self.state.loan
    if not loan then
        self:_save()
        return nil
    end
    for _, r in ipairs(rentals) do
        if tostring(r.id) == tostring(loan.rental_id) then
            loan.can_extend = r.can_extend
            if r.due and r.due ~= loan.due then
                loan.due = r.due
                loan.warned = {}
            end
            self:_save()
            return nil
        end
    end
    local removal = self:_remove("returned")
    removal.kind = "removed"
    return removal
end

-- return_fn(loan) -> ok, err. The book is deleted only if the server accepted the return.
function Manager:return_loan(return_fn)
    local loan = self.state.loan
    if not loan then return nil, "no_loan" end
    local ok, err = return_fn(loan)
    if not ok then return nil, err end
    local removal = self:_remove("returned_here")
    removal.kind = "removed"
    return removal
end

function Manager:seconds_until_due()
    local loan = self.state.loan
    if not loan then return nil end
    return math.max(loan.due - self.clock(), 0)
end

return Manager

local expiry = require("loans.expiry")

local M = {}

-- The real due-date field name is not confirmed yet (see the first real call); try the likely ones,
-- then fall back to days_remaining.
local DUE_FIELDS = { "due_date", "dueDate", "expires_at", "expiresAt", "end_date", "endDate", "return_date", "returnDate" }

function M.normalize(raw, now)
    local due
    for _, f in ipairs(DUE_FIELDS) do
        if type(raw[f]) == "string" then
            due = expiry.parse_iso(raw[f])
            if due then break end
        end
    end
    if not due and type(raw.days_remaining) == "number" then
        due = expiry.due_from_days_remaining(now, raw.days_remaining)
    end
    return {
        id = raw.id,
        book_id = raw.book_id or raw.bookId,
        title = raw.book_title or raw.title,
        due = due,
        can_extend = raw.can_extend == true,
    }
end

function M.list(data, now)
    local raw = type(data) == "table" and (data.rentals or data.data) or {}
    local out = {}
    for _, r in ipairs(raw) do out[#out + 1] = M.normalize(r, now) end
    return out
end

return M

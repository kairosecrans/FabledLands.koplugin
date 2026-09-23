--[[--
Finding the page a numbered section is printed on.

Gamebook sections are not page numbers, so turning to section 412 normally
means hunting. The books are scans with an OCR text layer, and a section
marker is printed alone on its own line -- which is exactly how it can be
told apart from the "turn to 412" cross-references that litter the prose,
since those sit mid-line among other words.

Sections ascend monotonically through a book, so there is no need to index
anything: a binary search finds the page in about seven reads out of a
hundred, with nothing to build, cache or invalidate when the edition changes.

The search takes a `read` function rather than a document, so the algorithm
can be tested without KOReader (see spec/sections_spec.lua).

@module koplugin.FabledLands.sections
--]]--

local Sections = {}

-- Section numbers in these books run to the high hundreds; anything larger is
-- not a marker. Page numbers are small but sit on lines with other words.
Sections.MAX_SECTION = 999

--- Pulls the section markers off one page of a document.
-- A marker is a line holding exactly one word, and that word an integer.
-- @treturn table ascending list of section numbers (possibly empty)
function Sections.onPage(document, pageno)
    local ok, text = pcall(function() return document:getPageText(pageno) end)
    if not ok or type(text) ~= "table" then return {} end

    local found = {}
    for _, line in ipairs(text) do
        if type(line) == "table" then
            local only, count = nil, 0
            for _, box in ipairs(line) do
                if type(box) == "table" and box.word then
                    count = count + 1
                    only = box.word
                end
            end
            if count == 1 and only then
                local n = tonumber(only:match("^(%d+)$") or "")
                if n and n >= 1 and n <= Sections.MAX_SECTION then
                    found[#found + 1] = n
                end
            end
        end
    end
    table.sort(found)
    return found
end

-- Markers genuinely on one page are consecutive (38, 39, 40...), so a lone
-- number is not a section: it is a running-head page number, a stray digit,
-- or OCR noise. Anything further than this from its neighbour starts a
-- separate group.
--
-- Kept tight on purpose. Early in a book, section numbers and page numbers
-- are both small -- section 14 near page 16 -- so a loose threshold swallows
-- a stray page number into the real run instead of rejecting it. Measured on
-- a book where every page also printed its own number alone: a gap of 25 put
-- 33 sections wrong by up to 4 pages, a gap of 3 put none wrong. The cost is
-- that heavily damaged pages split into smaller runs, which loses precision
-- but never correctness.
Sections.CLUSTER_GAP = 3

--- Reduces a page's markers to the largest tightly-grouped run.
--
-- Dropping markers costs accuracy but never correctness, because the search
-- still narrows monotonically. A false positive is different: it breaks the
-- ordering the search relies on and can send it to the wrong end of the book.
-- Discarding outliers is therefore worth a little lost precision.
function Sections.cluster(marks)
    if #marks <= 1 then return marks end
    local best_i, best_j, i = 1, 1, 1
    while i <= #marks do
        local j = i
        while j < #marks and marks[j + 1] - marks[j] <= Sections.CLUSTER_GAP do
            j = j + 1
        end
        if (j - i) > (best_j - best_i) then best_i, best_j = i, j end
        i = j + 1
    end
    local out = {}
    for k = best_i, best_j do out[#out + 1] = marks[k] end
    return out
end

--- Finds the nearest page at or around `pageno` that carries any marker.
-- Illustrations, maps and the codeword list have none, so a probe that lands
-- on one has to look outwards rather than give up.
local function probeNear(read, pageno, lo, hi)
    -- A page of real sections carries a run of them; a stray numeral in the
    -- front matter is alone. So take the best evidence in the window rather
    -- than the first: a lone number is only trusted when there is nothing
    -- better nearby. Without this, a single stray on a front-matter page can
    -- anchor the search below the page where the text actually starts.
    local fallback_page, fallback_marks
    for offset = 0, 4 do
        for _, p in ipairs(offset == 0 and { pageno } or { pageno - offset, pageno + offset }) do
            if p >= lo and p <= hi then
                local marks = read(p)
                if marks and #marks > 0 then
                    marks = Sections.cluster(marks)
                    if #marks > 1 then
                        return p, marks
                    elseif #marks == 1 and not fallback_page then
                        fallback_page, fallback_marks = p, marks
                    end
                end
            end
        end
    end
    return fallback_page, fallback_marks
end

--- Binary-searches the page range for the page holding `target`.
-- @func read called with a page number, returns that page's markers
-- @int target the section wanted
-- @int lo, hi page range to search
-- @treturn table|nil { page, exact, nearest, reads } or nil if nothing readable
function Sections.search(read, target, lo, hi)
    local reads = 0
    local function readCounted(p)
        reads = reads + 1
        return read(p)
    end

    local best, best_gap
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local page, marks = probeNear(readCounted, mid, lo, hi)
        if not page then break end

        local first, last = marks[1], marks[#marks]
        -- Track the closest page seen, so a section that is never printed
        -- (a gap, or a marker the OCR dropped) still lands nearby.
        local gap = target < first and first - target or target - last
        if best_gap == nil or gap < best_gap then
            best, best_gap = page, gap
        end

        if target >= first and target <= last then
            return { page = page, exact = true, nearest = page, reads = reads }
        elseif target < first then
            hi = page - 1
        else
            lo = page + 1
        end
    end

    if best then
        return { page = best, exact = false, nearest = best, reads = reads }
    end
    return nil
end

--- Convenience wrapper over a live document.
-- @int skip pages of front matter to ignore; section 1 does not start at page 1
function Sections.find(document, target, skip)
    local pages = document:getPageCount()
    return Sections.search(
        function(p) return Sections.onPage(document, p) end,
        target, math.max(1, skip or 1), pages)
end

return Sections

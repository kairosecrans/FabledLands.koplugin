--[[--
Tests for the section-to-page search.

The search takes a `read` callback, so a whole book can be simulated without
KOReader or a PDF. The fixture mirrors what a real scan produces: sections
ascending across pages, a few pages with no markers at all (illustrations,
maps, the codeword list), and the odd number the OCR dropped.

    luajit spec/sections_spec.lua
--]]--

package.path = "?.lua;" .. package.path
local Sections = require("fl_sections")

local failures, checks = 0, 0

local function check(ok, label, detail)
    checks = checks + 1
    if not ok then
        failures = failures + 1
        io.write(("FAIL  %s%s\n"):format(label, detail and ("  -- " .. detail) or ""))
    end
end

local function eq(got, want, label)
    check(got == want, label, ("expected %s, got %s"):format(tostring(want), tostring(got)))
end

--- A hundred-page book: 7 sections a page, starting on page 9.
local FIRST_PAGE, PER_PAGE, LAST_PAGE = 9, 7, 104
local blank = { [30] = true, [31] = true, [70] = true }  -- illustrations
local dropped = { [361] = true }                          -- OCR missed this one

local function pageMarks(p)
    if p < FIRST_PAGE or p > LAST_PAGE or blank[p] then return {} end
    local out = {}
    for i = 1, PER_PAGE do
        local n = (p - FIRST_PAGE) * PER_PAGE + i
        if not dropped[n] then out[#out + 1] = n end
    end
    return out
end

local function pageOf(section)
    return FIRST_PAGE + math.floor((section - 1) / PER_PAGE)
end

-- Every section in the book is found, on the right page -------------------
do
    local worst, total, misses = 0, 0, 0
    for section = 1, (LAST_PAGE - FIRST_PAGE + 1) * PER_PAGE do
        if not dropped[section] then
            local want = pageOf(section)
            if not blank[want] then
                local r = Sections.search(pageMarks, section, 1, LAST_PAGE)
                if not r or not r.exact or r.page ~= want then
                    misses = misses + 1
                    if misses < 4 then
                        io.write(("  miss: section %d -> %s (wanted page %d)\n")
                            :format(section, r and r.page or "nil", want))
                    end
                end
                if r then
                    worst = math.max(worst, r.reads)
                    total = total + r.reads
                end
            end
        end
    end
    eq(misses, 0, "every section lands on its own page")
    check(worst <= 12, "no search reads more than a dozen pages",
        ("worst case %d reads"):format(worst))
end

-- Specific landmarks -------------------------------------------------------
do
    local first = Sections.search(pageMarks, 1, 1, LAST_PAGE)
    eq(first.exact, true, "the opening section is found")
    eq(first.page, FIRST_PAGE, "and it is on the first page of text, not page 1")

    local last_section = (LAST_PAGE - FIRST_PAGE + 1) * PER_PAGE
    local last = Sections.search(pageMarks, last_section, 1, LAST_PAGE)
    eq(last.exact, true, "the final section is found")
    eq(last.page, LAST_PAGE, "on the last page")
end

-- Front matter must not be mistaken for sections ---------------------------
do
    -- Pages before the text carry numerals, but never alone on a line, so the
    -- reader returns nothing for them. The search must still work.
    local r = Sections.search(pageMarks, 5, 1, LAST_PAGE)
    eq(r.exact, true, "a low section is still found past empty front matter")
    eq(r.page, FIRST_PAGE, "and lands in the text, not the front matter")
end

-- Pages with no markers at all ---------------------------------------------
do
    -- Sections that fall on an illustration page cannot be landed on exactly,
    -- but the search must come back with somewhere close rather than nothing.
    local hidden = (30 - FIRST_PAGE) * PER_PAGE + 1
    local r = Sections.search(pageMarks, hidden, 1, LAST_PAGE)
    check(r ~= nil, "a section on a blank page still returns a result")
    check(math.abs(r.page - 30) <= 3, "and lands within a few pages",
        ("got page %s"):format(r and r.page))
end

-- A section the OCR dropped ------------------------------------------------
do
    local r = Sections.search(pageMarks, 361, 1, LAST_PAGE)
    check(r ~= nil, "a dropped section still returns a result")
    -- 361 sits on the same page as 358-364, so the page range still contains it.
    eq(r.page, pageOf(361), "and the surrounding markers put it on the right page")
end

-- Out-of-range requests ----------------------------------------------------
do
    local high = Sections.search(pageMarks, 5000, 1, LAST_PAGE)
    check(high ~= nil, "an impossible section still returns something")
    eq(high.exact, false, "but is not claimed as exact")
    eq(high.page, LAST_PAGE, "and points at the end of the book")

    local zero = Sections.search(pageMarks, 0, 1, LAST_PAGE)
    eq(zero.exact, false, "section zero is not exact")
end

-- A document with no text layer at all -------------------------------------
do
    local none = Sections.search(function() return {} end, 42, 1, 100)
    eq(none, nil, "no text layer means no result, rather than a wrong one")
end

-- Marker extraction --------------------------------------------------------
-- A line holding a single integer is a section; anything else is not.
do
    local fake = {
        getPageText = function()
            return {
                { { word = "38" } },                                  -- a marker
                { { word = "Heavy" }, { word = "black" }, { word = "clouds" } },
                { { word = "turn" }, { word = "to" }, { word = "209" } }, -- a reference
                { { word = "16" }, { word = "The" }, { word = "War-Torn" } }, -- running head
                { { word = "39" } },                                  -- another marker
                { { word = "9999" } },                                -- too large
                { { word = "" } },
            }
        end,
    }
    local marks = Sections.onPage(fake, 1)
    eq(#marks, 2, "only the solo integers count")
    eq(marks[1], 38, "first marker")
    eq(marks[2], 39, "second marker")

    local broken = { getPageText = function() error("no text layer") end }
    eq(#Sections.onPage(broken, 1), 0, "a document that throws yields no markers")
end

io.write(("\n%d checks, %d failures\n"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)

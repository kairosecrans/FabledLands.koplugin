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

-- Fault tolerance ----------------------------------------------------------
-- Two kinds of OCR damage behave very differently. Missing markers only cost
-- precision: the search still narrows monotonically, so it lands nearby.
-- Spurious markers break the ordering the search depends on and can send it
-- to the wrong end of the book, which is why pages are clustered first.

local function damagedBook(drop_rate, extra_kind, seed, extra_rate)
    math.randomseed(seed)
    local drop, extra = {}, {}
    local total = (LAST_PAGE - FIRST_PAGE + 1) * PER_PAGE
    for n = 1, total do
        if drop_rate > 0 and math.random() < drop_rate then drop[n] = true end
    end
    if extra_kind then
        for p = FIRST_PAGE, LAST_PAGE do
            if math.random() < (extra_rate or 0.3) then
                extra[p] = extra_kind == "small" and math.random(1, 60) or math.random(1, total)
            end
        end
    end
    return function(p)
        if p < FIRST_PAGE or p > LAST_PAGE then return {} end
        local out = {}
        for i = 1, PER_PAGE do
            local n = (p - FIRST_PAGE) * PER_PAGE + i
            if not drop[n] then out[#out + 1] = n end
        end
        if extra[p] then out[#out + 1] = extra[p]; table.sort(out) end
        return out
    end, total
end

--- Runs every section and reports how many landed more than 2 pages out.
local function misplaced(read, total)
    local bad = 0
    for n = 1, total do
        local want = FIRST_PAGE + math.floor((n - 1) / PER_PAGE)
        local r = Sections.search(read, n, 1, LAST_PAGE)
        if not r or math.abs(r.page - want) > 2 then bad = bad + 1 end
    end
    return bad
end

do
    -- Losing markers must never place a section wrongly, only less precisely.
    for _, rate in ipairs({ 0.3, 0.5, 0.7 }) do
        local read, total = damagedBook(rate, nil, 11)
        eq(misplaced(read, total), 0,
            ("%d%% of markers missing still never lands wrong"):format(rate * 100))
    end

    -- Spurious low numbers are what a running head looks like to the reader.
    local read, total = damagedBook(0, "small", 7)
    eq(misplaced(read, total), 0, "stray low numbers do not mislead the search")

    local read2, total2 = damagedBook(0, "any", 7)
    eq(misplaced(read2, total2), 0, "stray arbitrary numbers do not mislead it either")

    -- Both kinds at once, at a damage level a real scan might plausibly hit.
    -- Checked over many seeds rather than one: the combined case is bimodal,
    -- almost always perfect but occasionally bad when a stray inverts the
    -- ordering at a decision point, so a single seed proves nothing.
    for seed = 1, 20 do
        local read3, total3 = damagedBook(0.2, "small", seed, 0.15)
        eq(misplaced(read3, total3), 0,
            ("20%% missing plus 15%% spurious, seed %d"):format(seed))
    end
end

-- Page numbers, which converge with section numbers early in a book ------
do
    -- The worst realistic case: every page also prints its own number alone.
    -- Early on, section 14 sits near page 16, so a loose cluster threshold
    -- would swallow the page number into the real run.
    local function withPageNumbers(p)
        if p < FIRST_PAGE or p > LAST_PAGE then return {} end
        local out = {}
        for i = 1, PER_PAGE do out[#out + 1] = (p - FIRST_PAGE) * PER_PAGE + i end
        out[#out + 1] = p
        table.sort(out)
        return out
    end
    local total = (LAST_PAGE - FIRST_PAGE + 1) * PER_PAGE
    eq(misplaced(withPageNumbers, total), 0,
        "a page number printed alone never displaces a section")

    -- Front matter, where stray numerals really do occur -- Book 1 has a lone
    -- "7" on page 4. What matters is not whether those pages get read while
    -- narrowing, but that they never become the answer. A real section page
    -- carries a run of markers; a stray is alone, and a lone number is only
    -- trusted when there is nothing better nearby.
    local function strayOnEveryFrontPage(p)
        if p < FIRST_PAGE then return { 7 } end
        return pageMarks(p)
    end
    -- Sections that fall on a blank illustration page, or whose marker the
    -- OCR dropped, are a separate limitation tested above; exclude them so
    -- this measures only the effect of the front-matter strays.
    local wrong = 0
    for section = 1, total do
        local want = FIRST_PAGE + math.floor((section - 1) / PER_PAGE)
        if not blank[want] and not dropped[section] then
            local r = Sections.search(strayOnEveryFrontPage, section, 1, LAST_PAGE)
            if not r or r.page ~= want then wrong = wrong + 1 end
        end
    end
    eq(wrong, 0, "front-matter strays never become the answer")

    -- The low sections are the ones at risk, since they are numerically
    -- closest to the front-matter page numbers.
    for _, section in ipairs({ 1, 2, 7 }) do
        local r = Sections.search(strayOnEveryFrontPage, section, 1, LAST_PAGE)
        check(r and r.page >= FIRST_PAGE,
            ("section %d lands in the text, not the front matter"):format(section),
            ("got page %s"):format(r and r.page))
    end
end

-- The clustering that makes the above work --------------------------------
do
    -- A running head caught alone on a line, among real markers.
    local kept = Sections.cluster({ 16, 523, 524, 525, 526, 527 })
    eq(#kept, 5, "the outlier is dropped")
    eq(kept[1], 523, "and the real run is kept")

    -- An outlier above the run.
    local kept2 = Sections.cluster({ 38, 39, 40, 900 })
    eq(#kept2, 3, "a high outlier is dropped too")
    eq(kept2[#kept2], 40, "run intact")

    -- A page with a single marker must survive: nothing to compare it to.
    eq(#Sections.cluster({ 42 }), 1, "a lone marker is kept")
    eq(#Sections.cluster({}), 0, "an empty page stays empty")

    -- Two equal-sized groups: keeping either is defensible, but it must
    -- return a contiguous run rather than the union.
    local split = Sections.cluster({ 10, 11, 500, 501 })
    eq(#split, 2, "one group is chosen, not both")
    check(split[2] - split[1] <= Sections.CLUSTER_GAP, "and it is a tight run")
end

io.write(("\n%d checks, %d failures\n"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)

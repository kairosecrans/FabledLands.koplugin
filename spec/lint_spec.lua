--[[--
Static checks over the plugin sources.

These exist because of a bug that unit tests could never have caught: in a
file that does `local _ = require("gettext")`, writing `for _, item in
ipairs(...)` rebinds `_` to the loop index, so any `_("...")` inside that
loop tries to call a number and crashes at the moment the user taps the
button. It only shows up at runtime, on one code path, so it is worth
pinning down here.

    luajit spec/lint_spec.lua
--]]--

local PLUGIN_DIR = "."

local failures, checks = 0, 0

local function check(ok, label, detail)
    checks = checks + 1
    if not ok then
        failures = failures + 1
        io.write(("FAIL  %s%s\n"):format(label, detail and ("  -- " .. detail) or ""))
    end
end

local function sources()
    local names = {}
    local pipe = io.popen(("ls %s/*.lua 2>/dev/null"):format(PLUGIN_DIR))
    if pipe then
        for line in pipe:lines() do table.insert(names, line) end
        pipe:close()
    end
    return names
end

local function read(path)
    local handle = assert(io.open(path, "r"))
    local text = handle:read("*a")
    handle:close()
    return text
end

local files = sources()
check(#files > 0, "found plugin sources", "none matched " .. PLUGIN_DIR .. "/*.lua")

for _i, path in ipairs(files) do
    local text = read(path)

    -- Everything must at least parse.
    local chunk, err = loadfile(path)
    check(chunk ~= nil, path .. " parses", err)

    -- The gettext shadowing trap.
    if text:match('local%s+_%s*=%s*require%("gettext"%)') then
        local line_no = 0
        -- "(.-)\n" walks real lines; "[^\n]*" would also yield an empty match
        -- between each pair and double the count.
        for line in (text .. "\n"):gmatch("(.-)\n") do
            line_no = line_no + 1
            -- `for _, x in ...` or `for _ = 1, n` rebinds the gettext alias.
            if line:match("^%s*for%s+_%s*,") or line:match("^%s*for%s+_%s*=") then
                check(false, path .. " does not shadow the gettext `_`",
                    ("line %d: %s"):format(line_no, line:match("^%s*(.-)%s*$")))
            end
        end
        check(true, path .. " keeps `_` bound to gettext")
    end


    -- Nothing may call into a KOReader API at module level. main.lua requires
    -- these modules before it can register anything, so a throw out here takes
    -- the whole plugin down with no menu entry and no actionable error -- a
    -- failure mode that is invisible on Android, where there is no crash.log.
    do
        local line_no = 0
        for line in (text .. "\n"):gmatch("(.-)\n") do
            line_no = line_no + 1
            -- A top-level assignment (no leading whitespace) whose value calls
            -- a method on a module, e.g. `X.Y = Font:getFace("...")`.
            if line:match("^[%w_.]+%s*=%s*[A-Z][%w_]*[:.][%w_]+%s*%(") then
                check(false, path .. " does no work at module load time",
                    ("line %d: %s"):format(line_no, line:match("^%s*(.-)%s*$")))
            end
        end
        check(true, path .. " defers KOReader calls to runtime")
    end

    -- Module names must stay namespaced: package.path is shared across every
    -- loaded plugin, so a bare `require("rules")` could pick up a different
    -- plugin's file depending on load order.
    for required in text:gmatch('require%("([%w_]+)"%)') do
        local is_local = false
        for _j, candidate in ipairs(files) do
            if candidate:match("([%w_]+)%.lua$") == required then is_local = true end
        end
        if is_local then
            check(required:match("^fl_") ~= nil,
                ("%s requires a namespaced module"):format(path),
                ("%q should start with fl_"):format(required))
        end
    end
end

io.write(("\n%d checks, %d failures\n"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)

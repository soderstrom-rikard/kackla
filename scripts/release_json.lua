-- Writes a release.json (the BigWigsMods/packager format) to stdout, so
-- strongbox knows which game versions the release zip supports:
--
--   lua scripts/release_json.lua VERSION ZIPNAME TOC...
--
-- The interface numbers and the version are read from the .toc files, only
-- the mapping from .toc suffix to flavor lives here. strongbox only reads
-- each entry's flavor, matching it against keywords such as classic, bcc,
-- wrath, cata, mists and forever.

-- {suffix, flavor} for kackla_<suffix>.toc, in the order they are listed.
-- kackla.toc, without a suffix, is the fallback for game versions without
-- their own .toc and is not listed.
local FLAVORS = {
    {"Vanilla", "classic"},
    {"TBC", "bcc"},
    {"Wrath", "wrath"},
    {"Cata", "cata"},
    {"Mists", "mists"},
    {"Forever", "forever"},
    -- the BigWigs packager writes Camelot as forever, and instawow rejects
    -- a release.json with flavors the packager doesn't write
    {"Camelot", "forever"},
}

local flavorBySuffix = {}
for _, entry in ipairs(FLAVORS) do
    flavorBySuffix[entry[1]] = entry[2]
end

local version, zipName = arg[1], arg[2]
if not version or not zipName or not arg[3] then
    io.stderr:write("usage: lua scripts/release_json.lua VERSION ZIPNAME TOC...\n")
    os.exit(1)
end

-- Prints message to stderr and exits with status 1
local function fail(message)
    io.stderr:write("release_json.lua: " .. message .. "\n")
    os.exit(1)
end

-- Returns the value of "## key: value" in a .toc file
local function tocField(path, key)
    local file = io.open(path) or fail("can't read " .. path)
    local value
    for line in file:lines() do
        value = value or line:match("^## " .. key .. ":%s*(.-)%s*$")
    end
    file:close()
    return value
end

local interfaces = {}
for i = 3, #arg do
    local path = arg[i]
    local tocVersion = tocField(path, "Version")
    if tocVersion ~= version then
        fail(path .. " has version " .. tostring(tocVersion) .. ", expected " .. version)
    end

    local suffix = path:match("_([^_/]+)%.toc$")
    if suffix then
        if not flavorBySuffix[suffix] then
            fail(path .. ": no flavor for suffix '" .. suffix .. "', add it to FLAVORS")
        end
        -- "## Interface: 50503, 50504", the first one is used
        local interface = (tocField(path, "Interface") or ""):match("^(%d+)")
        if not interface then
            fail(path .. " has no ## Interface number")
        end
        interfaces[suffix] = tonumber(interface)
    end
end

local metadata = {}
for _, entry in ipairs(FLAVORS) do
    local suffix, flavor = entry[1], entry[2]
    if interfaces[suffix] then
        table.insert(metadata, string.format('        {"flavor": "%s", "interface": %d}',
                                             flavor, interfaces[suffix]))
    end
end
if #metadata == 0 then
    fail("no kackla_<suffix>.toc files given")
end

io.write('{\n')
io.write('  "releases": [{\n')
io.write('    "name": "kackla",\n')
io.write('    "version": "' .. version .. '",\n')
io.write('    "filename": "' .. zipName .. '",\n')
io.write('    "nolib": false,\n')
io.write('    "metadata": [\n')
io.write(table.concat(metadata, ",\n") .. "\n")
io.write('    ]\n')
io.write('  }]\n')
io.write('}\n')

-- ASN.1 UNALIGNED Packed Encoding Rules (uPER), ITU-T X.691 (02/2021), for
-- the kackla communication layer (see docs/communication-layer.md).
--
-- Only what kackla's messages use is implemented so far, the rest fails with
-- a "not implemented" error, never with a wrong encoding. It is meant to grow
-- into a full implementation, so it follows the structure of X.691: a bit
-- writer and reader, the encoding procedures of clause 11 (constrained whole
-- numbers, lengths, open types, …) and one encoder and decoder per type,
-- built from those. Clause numbers refer to X.691.
--
-- Types are described with Lua tables mirroring the ASN.1 definitions:
--
--   {type = "BOOLEAN"}
--   {type = "NULL"}
--   {type = "INTEGER", min = 0, max = 255, extensible = true}
--   {type = "ENUMERATED", values = {"red", "green"}, extensible = true,
--    additions = {"blue"}}
--   {type = "CHOICE", alternatives = {{"name", TYPE}, ...},
--    extensible = true, additions = {{"name", TYPE}, ...}}
--   {type = "SEQUENCE", fields = {{"name", TYPE, optional = true}, ...},
--    extensible = true}
--   {type = "SEQUENCE OF", of = TYPE, min = 1, max = 32, extensible = true}
--
-- extensible means the ASN.1 has an extension marker (...). ENUMERATED and
-- CHOICE list the values and alternatives in their ASN.1 order, which is the
-- encoding order with AUTOMATIC TAGS. Any other type name, e.g.
-- {type = "IA5String"}, can be used as a placeholder for a type that isn't
-- implemented yet: it works as long as no value of it is encoded or decoded.
--
-- Values are Lua values:
--   BOOLEAN       true or false
--   NULL          anything when encoding, true when decoded
--   INTEGER       a whole number
--   ENUMERATED    the value's name, e.g. "red"
--   CHOICE        {name, value}, e.g. {"named", "red"}
--   SEQUENCE      a table with the fields by name, absent OPTIONAL fields nil
--   SEQUENCE OF   an array
--
-- Values from a newer version that this version doesn't know (extension
-- additions) are decoded as kacklaUper.UNKNOWN: an unknown ENUMERATED value
-- is kacklaUper.UNKNOWN, an unknown CHOICE alternative {kacklaUper.UNKNOWN,
-- index}. Unknown SEQUENCE additions are skipped.
--
-- Numbers are packed with arithmetic, not bit operations: Lua 5.1 has none
-- and WoW's bit library isn't there in the tests. Values must stay below 2^53.

kacklaUper = {}
local uper = kacklaUper

-- Decoded value of an extension addition this version doesn't know
uper.UNKNOWN = setmetatable({}, {__tostring = function() return "UNKNOWN" end})

-- Raises an error for path, e.g. "uper: ChatColors.spans[2]: …"
local function fail(path, message)
    error("uper: " .. (path ~= "" and path .. ": " or "") .. message, 0)
end

-- Returns path extended with name, e.g. "spans" -> "spans.color"
local function join(path, name)
    return path == "" and name or path .. "." .. name
end

-- Raises the error for a feature that isn't implemented yet
local function notImplemented(path, feature)
    fail(path, feature .. " is not implemented")
end

-- Returns the number of bits needed to encode the values 0 to range - 1,
-- e.g. 0 for range 1, 2 for range 3 or 4 (11.5.6)
local function bitsForRange(range)
    local bits = 0
    while 2 ^ bits < range do
        bits = bits + 1
    end
    return bits
end

-- Returns true when value is a whole number
local function isWholeNumber(value)
    return type(value) == "number" and value == math.floor(value)
end

--------------------------------------------------------------------------------
-- Bit writer and reader

local Writer = {}
Writer.__index = Writer

-- Returns a writer collecting bits, one table entry (0 or 1) per bit
function uper.newWriter()
    return setmetatable({bits = {}}, Writer)
end

-- Appends value as a non-negative-binary-integer in count bits (11.3)
function Writer:number(value, count)
    for i = count - 1, 0, -1 do
        self.bits[#self.bits + 1] = math.floor(value / 2 ^ i) % 2
    end
end

-- Appends a single bit, 1 for true
function Writer:bit(set)
    self.bits[#self.bits + 1] = set and 1 or 0
end

-- Appends the bytes of s, 8 bits each, not aligned
function Writer:octets(s)
    for i = 1, #s do
        self:number(string.byte(s, i), 8)
    end
end

-- Returns the bits written so far as a string of 0 and 1, for tests
function Writer:bitString()
    return table.concat(self.bits)
end

-- Returns the complete encoding (11.1.3.1): padded with zero bits to whole
-- octets, and a single zero octet when nothing was written
function Writer:complete()
    local bits = self.bits
    if #bits == 0 then
        return "\0"
    end
    local bytes = {}
    for i = 1, #bits, 8 do
        local byte = 0
        for j = i, i + 7 do
            byte = byte * 2 + (bits[j] or 0)
        end
        bytes[#bytes + 1] = string.char(byte)
    end
    return table.concat(bytes)
end

local Reader = {}
Reader.__index = Reader

-- Returns a reader for the bits of data, a string
function uper.newReader(data)
    return setmetatable({data = data, pos = 0, size = #data * 8}, Reader)
end

-- Returns the next count bits as a non-negative-binary-integer (11.3)
function Reader:number(count)
    if self.pos + count > self.size then
        fail("", "the data ends at bit " .. self.size .. ", " .. count .. " more bits needed at bit " .. self.pos)
    end
    local value = 0
    for _ = 1, count do
        local byte = string.byte(self.data, math.floor(self.pos / 8) + 1)
        local bit = math.floor(byte / 2 ^ (7 - self.pos % 8)) % 2
        value = value * 2 + bit
        self.pos = self.pos + 1
    end
    return value
end

-- Returns true when the next bit is 1
function Reader:bit()
    return self:number(1) == 1
end

-- Returns the next count bytes, not aligned
function Reader:octets(count)
    if self.pos + count * 8 > self.size then
        fail("", "the data ends at bit " .. self.size .. ", " .. count .. " more octets needed at bit " .. self.pos)
    end
    if self.pos % 8 == 0 then
        local first = self.pos / 8 + 1
        self.pos = self.pos + count * 8
        return string.sub(self.data, first, first + count - 1)
    end
    local bytes = {}
    for i = 1, count do
        bytes[i] = string.char(self:number(8))
    end
    return table.concat(bytes)
end

--------------------------------------------------------------------------------
-- Encoding procedures (clause 11)

-- Constrained whole number n in lb..ub (11.5.6): n - lb in the fewest bits
-- for the range, no bits when the range is 1
local function encodeConstrained(w, path, n, lb, ub)
    if not isWholeNumber(n) or n < lb or n > ub then
        fail(path, tostring(n) .. " is not a whole number in " .. lb .. ".." .. ub)
    end
    w:number(n - lb, bitsForRange(ub - lb + 1))
end

local function decodeConstrained(r, path, lb, ub)
    local n = r:number(bitsForRange(ub - lb + 1)) + lb
    if n > ub then
        fail(path, n .. " is outside " .. lb .. ".." .. ub)
    end
    return n
end

-- Normally small non-negative whole number (11.6), e.g. an extension index
local function encodeNormallySmall(w, path, n)
    if n > 63 then
        notImplemented(path, "a normally small number over 63")
    end
    w:bit(false)
    w:number(n, 6)
end

local function decodeNormallySmall(r, path)
    if r:bit() then
        notImplemented(path, "a normally small number over 63")
    end
    return r:number(6)
end

-- Normally small length 1..64 (11.9.3.4), e.g. a count of extension
-- additions. Only decoded so far, encoding SEQUENCE additions isn't
-- implemented.
local function decodeNormallySmallLength(r, path)
    if r:bit() then
        notImplemented(path, "a normally small length over 64")
    end
    return r:number(6) + 1
end

-- Unconstrained length determinant (11.9.3.6, 11.9.3.7): 0 and 7 bits up to
-- 127, 10 and 14 bits below 16K. Larger lengths need fragmentation (11.9.3.8).
local function encodeLength(w, path, n)
    if n <= 127 then
        w:bit(false)
        w:number(n, 7)
    elseif n < 16384 then
        w:number(2, 2)
        w:number(n, 14)
    else
        notImplemented(path, "a length of 16K or more (fragmentation)")
    end
end

local function decodeLength(r, path)
    if not r:bit() then
        return r:number(7)
    end
    if r:bit() then
        notImplemented(path, "a length of 16K or more (fragmentation)")
    end
    return r:number(14)
end

-- Open type field (11.2): the complete encoding of the value, preceded by its
-- length in octets
local function encodeOpenType(w, path, encoding)
    encodeLength(w, path, #encoding)
    w:octets(encoding)
end

-- Returns the complete encoding inside an open type field
local function decodeOpenType(r, path)
    return r:octets(decodeLength(r, path))
end

--------------------------------------------------------------------------------
-- Types

local encoders, decoders = {}, {}

-- Encodes value of type t, dispatching on t.type
local function encodeValue(w, t, value, path)
    local encoder = encoders[t.type]
    if not encoder then
        notImplemented(path, "type " .. tostring(t.type))
    end
    encoder(w, t, value, path)
end

local function decodeValue(r, t, path)
    local decoder = decoders[t.type]
    if not decoder then
        notImplemented(path, "type " .. tostring(t.type))
    end
    return decoder(r, t, path)
end

-- Returns the complete encoding of value, as used inside open types
local function encodeComplete(t, value, path)
    local w = uper.newWriter()
    encodeValue(w, t, value, path)
    return w:complete()
end

-- Returns the value in the complete encoding data
local function decodeComplete(t, data, path)
    return decodeValue(uper.newReader(data), t, path)
end

-- Fails unless the INTEGER t has both bounds, the only kind implemented
local function checkIntegerBounds(t, path)
    if t.min == nil or t.max == nil then
        notImplemented(path, "INTEGER without both bounds")
    end
end

-- BOOLEAN (clause 12): one bit
encoders["BOOLEAN"] = function(w, t, value, path)
    if type(value) ~= "boolean" then
        fail(path, "expected a boolean, got " .. tostring(value))
    end
    w:bit(value)
end

decoders["BOOLEAN"] = function(r, t, path)
    return r:bit()
end

-- NULL (clause 18): no bits
encoders["NULL"] = function(w, t, value, path)
end

decoders["NULL"] = function(r, t, path)
    return true
end

-- INTEGER (clause 13): an extension bit when extensible, then a constrained
-- whole number. Values outside the extension root are not implemented.
encoders["INTEGER"] = function(w, t, value, path)
    checkIntegerBounds(t, path)
    if t.extensible then
        if isWholeNumber(value) and (value < t.min or value > t.max) then
            notImplemented(path, "an INTEGER value outside the extension root")
        end
        w:bit(false)
    end
    encodeConstrained(w, path, value, t.min, t.max)
end

decoders["INTEGER"] = function(r, t, path)
    checkIntegerBounds(t, path)
    if t.extensible and r:bit() then
        notImplemented(path, "an INTEGER value outside the extension root")
    end
    return decodeConstrained(r, path, t.min, t.max)
end

-- Returns the index (0 based) of name in list, a list of names or of
-- {name, type} pairs, or nil
local function indexOf(list, name)
    for i, entry in ipairs(list or {}) do
        if entry == name or (type(entry) == "table" and entry[1] == name) then
            return i - 1
        end
    end
end

-- ENUMERATED (clause 14): an extension bit when extensible, then the index
-- as a constrained whole number, or as a normally small number for additions
encoders["ENUMERATED"] = function(w, t, value, path)
    local index = indexOf(t.values, value)
    if index then
        if t.extensible then
            w:bit(false)
        end
        encodeConstrained(w, path, index, 0, #t.values - 1)
        return
    end
    index = t.extensible and indexOf(t.additions, value)
    if not index then
        fail(path, "'" .. tostring(value) .. "' is not a value of the ENUMERATED")
    end
    w:bit(true)
    encodeNormallySmall(w, path, index)
end

decoders["ENUMERATED"] = function(r, t, path)
    if t.extensible and r:bit() then
        local index = decodeNormallySmall(r, path)
        return (t.additions or {})[index + 1] or uper.UNKNOWN
    end
    return t.values[decodeConstrained(r, path, 0, #t.values - 1) + 1]
end

-- CHOICE (clause 23): an extension bit when extensible, then the index of the
-- alternative as a constrained whole number followed by its value, or for
-- additions as a normally small number followed by its value as an open type
encoders["CHOICE"] = function(w, t, value, path)
    if type(value) ~= "table" then
        fail(path, "expected {name, value}, got " .. tostring(value))
    end
    local name = value[1]
    local index = indexOf(t.alternatives, name)
    if index then
        if t.extensible then
            w:bit(false)
        end
        encodeConstrained(w, path, index, 0, #t.alternatives - 1)
        encodeValue(w, t.alternatives[index + 1][2], value[2], join(path, name))
        return
    end
    index = t.extensible and indexOf(t.additions, name)
    if not index then
        fail(path, "'" .. tostring(name) .. "' is not an alternative of the CHOICE")
    end
    w:bit(true)
    encodeNormallySmall(w, path, index)
    encodeOpenType(w, path, encodeComplete(t.additions[index + 1][2], value[2], join(path, name)))
end

decoders["CHOICE"] = function(r, t, path)
    if t.extensible and r:bit() then
        local index = decodeNormallySmall(r, path)
        local encoding = decodeOpenType(r, path)
        local addition = (t.additions or {})[index + 1]
        if not addition then
            return {uper.UNKNOWN, index}
        end
        return {addition[1], decodeComplete(addition[2], encoding, join(path, addition[1]))}
    end
    local index = decodeConstrained(r, path, 0, #t.alternatives - 1)
    local alternative = t.alternatives[index + 1]
    return {alternative[1], decodeValue(r, alternative[2], join(path, alternative[1]))}
end

-- SEQUENCE (clause 19): an extension bit when extensible, a bit for each
-- OPTIONAL field saying whether it is present, then the present fields.
-- Known extension additions are not implemented, unknown ones are skipped.
encoders["SEQUENCE"] = function(w, t, value, path)
    if t.additions then
        notImplemented(path, "SEQUENCE extension additions")
    end
    if type(value) ~= "table" then
        fail(path, "expected a table, got " .. tostring(value))
    end
    if t.extensible then
        w:bit(false)
    end
    for _, field in ipairs(t.fields) do
        if field.optional then
            w:bit(value[field[1]] ~= nil)
        end
    end
    for _, field in ipairs(t.fields) do
        local name, fieldValue = field[1], value[field[1]]
        if fieldValue ~= nil then
            encodeValue(w, field[2], fieldValue, join(path, name))
        elseif not field.optional then
            fail(path, "field '" .. name .. "' is missing")
        end
    end
end

decoders["SEQUENCE"] = function(r, t, path)
    if t.additions then
        notImplemented(path, "SEQUENCE extension additions")
    end
    local extended = t.extensible and r:bit()
    local present = {}
    for i, field in ipairs(t.fields) do
        present[i] = not field.optional or r:bit()
    end
    local value = {}
    for i, field in ipairs(t.fields) do
        if present[i] then
            value[field[1]] = decodeValue(r, field[2], join(path, field[1]))
        end
    end
    if extended then
        -- additions from a newer version (19.7 to 19.9), skipped
        local count = decodeNormallySmallLength(r, path)
        local additionsPresent = 0
        for _ = 1, count do
            if r:bit() then
                additionsPresent = additionsPresent + 1
            end
        end
        for _ = 1, additionsPresent do
            decodeOpenType(r, path)
        end
    end
    return value
end

-- Returns the lower and upper bound of the number of components of the
-- SEQUENCE OF t (20.2), upper is nil when unset (no bound, or 64K or more)
local function sizeBounds(t)
    local lb = t.min or 0
    local ub = t.max
    if ub and ub >= 65536 then
        ub = nil
    end
    return lb, ub
end

-- SEQUENCE OF (clause 20): an extension bit when the size is extensible, the
-- number of components unless it is fixed, then the components
encoders["SEQUENCE OF"] = function(w, t, value, path)
    if type(value) ~= "table" then
        fail(path, "expected an array, got " .. tostring(value))
    end
    local n = #value
    local lb, ub = sizeBounds(t)
    if n < lb or (t.max and n > t.max) then
        if t.extensible then
            notImplemented(path, "a SEQUENCE OF size outside the extension root")
        end
        fail(path, n .. " components, expected " .. lb .. ".." .. tostring(t.max))
    end
    if t.extensible then
        w:bit(false)
    end
    -- a fixed size has a range of 1, which encodes to no bits (20.5)
    if ub then
        encodeConstrained(w, path, n, lb, ub)
    else
        encodeLength(w, path, n)
    end
    for i = 1, n do
        encodeValue(w, t.of, value[i], path .. "[" .. i .. "]")
    end
end

decoders["SEQUENCE OF"] = function(r, t, path)
    if t.extensible and r:bit() then
        notImplemented(path, "a SEQUENCE OF size outside the extension root")
    end
    local lb, ub = sizeBounds(t)
    local n
    if ub then
        n = decodeConstrained(r, path, lb, ub)
    else
        n = decodeLength(r, path)
        if n < lb or (t.max and n > t.max) then
            fail(path, n .. " components, expected " .. lb .. ".." .. tostring(t.max))
        end
    end
    local value = {}
    for i = 1, n do
        value[i] = decodeValue(r, t.of, path .. "[" .. i .. "]")
    end
    return value
end

--------------------------------------------------------------------------------
-- API

-- Returns the complete encoding of value of type t, a string. Raises an error
-- when value doesn't fit t or uses something not implemented.
function uper.encode(t, value)
    return encodeComplete(t, value, "")
end

-- Returns the bits of value of type t as a string of 0 and 1, without the
-- padding of a complete encoding, for tests
function uper.encodeBits(t, value)
    local w = uper.newWriter()
    encodeValue(w, t, value, "")
    return w:bitString()
end

-- Returns the value of type t in the complete encoding data, or nil and an
-- error message. data comes from other players, so it is untrusted: every
-- error, including bugs, is returned instead of raised.
function uper.decode(t, data)
    if type(data) ~= "string" then
        return nil, "uper: data must be a string"
    end
    local ok, result = pcall(decodeComplete, t, data, "")
    if not ok then
        return nil, tostring(result)
    end
    return result
end

return kacklaUper

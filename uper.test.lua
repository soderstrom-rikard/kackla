-- Tests uPER, run with make test. uper.lua is independent of the rest of
-- kackla, so testsetup isn't needed.
--
-- Expected encodings come from ITU-T X.691 (02/2021): the UNALIGNED examples
-- of Annex A and the examples in clause 11.9. The rest are derived by hand
-- from the clauses, with each bit commented.
require("uper")

local UNKNOWN = kacklaUper.UNKNOWN

-- Returns the bytes of s as uppercase hex without spaces, e.g. "9E00"
local function hex(s)
    return (string.gsub(s, ".", function(c) return string.format("%02X", string.byte(c)) end))
end

-- Returns the string of the bytes in hex, e.g. "9E00" -> "\158\0"
local function bytes(hexString)
    return (string.gsub(hexString, "%x%x", function(h) return string.char(tonumber(h, 16)) end))
end

-- Returns the complete encoding of a string of 0 and 1 (spaces are
-- ignored), padded with zero bits
local function fromBits(bits)
    local w = kacklaUper.newWriter()
    for bit in string.gmatch(bits, "[01]") do
        w:bit(bit == "1")
    end
    return w:complete()
end

-- Returns true when a and b are equal, comparing tables by content
local function deepEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for k, v in pairs(a) do
        if not deepEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- Returns value as a readable string, for error messages
local function show(value)
    if type(value) ~= "table" or value == UNKNOWN then
        return tostring(value)
    end
    local parts = {}
    for k, v in pairs(value) do
        table.insert(parts, tostring(k) .. "=" .. show(v))
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
end

-- Asserts that value of type t encodes to the bits expected (spaces are
-- ignored), and that its complete encoding decodes back to value
local function checkBits(name, t, value, expected)
    expected = string.gsub(expected, " ", "")
    local got = kacklaUper.encodeBits(t, value)
    assert(got == expected, name .. ": expected bits " .. expected .. " got " .. got)
    local decoded, err = kacklaUper.decode(t, kacklaUper.encode(t, value))
    assert(err == nil, name .. ": " .. tostring(err))
    assert(deepEqual(decoded, value), name .. ": decoded " .. show(decoded) .. " expected " .. show(value))
end

-- Asserts that func raises an error containing text
local function checkError(name, text, func, ...)
    local ok, err = pcall(func, ...)
    assert(not ok, name .. ": should fail")
    assert(string.find(err, text, 1, true), name .. ": expected an error with '" .. text .. "' got '" .. err .. "'")
end

-- Asserts that decoding data as t fails with an error containing text
local function checkDecodeError(name, text, t, data)
    local value, err = kacklaUper.decode(t, data)
    assert(value == nil, name .. ": should not decode, got " .. show(value))
    assert(string.find(err, text, 1, true), name .. ": expected an error with '" .. text .. "' got '" .. err .. "'")
end

local BOOLEAN = {type = "BOOLEAN"}
local NULL = {type = "NULL"}

-- Tests the bit writer and reader, and the complete encoding (11.1.3.1)
function checkBitsAndComplete()
    local w = kacklaUper.newWriter()
    w:number(5, 3)
    w:bit(true)
    w:octets("\255")
    assert(w:bitString() == "101" .. "1" .. "11111111", "writer bits " .. w:bitString())
    -- padded with zero bits to whole octets
    assert(w:complete() == bytes("BFF0"), "complete " .. hex(w:complete()))
    -- nothing written is a single zero octet
    assert(kacklaUper.newWriter():complete() == "\0", "empty complete encoding")

    local r = kacklaUper.newReader(bytes("BFF0"))
    assert(r:number(3) == 5 and r:bit() and r:octets(1) == "\255", "reader")
    assert(r:number(4) == 0, "reader padding")
    checkError("reading past the end", "the data ends", r.number, r, 1)
end

-- Tests BOOLEAN (clause 12), NULL (clause 18) and INTEGER (clause 13)
function checkSimpleTypes()
    checkBits("TRUE", BOOLEAN, true, "1")
    checkBits("FALSE", BOOLEAN, false, "0")
    checkBits("NULL", NULL, true, "")
    assert(kacklaUper.encode(NULL, true) == "\0", "NULL alone is a zero octet")

    -- A.4 "a INTEGER (250..253)" = 253
    checkBits("A.4 a", {type = "INTEGER", min = 250, max = 253}, 253, "11")
    -- A.3 "EmployeeNumber INTEGER (0..9999, ...)" = 51: extension bit, then
    -- 14 bits since 2^13 < 10000 <= 2^14
    checkBits("A.3 number", {type = "INTEGER", min = 0, max = 9999, extensible = true}, 51,
              "0 00000000110011")
    checkBits("INTEGER (0..255)", {type = "INTEGER", min = 0, max = 255}, 200, "11001000")
    -- a range of 1 has no bits (11.5.4)
    checkBits("INTEGER (5..5)", {type = "INTEGER", min = 5, max = 5}, 5, "")
    checkBits("INTEGER (0..16777215)", {type = "INTEGER", min = 0, max = 16777215}, 0xFF8000,
              "111111111000000000000000")
    checkBits("INTEGER (-5..5)", {type = "INTEGER", min = -5, max = 5}, -5, "0000")

    local byte = {type = "INTEGER", min = 0, max = 255}
    checkError("INTEGER too big", "not a whole number in 0..255", kacklaUper.encode, byte, 256)
    checkError("INTEGER not whole", "not a whole number", kacklaUper.encode, byte, 1.5)
    checkError("INTEGER not a number", "not a whole number", kacklaUper.encode, byte, "1")
    checkError("INTEGER outside extension root", "not implemented", kacklaUper.encode,
               {type = "INTEGER", min = 0, max = 9, extensible = true}, 10)
    checkError("INTEGER without bounds", "not implemented", kacklaUper.encode, {type = "INTEGER"}, 1)
    -- 2 bits can hold 3, which is outside 0..2
    checkDecodeError("INTEGER (0..2) = 3", "outside 0..2", {type = "INTEGER", min = 0, max = 2}, bytes("C0"))
    checkDecodeError("INTEGER outside extension root", "not implemented",
                     {type = "INTEGER", min = 0, max = 9, extensible = true}, bytes("80"))
end

-- Tests ENUMERATED (clause 14)
function checkEnumerated()
    -- A.3 "sex ENUMERATED {male(1), female(2), unknown(3)}" = female
    local sex = {type = "ENUMERATED", values = {"male", "female", "unknown"}}
    checkBits("A.3 sex", sex, "female", "01")
    -- its complete encoding, from the open type in A.3.4
    assert(kacklaUper.encode(sex, "female") == bytes("40"), "A.3 sex complete encoding")

    local v1 = {type = "ENUMERATED", values = {"red", "green"}, extensible = true}
    local v2 = {type = "ENUMERATED", values = {"red", "green"}, extensible = true, additions = {"blue"}}
    -- extension bit 0, index 1 of 2 in 1 bit
    checkBits("ENUMERATED root value", v2, "green", "0 1")
    -- extension bit 1, index 0 as a normally small number (11.6.1): 0 and 6 bits
    checkBits("ENUMERATED addition", v2, "blue", "1 0 000000")
    -- an older version decodes the addition as UNKNOWN
    assert(kacklaUper.decode(v1, kacklaUper.encode(v2, "blue")) == UNKNOWN, "unknown addition")
    checkError("ENUMERATED unknown name", "not a value", kacklaUper.encode, v2, "pink")
    checkError("ENUMERATED UNKNOWN", "not a value", kacklaUper.encode, v1, UNKNOWN)
    checkDecodeError("ENUMERATED index 3 of 3", "outside 0..2",
                     {type = "ENUMERATED", values = {"a", "b", "c"}}, bytes("C0"))
end

-- A.4 Ax as an older version that only knows the extension root: a, b, c
-- with only d, and the root fields i and j after the extensions (encoded as
-- if they were before them, 19.9 Note 2)
local AxRoot = {
    type = "SEQUENCE",
    extensible = true,
    fields = {
        {"a", {type = "INTEGER", min = 250, max = 253}},
        {"b", BOOLEAN},
        {"c", {type = "CHOICE", extensible = true, alternatives = {{"d", {type = "INTEGER"}}}}},
        {"i", {type = "BMPString"}, optional = true},
        {"j", {type = "PrintableString"}, optional = true},
    },
}

-- Ax's c knowing its extension additions e and f
local AxChoiceC = {
    type = "CHOICE",
    extensible = true,
    alternatives = {{"d", {type = "INTEGER"}}},
    additions = {{"e", BOOLEAN}, {"f", {type = "IA5String"}}},
}

-- Ax knowing c's extension additions e and f, but not Ax's own additions
local AxChoice = {
    type = "SEQUENCE",
    extensible = true,
    fields = {
        AxRoot.fields[1],
        AxRoot.fields[2],
        {"c", AxChoiceC},
        AxRoot.fields[4],
        AxRoot.fields[5],
    },
}

-- A.4.4.1: { a 253, b TRUE, c e : TRUE, g "123", h TRUE }
local AX_ENCODING = bytes("9E000600040A4690")

-- Tests CHOICE (clause 23) and SEQUENCE (clause 19) with X.691 Annex A
function checkChoiceAndSequence()
    -- An older version skips everything it doesn't know
    local value, err = kacklaUper.decode(AxRoot, AX_ENCODING)
    assert(err == nil, "A.4 decode: " .. tostring(err))
    assert(deepEqual(value, {a = 253, b = true, c = {UNKNOWN, 0}}), "A.4 root decode " .. show(value))

    value, err = kacklaUper.decode(AxChoice, AX_ENCODING)
    assert(err == nil, "A.4 decode: " .. tostring(err))
    assert(deepEqual(value, {a = 253, b = true, c = {"e", true}}), "A.4 choice decode " .. show(value))

    -- The same value without g and h: the A.4 bits with the extension bit 0
    -- and without the additions after c.e
    checkBits("A.4 without additions", AxChoice, {a = 253, b = true, c = {"e", true}},
              "0" ..         -- no extension additions in Ax
              "00" ..        -- i and j absent
              "11" ..        -- a = 253
              "1" ..         -- b = TRUE
              "1" ..         -- c's alternative is an extension addition
              "0 000000" ..  -- choice index 0 selects c.e
              "00000001" ..  -- length of c.e = 1 octet
              "10000000")    -- c.e = TRUE, padded to an octet
    assert(kacklaUper.encode(AxChoice, {a = 253, b = true, c = {"e", true}}) == bytes("1E000600"),
           "A.4 without additions, complete encoding")

    -- A.3.4 children[1]: an extension bit 1 and the addition "sex = female"
    -- after the root fields, here a single BOOLEAN instead of name and
    -- dateOfBirth. An older version without "sex" skips it.
    local child = {type = "SEQUENCE", extensible = true, fields = {{"b", BOOLEAN}}}
    local encoding = bytes("C0405000")
    -- 1         extension values present
    -- 1         b = TRUE
    -- 0 000000  length of the extension addition bitmap = 1 (11.9.3.4)
    -- 1         "sex" is present
    -- 00000001  length of the complete encoding of "sex" = 1 octet
    -- 01000000  "sex" = female, padded
    -- 000000    padding
    value, err = kacklaUper.decode(child, encoding)
    assert(err == nil and deepEqual(value, {b = true}), "A.3 skipping sex: " .. tostring(err) .. " " .. show(value))

    -- two unknown additions, then a field after the SEQUENCE: both must be
    -- skipped completely
    local outer = {type = "SEQUENCE", fields = {{"s", child}, {"z", BOOLEAN}}}
    value, err = kacklaUper.decode(outer, fromBits(
        "1" ..                      -- s: extension values present
        "1" ..                      -- s.b = TRUE
        "0 000001" ..               -- 2 additions in the bitmap
        "1 1" ..                    -- both present
        "00000001 10101010" ..      -- addition 1, 1 octet
        "00000010 01010101 11111111" .. -- addition 2, 2 octets
        "1"))                       -- z = TRUE
    assert(err == nil and deepEqual(value, {s = {b = true}, z = true}),
           "skipping two additions: " .. tostring(err) .. " " .. show(value))

    -- a single alternative has no index bits (23.4)
    checkBits("CHOICE with one alternative", {type = "CHOICE", alternatives = {{"x", BOOLEAN}}},
              {"x", true}, "1")
    checkBits("CHOICE of three", {type = "CHOICE", alternatives = {{"x", BOOLEAN}, {"y", NULL}, {"z", BOOLEAN}}},
              {"z", false}, "10 0")
    local optionalFields = {
        type = "SEQUENCE",
        fields = {
            {"x", BOOLEAN, optional = true},
            {"y", BOOLEAN},
            {"z", BOOLEAN, optional = true},
        },
    }
    checkBits("OPTIONAL fields", optionalFields, {y = true, z = false}, "0 1" .. "1" .. "0")

    checkError("CHOICE unknown alternative", "not an alternative", kacklaUper.encode, AxRoot.fields[3][2], {"e", true})
    checkError("SEQUENCE missing field", "field 'b' is missing", kacklaUper.encode, AxRoot, {a = 250})
    checkError("SEQUENCE error path", "uper: a: ", kacklaUper.encode, AxRoot, {a = 1, b = true, c = {"d", 1}})
    checkError("nested error path", "uper: c.e: expected a boolean", kacklaUper.encode, AxChoice,
               {a = 250, b = true, c = {"e", 1}})
    checkError("unimplemented type", "uper: i: type BMPString is not implemented", kacklaUper.encode, AxChoice,
               {a = 250, b = true, c = {"e", true}, i = "x"})
    checkError("INTEGER without bounds in a CHOICE", "uper: c.d: INTEGER without both bounds", kacklaUper.encode,
               AxRoot, {a = 250, b = true, c = {"d", 1}})
    checkError("SEQUENCE additions", "SEQUENCE extension additions is not implemented", kacklaUper.encode,
               {type = "SEQUENCE", fields = {}, extensible = true, additions = {}}, {})
    checkDecodeError("CHOICE index 3 of 3", "outside 0..2",
                     {type = "CHOICE", alternatives = {{"x", NULL}, {"y", NULL}, {"z", NULL}}}, bytes("C0"))
    checkDecodeError("A.4 cut off", "the data ends", AxRoot, string.sub(AX_ENCODING, 1, 5))
end

-- Tests SEQUENCE OF (clause 20) and length determinants (11.9)
function checkSequenceOf()
    -- A.3 "children SEQUENCE (SIZE(2, ...))": only the extension bit, the
    -- fixed size has no length (20.5)
    checkBits("SIZE(2, ...)", {type = "SEQUENCE OF", of = BOOLEAN, min = 2, max = 2, extensible = true},
              {true, false}, "0" .. "1 0")
    -- 2 in 1..32 is 1 in 5 bits
    checkBits("SIZE(1..32)", {type = "SEQUENCE OF", of = BOOLEAN, min = 1, max = 32}, {true, true}, "00001 1 1")

    -- 11.9.3.6 Note: "B ::= SEQUENCE (SIZE (4..123456)) OF INTEGER" with 4
    -- items has the length 0 0000100, its upper bound is 64K or more
    local big = {type = "SEQUENCE OF", of = BOOLEAN, min = 4, max = 123456}
    checkBits("11.9.3.6 example", big, {true, true, true, true}, "0 0000100" .. "1111")
    -- 11.9.3.7 Note: 130 items have the length 10 000000 10000010
    local items = {}
    for i = 1, 130 do items[i] = false end
    local bits = kacklaUper.encodeBits(big, items)
    assert(string.sub(bits, 1, 16) == "1000000010000010", "11.9.3.7 example: " .. string.sub(bits, 1, 16))
    assert(deepEqual(kacklaUper.decode(big, kacklaUper.encode(big, items)), items), "130 items round trip")

    local unbounded = {type = "SEQUENCE OF", of = NULL}
    local many = {}
    for i = 1, 16384 do many[i] = true end
    checkError("16K items", "fragmentation", kacklaUper.encode, unbounded, many)
    checkDecodeError("16K items", "fragmentation", unbounded, bytes("C1"))

    checkError("too few", "expected 1..32", kacklaUper.encode, {type = "SEQUENCE OF", of = BOOLEAN, min = 1, max = 32}, {})
    checkError("outside extension root", "not implemented", kacklaUper.encode,
               {type = "SEQUENCE OF", of = BOOLEAN, min = 2, max = 2, extensible = true}, {true})
    -- 2 items (0 0000010) for SIZE (4..123456), whose length isn't bounded
    -- by its encoding
    checkDecodeError("too few", "expected 4..123456", big, bytes("02"))
end

-- The draft messages from docs/communication-layer.md
local NamedColor = {
    type = "ENUMERATED",
    extensible = true,
    values = {
        "red",
        "green",
        "blue",
        "yellow",
        "orange",
        "purple",
        "pink",
        "cyan",
        "white",
        "gray",
        "black",
    },
}
local ClassColor = {
    type = "ENUMERATED",
    extensible = true,
    values = {
        "warrior",
        "paladin",
        "hunter",
        "rogue",
        "priest",
        "deathKnight",
        "shaman",
        "mage",
        "warlock",
        "monk",
        "druid",
        "demonHunter",
        "evoker",
    },
}
local ItemQuality = {
    type = "ENUMERATED",
    extensible = true,
    values = {
        "poor",
        "common",
        "uncommon",
        "rare",
        "epic",
        "legendary",
        "artifact",
        "heirloom",
    },
}
local Color = {
    type = "CHOICE",
    extensible = true,
    alternatives = {
        {"reset", NULL},
        {"rgb", {type = "INTEGER", min = 0, max = 16777215}},
        {"named", NamedColor},
        {"class", ClassColor},
        {"quality", ItemQuality},
    },
}
local ColorSpan = {
    type = "SEQUENCE",
    fields = {
        {"start", {type = "INTEGER", min = 0, max = 255}},
        {"color", Color},
    },
}
local ChatColors = {
    type = "SEQUENCE",
    extensible = true,
    fields = {
        {"textHash", {type = "INTEGER", min = 0, max = 65535}},
        {"spans", {type = "SEQUENCE OF", min = 1, max = 32, of = ColorSpan}},
    },
}
local Message = {type = "CHOICE", extensible = true, alternatives = {{"chatColors", ChatColors}}}

-- Tests the draft messages, and that random data never raises errors
function checkMessages()
    local spans = {
        {start = 0, color = {"named", "red"}},
        {start = 5, color = {"reset", true}},
    }
    local message = {"chatColors", {textHash = 0x1234, spans = spans}}
    checkBits("ChatColors", Message, message,
              "0" ..                  -- Message: no extension, one alternative so no index
              "0" ..                  -- ChatColors: no extension
              "0001001000110100" ..   -- textHash = 0x1234
              "00001" ..              -- 2 spans in 1..32
              "00000000" ..           -- span 1: start = 0
              "0 010" ..              --   color: no extension, index 2 = named
              "0 0000" ..             --   red: no extension, index 0 of 11
              "00000101" ..           -- span 2: start = 5
              "0 000")                --   color: no extension, index 0 = reset
    -- 52 bits, 7 octets as the design note estimates
    assert(#kacklaUper.encode(Message, message) == 7, "ChatColors size")

    -- a newer version's message type is UNKNOWN to this version
    local newer = {
        type = "CHOICE",
        extensible = true,
        alternatives = Message.alternatives,
        additions = {{"ping", NULL}, {"pong", BOOLEAN}},
    }
    local value = kacklaUper.decode(Message, kacklaUper.encode(newer, {"ping", true}))
    assert(deepEqual(value, {UNKNOWN, 0}), "unknown message " .. show(value))
    value = kacklaUper.decode(Message, kacklaUper.encode(newer, {"pong", false}))
    assert(deepEqual(value, {UNKNOWN, 1}), "second unknown message " .. show(value))

    -- random data decodes or returns an error, never raises one
    math.randomseed(2)
    local decoded = 0
    for _ = 1, 2000 do
        local data = {}
        for i = 1, math.random(0, 12) do
            data[i] = string.char(math.random(0, 255))
        end
        local ok, result, err = pcall(kacklaUper.decode, Message, table.concat(data))
        assert(ok, "decode raised: " .. tostring(result))
        assert((result == nil) ~= (err == nil), "decode returns a value or an error")
        if result then decoded = decoded + 1 end
    end
    assert(decoded > 0, "some random data should decode")
end

print("Verify uPER start")
checkBitsAndComplete()
checkSimpleTypes()
checkEnumerated()
checkChoiceAndSequence()
checkSequenceOf()
checkMessages()
print("Verify uPER done")

-- Tests COBS, run with make test. cobs.lua is independent of the rest of
-- kackla, so testsetup isn't needed.
require("cobs")

-- Returns the bytes of s as uppercase hex, e.g. "01 FF"
local function hex(s)
    return (string.gsub(s, ".", function(c) return string.format("%02X ", string.byte(c)) end):gsub(" $", ""))
end

-- Returns the string of the bytes first to last
local function range(first, last)
    local bytes = {}
    for byte = first, last do
        table.insert(bytes, string.char(byte))
    end
    return table.concat(bytes)
end

-- The examples from the Wikipedia article, without the 00 delimiter it adds
-- after each encoding
local EXAMPLES = {
    {"\0", "\1\1"},
    {"\0\0", "\1\1\1"},
    {"\0\17\0", "\1\2\17\1"},
    {"\17\34\0\51", "\3\17\34\2\51"},
    {"\17\34\51\68", "\5\17\34\51\68"},
    {"\17\0\0\0", "\2\17\1\1\1"},
    {range(1, 254), "\255" .. range(1, 254)},
    {range(0, 254), "\1\255" .. range(1, 254)},
    {range(1, 255), "\255" .. range(1, 254) .. "\2\255"},
    {range(2, 255) .. "\0", "\255" .. range(2, 255) .. "\1\1"},
    {range(3, 255) .. "\0\1", "\254" .. range(3, 255) .. "\2\1"},
}

-- Tests the examples, decoding of everything encoded, and invalid input
function checkCobs()
    print("Verify COBS start")
    for i, example in ipairs(EXAMPLES) do
        local data, expected = example[1], example[2]
        local encoded = kacklaCobs.encode(data)
        assert(encoded == expected, "example " .. i .. ": expected " .. hex(expected) .. " got " .. hex(encoded))
        assert(kacklaCobs.decode(encoded) == data, "example " .. i .. " doesn't decode")
    end

    assert(kacklaCobs.encode("") == "\1", "empty data encodes to 01")
    assert(kacklaCobs.decode("\1") == "", "01 decodes to empty data")

    -- every length up to two full blocks, with and without NUL bytes, and the
    -- worst case overhead of 1 byte per 254 plus 1
    for length = 0, 2 * 254 + 3 do
        for _, fill in ipairs({"\0", "\7", "mixed"}) do
            local bytes = {}
            for i = 1, length do
                bytes[i] = fill == "mixed" and string.char((i * 37) % 256) or fill
            end
            local data = table.concat(bytes)
            local encoded = kacklaCobs.encode(data)
            assert(not string.find(encoded, "\0", 1, true), "encoding of " .. length .. " bytes contains NUL")
            assert(#encoded <= length + math.ceil(length / 254) + 1, "too long encoding of " .. length .. " bytes")
            assert(kacklaCobs.decode(encoded) == data, "round trip of " .. length .. " bytes " .. fill)
        end
    end

    -- any 254 bytes fit a 255-byte addon message, 255 bytes don't always
    math.randomseed(1)
    for _ = 1, 200 do
        local bytes = {}
        for i = 1, 254 do
            -- about one in four bytes is NUL
            bytes[i] = math.random(4) == 1 and "\0" or string.char(math.random(1, 255))
        end
        assert(#kacklaCobs.encode(table.concat(bytes)) == 255, "254 bytes should take 255")
    end
    assert(#kacklaCobs.encode(string.rep("\7", 254)) == 255, "254 bytes without NUL take 255")
    assert(#kacklaCobs.encode(string.rep("\7", 255)) == 257, "255 bytes without NUL take 257")

    -- invalid encodings are reported, not raised
    for _, invalid in ipairs({"", "\0", "\3\1", "\2\0", "\5\1\2"}) do
        local data, err = kacklaCobs.decode(invalid)
        assert(data == nil and type(err) == "string", "'" .. hex(invalid) .. "' should be invalid")
    end
    print("Verify COBS done")
end

checkCobs()

-- Consistent Overhead Byte Stuffing (COBS), removes the NUL bytes that addon
-- messages can't contain (see docs/communication-layer.md).
--
-- The data is split at its NUL bytes into blocks. Each block is sent as a
-- code byte (its length + 1) followed by its bytes, the NUL after it is
-- implied. A block of 254 bytes has code 255 and no NUL after it, so the
-- output never contains NUL and grows by at most 1 byte per 254, plus 1.
-- No delimiter is added, each addon message holds exactly one encoding.
--
-- https://en.wikipedia.org/wiki/Consistent_Overhead_Byte_Stuffing

kacklaCobs = {}

-- the most bytes a block can hold, giving code 255
local MAX_BLOCK = 254

-- Returns data with its NUL bytes removed, data is a string of any bytes
function kacklaCobs.encode(data)
    assert(type(data) == "string", "kacklaCobs.encode: data must be a string")
    local out = {}
    local block = {}
    -- true right after a full block, which has no implied NUL after it
    local afterFullBlock = false

    local function flush()
        table.insert(out, string.char(#block + 1))
        table.insert(out, table.concat(block))
        afterFullBlock = #block == MAX_BLOCK
        block = {}
    end

    for i = 1, #data do
        local byte = string.sub(data, i, i)
        if byte == "\0" then
            flush()
        else
            table.insert(block, byte)
            if #block == MAX_BLOCK then
                flush()
            end
        end
    end
    -- the last block, unless the data ended exactly with a full block
    if #block > 0 or not afterFullBlock then
        flush()
    end
    return table.concat(out)
end

-- Returns the data encoded by kacklaCobs.encode, or nil and an error message
-- when encoded isn't a valid encoding (it comes from other players, so it is
-- untrusted)
function kacklaCobs.decode(encoded)
    if type(encoded) ~= "string" or encoded == "" then
        return nil, "cobs: empty encoding"
    end
    local out = {}
    local pos = 1
    while pos <= #encoded do
        local code = string.byte(encoded, pos)
        if code == 0 then
            return nil, "cobs: NUL byte at " .. pos
        end
        local last = pos + code - 1
        if last > #encoded then
            return nil, "cobs: block at " .. pos .. " is cut off"
        end
        local block = string.sub(encoded, pos + 1, last)
        if string.find(block, "\0", 1, true) then
            return nil, "cobs: NUL byte in block at " .. pos
        end
        table.insert(out, block)
        pos = last + 1
        -- every block except a full one is followed by a NUL, except the last
        if code < MAX_BLOCK + 1 and pos <= #encoded then
            table.insert(out, "\0")
        end
    end
    return table.concat(out)
end

return kacklaCobs

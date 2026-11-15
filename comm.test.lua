-- Tests the communication layer, run with make test. comm.lua only needs
-- cobs.lua, uper.lua, messages.lua and the WoW API mocked here, so
-- testsetup isn't needed.
require("cobs")
require("uper")
require("messages")
require("comm")

-- Simulated clock and timers (C_Timer), run with RunUntil
local now = 0
local timers = {}
-- order of creation, so timers due at the same time run in that order
local timerCount = 0
GetTime = function() return now end
C_Timer = {
    After = function(delay, func)
        timerCount = timerCount + 1
        table.insert(timers, {time = now + delay, seq = timerCount, func = func})
    end,
    NewTicker = function(interval, func)
        local ticker = {cancelled = false}
        function ticker:Cancel() self.cancelled = true end
        local function tick()
            if not ticker.cancelled then
                func()
                if not ticker.cancelled then
                    C_Timer.After(interval, tick)
                end
            end
        end
        C_Timer.After(interval, tick)
        return ticker
    end,
}

-- Runs the timers due until time, in order
local function RunUntil(time)
    while true do
        table.sort(timers, function(a, b)
            return a.time < b.time or (a.time == b.time and a.seq < b.seq)
        end)
        local timer = timers[1]
        if not timer or timer.time > time then
            break
        end
        table.remove(timers, 1)
        now = timer.time
        timer.func()
    end
    now = time
end

Enum = {
    SendAddonMessageResult = {
        Success = 0,
        InvalidMessage = 2,
        AddonMessageThrottle = 3,
        InvalidChatType = 4,
        NotInGroup = 5,
    },
}

-- Simulated server: a throttle of serverBurst frames refilling 1 per second,
-- every sent frame is recorded in wire and arrives back after a short delay
-- as from "Me", like guild messages and whispers to yourself do
local wire = {}
local serverBurst, serverTokens, serverRefill = 10, 10, 0
local notInGroup = false
-- sends refused by the server's throttle
local throttled = 0
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return 0 end,
    SendAddonMessage = function(prefix, text, chatType, target)
        serverTokens = math.min(serverBurst, serverTokens + (now - serverRefill))
        serverRefill = now
        if #text > 255 or string.find(text, "\0", 1, true) then
            return Enum.SendAddonMessageResult.InvalidMessage
        end
        if notInGroup and chatType == "PARTY" then
            return Enum.SendAddonMessageResult.NotInGroup
        end
        if serverTokens < 1 then
            throttled = throttled + 1
            return Enum.SendAddonMessageResult.AddonMessageThrottle
        end
        serverTokens = serverTokens - 1
        table.insert(wire, {text = text, chatType = chatType, time = now})
        C_Timer.After(0.05, function() kacklaComm.onAddonMessage(prefix, text, chatType, "Me") end)
        return Enum.SendAddonMessageResult.Success
    end,
}

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

-- Returns a chatColors message with textHash id and count spans
local function ColorsMessage(id, count)
    local spans = {}
    for i = 1, count or 1 do
        spans[i] = {start = i - 1, color = {"rgb", (i * 99991) % 16777216}}
    end
    return {"chatColors", {textHash = id, spans = spans}}
end

-- Resets the layer, the clock and the simulated server, and returns the list
-- the chatColors handler collects {value, info} into
local function Fresh()
    kacklaComm.reset()
    now, timers, wire = 0, {}, {}
    serverBurst, serverTokens, serverRefill = 10, 10, 0
    notInGroup = false
    throttled = 0
    local received = {}
    kacklaComm.on("chatColors", function(value, info)
        table.insert(received, {value = value, info = info})
    end)
    return received
end

-- Returns the frame of a wire text: version, FrameHeader and the chunk
local function OpenFrame(text)
    local frame = assert(kacklaCobs.decode(text))
    local header = assert(kacklaUper.decode(kacklaMessages.FrameHeader, string.sub(frame, 2, 3)))
    return string.byte(frame, 1), header, string.sub(frame, 4)
end

-- Tests how messages are split into frames
function checkFrames()
    Fresh()
    local frames = kacklaComm.makeFrames(string.rep("\0", 251), 7)
    assert(#frames == 1, "251 bytes are one frame")
    assert(#frames[1] == 255, "a full frame fills 255 bytes, got " .. #frames[1])
    local version, header, chunk = OpenFrame(frames[1])
    assert(version == 1, "version byte")
    assert(deepEqual(header, {messageId = 7, fragmentIndex = 0, lastFragment = true}), "single frame header")
    assert(chunk == string.rep("\0", 251), "single frame chunk")

    frames = kacklaComm.makeFrames(string.rep("x", 252), 8)
    assert(#frames == 2, "252 bytes are two frames")
    local _, first = OpenFrame(frames[1])
    local _, second, rest = OpenFrame(frames[2])
    assert(not first.lastFragment and second.lastFragment and second.fragmentIndex == 1 and rest == "x",
           "two frame headers")

    for _, frame in ipairs(kacklaComm.makeFrames(string.rep("\0\255", 16 * 251 / 2), 9)) do
        assert(#frame <= 255 and not string.find(frame, "\0", 1, true), "frames fit an addon message")
    end
    assert(#kacklaComm.makeFrames(string.rep("x", 16 * 251), 9) == 16, "16 frames at most")
    local ok, err = pcall(kacklaComm.makeFrames, string.rep("x", 16 * 251 + 1), 9)
    assert(not ok and string.find(err, "more than 16 frames", 1, true), "17 frames are refused")
end

-- Tests sending and receiving whole and fragmented messages
function checkRoundTrip()
    local received = Fresh()
    assert(kacklaComm.send(ColorsMessage(1), "GUILD"), "send to GUILD")
    RunUntil(1)
    assert(#received == 1, "one message received, got " .. #received)
    assert(deepEqual(received[1].value, ColorsMessage(1)[2]), "received value")
    assert(deepEqual(received[1].info, {sender = "Me", chatType = "GUILD"}), "received info")

    -- 32 rgb spans are about 150 bytes, 10 frames of 16 bytes
    received = Fresh()
    kacklaComm.maxChunk = 16
    kacklaComm.send(ColorsMessage(2, 32), "WHISPER", "Me Myself")
    RunUntil(5)
    assert(#wire == 10, "10 frames sent, got " .. #wire)
    assert(#received == 1 and deepEqual(received[1].value, ColorsMessage(2, 32)[2]), "fragmented message")
    assert(kacklaComm.bufferCount() == 0, "no buffer left")

    -- fragments arriving in reverse order, interleaved with another sender
    -- using the same messageId
    received = Fresh()
    kacklaComm.maxChunk = 16
    local frames = kacklaComm.makeFrames(kacklaUper.encode(kacklaMessages.Message, ColorsMessage(3, 20)), 5)
    local others = kacklaComm.makeFrames(kacklaUper.encode(kacklaMessages.Message, ColorsMessage(4, 20)), 5)
    for i = #frames, 1, -1 do
        kacklaComm.onAddonMessage("kackla", frames[i], "GUILD", "Alice")
        kacklaComm.onAddonMessage("kackla", others[#others + 1 - i], "GUILD", "Bob")
    end
    assert(#received == 2, "both messages received, got " .. #received)
    assert(received[1].info.sender == "Alice" and received[1].value.textHash == 3, "Alice's message")
    assert(received[2].info.sender == "Bob" and received[2].value.textHash == 4, "Bob's message")
end

-- Tests that untrusted input is dropped and buffers stay limited
function checkReceiving()
    local received = Fresh()
    kacklaComm.maxChunk = 16
    local frames = kacklaComm.makeFrames(kacklaUper.encode(kacklaMessages.Message, ColorsMessage(1, 20)), 1)

    -- a missing fragment: nothing delivered, the buffer expires
    for i = 1, #frames - 1 do
        kacklaComm.onAddonMessage("kackla", frames[i], "GUILD", "Alice")
    end
    assert(#received == 0 and kacklaComm.bufferCount() == 1, "incomplete message waits")
    now = 31
    kacklaComm.onAddonMessage("kackla", frames[#frames], "GUILD", "Alice")
    assert(#received == 0, "late last fragment doesn't complete an expired message")

    -- each sender keeps at most 4 incomplete messages, everyone 64
    Fresh()
    kacklaComm.maxChunk = 16
    for id = 0, 9 do
        local f = kacklaComm.makeFrames(string.rep("x", 40), id)
        kacklaComm.onAddonMessage("kackla", f[1], "GUILD", "Alice")
        now = now + 0.1
    end
    assert(kacklaComm.bufferCount() == 4, "4 buffers per sender, got " .. kacklaComm.bufferCount())
    for sender = 1, 100 do
        kacklaComm.onAddonMessage("kackla", kacklaComm.makeFrames(string.rep("x", 40), 0)[1], "GUILD", "S" .. sender)
        now = now + 0.1
    end
    assert(kacklaComm.bufferCount() == 64, "64 buffers in total, got " .. kacklaComm.bufferCount())

    -- other prefixes, other versions and garbage are ignored
    received = Fresh()
    local frame = kacklaComm.makeFrames(kacklaUper.encode(kacklaMessages.Message, ColorsMessage(1)), 0)[1]
    kacklaComm.onAddonMessage("other", frame, "GUILD", "Alice")
    assert(#received == 0, "other prefix ignored")
    local decoded = kacklaCobs.decode(frame)
    local printed = {}
    local originalPrint = print
    print = function(text) table.insert(printed, text) end
    -- an older version isn't warned about
    kacklaComm.onAddonMessage("kackla", kacklaCobs.encode("\0" .. string.sub(decoded, 2)), "GUILD", "Carol")
    kacklaComm.onAddonMessage("kackla", kacklaCobs.encode("\2" .. string.sub(decoded, 2)), "GUILD", "Alice")
    kacklaComm.onAddonMessage("kackla", kacklaCobs.encode("\3" .. string.sub(decoded, 2)), "GUILD", "Bob")
    print = originalPrint
    assert(#received == 0, "other versions ignored")
    assert(#printed == 1 and string.find(printed[1], "Alice uses a newer kackla", 1, true),
           "one warning about a newer version, got " .. #printed)

    math.randomseed(3)
    for _ = 1, 3000 do
        local bytes = {}
        for i = 1, math.random(0, 40) do
            bytes[i] = string.char(math.random(0, 255))
        end
        -- often a valid frame start, to get past COBS and the version byte
        local text = table.concat(bytes)
        if math.random(2) == 1 then
            text = kacklaCobs.encode("\1" .. text)
        end
        kacklaComm.onAddonMessage("kackla", text, "GUILD", "Mallory")
    end
    assert(kacklaComm.bufferCount() <= 4, "random frames are limited like any sender")

    -- a message type from a newer kackla is dropped without errors
    received = Fresh()
    local newer = {
        type = "CHOICE",
        extensible = true,
        alternatives = kacklaMessages.Message.alternatives,
        additions = {{"ping", {type = "NULL"}}},
    }
    local pingFrame = kacklaComm.makeFrames(kacklaUper.encode(newer, {"ping", true}), 0)[1]
    kacklaComm.onAddonMessage("kackla", pingFrame, "GUILD", "Alice")
    assert(#received == 0, "unknown message type dropped")
end

-- Tests the send queue: throttle, order, priority, expiry and failures
function checkSending()
    -- 15 messages: 10 at once, then 1 per second, never throttled by the server
    local received = Fresh()
    for id = 1, 15 do
        kacklaComm.send(ColorsMessage(id), "GUILD")
    end
    assert(#wire == 10, "the burst is sent at once, got " .. #wire)
    RunUntil(4.95)
    assert(#wire == 14, "then 1 per second, got " .. #wire)
    RunUntil(10)
    assert(#received == 15, "all arrive, got " .. #received)
    for i = 1, 15 do
        assert(received[i].value.textHash == i, "in order")
    end
    assert(kacklaComm.queueLength() == 0, "queue empty")
    assert(throttled == 0, "staying within the throttle, but the server refused " .. throttled)

    -- a server with a smaller burst than expected: throttled frames are retried
    received = Fresh()
    serverBurst, serverTokens = 3, 3
    for id = 1, 8 do
        kacklaComm.send(ColorsMessage(id), "GUILD")
    end
    RunUntil(20)
    assert(#received == 8, "throttled messages are retried, got " .. #received)
    -- after a refusal, wait for the throttle instead of retrying every tick
    assert(throttled <= 6, "too many refused retries: " .. throttled)

    -- a fragmented message's frames aren't interleaved with others
    Fresh()
    kacklaComm.maxChunk = 16
    kacklaComm.send(ColorsMessage(1, 10), "GUILD")
    kacklaComm.maxChunk = 251
    kacklaComm.send(ColorsMessage(2), "GUILD")
    RunUntil(10)
    local lastIds = {}
    for _, sent in ipairs(wire) do
        local _, header = OpenFrame(sent.text)
        table.insert(lastIds, header.messageId)
    end
    for i = 2, #lastIds do
        assert(lastIds[i] >= lastIds[i - 1], "frames of message " .. lastIds[i - 1] .. " interleaved")
    end

    -- priority never overtakes a partly sent message: 15 frames, the burst
    -- sends 10, then a priority message
    Fresh()
    kacklaComm.maxChunk = 10
    kacklaComm.send(ColorsMessage(1, 32), "GUILD")
    assert(#wire == 10, "burst of a long message")
    kacklaComm.maxChunk = 251
    kacklaComm.send(ColorsMessage(2), "GUILD", nil, {priority = 5})
    RunUntil(30)
    local ids = {}
    for _, sent in ipairs(wire) do
        local _, header = OpenFrame(sent.text)
        table.insert(ids, header.messageId)
    end
    assert(ids[#ids] == 1, "priority message after the partly sent one: " .. table.concat(ids, ","))

    -- priority overtakes waiting messages, expired ones are dropped
    received = Fresh()
    for id = 1, 12 do
        kacklaComm.send(ColorsMessage(id), "GUILD")
    end
    kacklaComm.send(ColorsMessage(100), "GUILD", nil, {priority = 1})
    kacklaComm.send(ColorsMessage(200), "GUILD", nil, {expiresIn = 1.5})
    RunUntil(20)
    local order = {}
    for _, r in ipairs(received) do
        table.insert(order, r.value.textHash)
    end
    assert(order[11] == 100, "priority message sent first among the waiting, order " .. table.concat(order, ","))
    for _, id in ipairs(order) do
        assert(id ~= 200, "expired message was sent")
    end
    assert(#order == 13, "12 messages and the priority one, got " .. #order)

    -- chat types without addon messages, and failing sends
    Fresh()
    assert(kacklaComm.send(ColorsMessage(1), "SAY") == false, "SAY can't carry addon messages")
    assert(kacklaComm.send(ColorsMessage(1), "YELL") == false, "YELL can't carry addon messages")
    notInGroup = true
    received = Fresh()
    notInGroup = true
    kacklaComm.send(ColorsMessage(1), "PARTY")
    kacklaComm.send(ColorsMessage(2), "GUILD")
    RunUntil(5)
    assert(#received == 1 and received[1].value.textHash == 2, "a failed message is dropped, the next is sent")

    -- messageId wraps around after 255
    Fresh()
    for id = 1, 257 do
        kacklaComm.send(ColorsMessage(id), "GUILD")
    end
    RunUntil(300)
    local _, header = OpenFrame(wire[257].text)
    assert(#wire == 257 and header.messageId == 0, "messageId wraps to 0")

    local ok = pcall(kacklaComm.send, {"chatColors", {textHash = 1, spans = {}}}, "GUILD")
    assert(not ok, "invalid messages are refused when sending")
end

print("Verify communication layer start")
checkFrames()
checkRoundTrip()
checkReceiving()
checkSending()
print("Verify communication layer done")

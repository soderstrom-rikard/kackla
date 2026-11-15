-- The communication layer: kackla-to-kackla messages sent as hidden addon
-- messages, see docs/communication-layer.md.
--
-- Sending: a Message (docs/kackla.asn) is encoded with uPER, split into
-- frames of at most 254 bytes, each COBS encoded so it holds no NUL bytes and
-- fits a 255-byte addon message. Frames wait in a queue that stays within
-- the throttle (a burst of 10, then 1 per second).
--
-- Receiving: frames are COBS decoded, reassembled per sender and messageId,
-- decoded and passed to the handler registered for the message type with
-- kacklaComm.on. Everything received is untrusted: invalid frames are dropped
-- silently, and the reassembly buffers are limited.
--
-- Each frame, before COBS:
--   1 byte    protocol version (kacklaComm.VERSION)
--   2 bytes   FrameHeader, uPER (13 bits, padded)
--   the rest  a fragment of the encoded Message

kacklaComm = {}
local comm = kacklaComm

comm.PREFIX = "kackla"
comm.VERSION = 1
-- bytes before COBS, which adds 1, filling a 255-byte addon message
comm.FRAME_SIZE = 254
-- version byte and FrameHeader
comm.HEADER_SIZE = 3
-- message bytes per frame, tests lower it to produce more fragments
comm.maxChunk = comm.FRAME_SIZE - comm.HEADER_SIZE
-- fragmentIndex is 0..15
comm.MAX_FRAGMENTS = 16
-- seconds an incomplete message waits for its missing fragments
comm.REASSEMBLY_TIMEOUT = 30
-- incomplete messages kept per sender and in total
comm.MAX_BUFFERS_PER_SENDER = 4
comm.MAX_BUFFERS = 64
-- the throttle measured in the Forever client: frames in a burst, frames
-- per second after it
comm.BURST = 10
comm.RATE = 1
-- seconds between attempts to send queued frames
comm.TICK = 0.1

-- Chat types that don't take addon messages (checked in the Forever client)
local UNSUPPORTED_CHAT_TYPES = {SAY = true, YELL = true}

local handlers = {}       -- message type -> function(value, info)
local buffers = {}        -- key -> incomplete message, see Reassemble
local queue = {}          -- messages waiting to be sent, see comm.send
local nextMessageId = 0
local tokens = comm.BURST -- frames that can be sent now
local lastRefill
local ticker
local warnedAboutVersion = false

--------------------------------------------------------------------------------
-- Receiving

-- Registers handler(value, info) for messages of type name, e.g.
-- "chatColors". info has sender and chatType. A later call replaces it.
function comm.on(name, handler)
    handlers[name] = handler
end

-- Returns the number of incomplete messages waiting for fragments, for tests
function comm.bufferCount()
    local count = 0
    for _ in pairs(buffers) do
        count = count + 1
    end
    return count
end

-- Removes incomplete messages older than REASSEMBLY_TIMEOUT
local function PruneBuffers(now)
    for key, buffer in pairs(buffers) do
        if now - buffer.created > comm.REASSEMBLY_TIMEOUT then
            buffers[key] = nil
        end
    end
end

-- Returns the key of the oldest buffer, of sender when given
local function OldestBuffer(sender)
    local oldestKey, oldest
    for key, buffer in pairs(buffers) do
        if (not sender or buffer.sender == sender) and (not oldest or buffer.created < oldest.created) then
            oldestKey, oldest = key, buffer
        end
    end
    return oldestKey
end

-- Removes the oldest buffers until sender and everyone together have room
-- for one more
local function MakeRoom(sender)
    local fromSender, total = 0, 0
    for _, buffer in pairs(buffers) do
        total = total + 1
        if buffer.sender == sender then
            fromSender = fromSender + 1
        end
    end
    if fromSender >= comm.MAX_BUFFERS_PER_SENDER then
        buffers[OldestBuffer(sender)] = nil
        total = total - 1
    end
    if total >= comm.MAX_BUFFERS then
        buffers[OldestBuffer()] = nil
    end
end

-- Adds a fragment to its incomplete message, returns the message's bytes
-- once all fragments arrived. Fragments may arrive in any order.
local function Reassemble(sender, chatType, header, chunk)
    local now = GetTime()
    PruneBuffers(now)
    local key = sender .. "\0" .. chatType .. "\0" .. header.messageId
    local buffer = buffers[key]
    if not buffer then
        MakeRoom(sender)
        buffer = {sender = sender, created = now, fragments = {}}
        buffers[key] = buffer
    end
    buffer.fragments[header.fragmentIndex] = chunk
    if header.lastFragment then
        buffer.last = header.fragmentIndex
    end
    if not buffer.last then
        return nil
    end
    local parts = {}
    for i = 0, buffer.last do
        if not buffer.fragments[i] then
            return nil
        end
        parts[i + 1] = buffer.fragments[i]
    end
    buffers[key] = nil
    return table.concat(parts)
end

-- Decodes a complete message and passes it to its handler. Messages that
-- don't decode, and types without a handler (including types from a newer
-- kackla), are dropped.
local function Deliver(data, chatType, sender)
    local message = kacklaUper.decode(kacklaMessages.Message, data)
    local handler = message and handlers[message[1]]
    if handler then
        handler(message[2], {sender = sender, chatType = chatType})
    end
end

-- Tells the player once that someone uses a kackla with a newer protocol
local function WarnAboutVersion(sender, version)
    if warnedAboutVersion then
        return
    end
    warnedAboutVersion = true
    print("kackla: " .. tostring(sender) .. " uses a newer kackla (protocol " .. version
          .. "), update kackla to see everything it sends")
end

-- Handles a CHAT_MSG_ADDON event
function comm.onAddonMessage(prefix, text, chatType, sender)
    if prefix ~= comm.PREFIX or type(text) ~= "string" then
        return
    end
    local frame = kacklaCobs.decode(text)
    if not frame or #frame < comm.HEADER_SIZE then
        return
    end
    local version = string.byte(frame, 1)
    if version ~= comm.VERSION then
        if version > comm.VERSION then
            WarnAboutVersion(sender, version)
        end
        return
    end
    local header = kacklaUper.decode(kacklaMessages.FrameHeader, string.sub(frame, 2, comm.HEADER_SIZE))
    if not header then
        return
    end
    local chunk = string.sub(frame, comm.HEADER_SIZE + 1)
    local data
    if header.fragmentIndex == 0 and header.lastFragment then
        data = chunk
    else
        data = Reassemble(tostring(sender), tostring(chatType), header, chunk)
    end
    if data then
        Deliver(data, chatType, sender)
    end
end

--------------------------------------------------------------------------------
-- Sending

-- Returns the frames, COBS encoded, for the encoded message data. Raises an
-- error when it needs more than MAX_FRAGMENTS frames.
function comm.makeFrames(data, messageId)
    local count = math.max(1, math.ceil(#data / comm.maxChunk))
    if count > comm.MAX_FRAGMENTS then
        error("kacklaComm: a message of " .. #data .. " bytes needs more than "
              .. comm.MAX_FRAGMENTS .. " frames", 2)
    end
    local frames = {}
    for i = 0, count - 1 do
        local header = kacklaUper.encode(kacklaMessages.FrameHeader, {
            messageId = messageId,
            fragmentIndex = i,
            lastFragment = i == count - 1,
        })
        local chunk = string.sub(data, i * comm.maxChunk + 1, (i + 1) * comm.maxChunk)
        frames[i + 1] = kacklaCobs.encode(string.char(comm.VERSION) .. header .. chunk)
    end
    return frames
end

-- Returns the number of messages waiting to be sent
function comm.queueLength()
    return #queue
end

-- Returns Enum.SendAddonMessageResult, empty in clients without it
local function Results()
    return Enum and Enum.SendAddonMessageResult or {}
end

-- True when a SendAddonMessage result means it was sent. Older clients
-- return a boolean (or nothing) instead of Enum.SendAddonMessageResult.
local function IsSent(result)
    return result == true or result == nil or result == Results().Success
end

-- True when a SendAddonMessage result means try again later
local function IsThrottled(result)
    return result ~= nil and (result == Results().AddonMessageThrottle or result == Results().ChannelThrottle)
end

-- Adds the frames that can be sent since the last refill
local function Refill()
    local now = GetTime()
    if lastRefill then
        tokens = math.min(comm.BURST, tokens + (now - lastRefill) * comm.RATE)
    end
    lastRefill = now
end

-- Sends as many queued frames as the throttle allows. A message's frames are
-- sent in order without other frames in between. A message whose sending
-- fails for other reasons than the throttle (e.g. not in a group) is dropped.
function comm.process()
    Refill()
    while queue[1] and tokens >= 1 do
        local entry = queue[1]
        if entry.nextFrame == 1 and entry.expires and GetTime() > entry.expires then
            table.remove(queue, 1)
        else
            local result = C_ChatInfo.SendAddonMessage(comm.PREFIX, entry.frames[entry.nextFrame],
                                                       entry.chatType, entry.target)
            if IsThrottled(result) then
                tokens = 0
                break
            elseif IsSent(result) then
                tokens = tokens - 1
                entry.nextFrame = entry.nextFrame + 1
                if entry.nextFrame > #entry.frames then
                    table.remove(queue, 1)
                end
            else
                table.remove(queue, 1)
            end
        end
    end
    if #queue == 0 and ticker then
        ticker:Cancel()
        ticker = nil
    elseif #queue > 0 and not ticker then
        ticker = C_Timer.NewTicker(comm.TICK, comm.process)
    end
end

-- Queues message (a Message value, e.g. {"chatColors", {...}}) to chatType
-- and target (as for SendAddonMessage). options:
--   priority   higher is sent first, default 0. Never overtakes a message
--              that is partly sent.
--   expiresIn  seconds after which the message is dropped if it hasn't
--              started sending, for messages that are useless when late
-- Returns false when chatType can't carry addon messages. Raises an error
-- when message isn't a valid Message.
function comm.send(message, chatType, target, options)
    if UNSUPPORTED_CHAT_TYPES[chatType] then
        return false
    end
    options = options or {}
    local data = kacklaUper.encode(kacklaMessages.Message, message)
    local entry = {
        frames = comm.makeFrames(data, nextMessageId),
        nextFrame = 1,
        chatType = chatType,
        target = target,
        priority = options.priority or 0,
        expires = options.expiresIn and GetTime() + options.expiresIn,
    }
    nextMessageId = (nextMessageId + 1) % 256

    local position = #queue + 1
    for i = #queue, 1, -1 do
        local other = queue[i]
        if other.priority >= entry.priority or other.nextFrame > 1 then
            break
        end
        position = i
    end
    table.insert(queue, position, entry)
    comm.process()
    return true
end

-- Registers the prefix, call once when kackla loads
function comm.init()
    C_ChatInfo.RegisterAddonMessagePrefix(comm.PREFIX)
end

-- Forgets all state, for tests
function comm.reset()
    handlers, buffers, queue = {}, {}, {}
    nextMessageId, tokens, lastRefill = 0, comm.BURST, nil
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    warnedAboutVersion = false
    comm.maxChunk = comm.FRAME_SIZE - comm.HEADER_SIZE
end

return kacklaComm

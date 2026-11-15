# Communication layer design

Status: draft, nothing is implemented yet.

kackla-to-kackla messages sent as hidden addon messages, so kackla can add
things to chat (first of all colors) that players without kackla never see.
Players without kackla see the plain chat message, players with kackla see it
enhanced.

## Goals

- **Invisible degradation**: players without kackla only see the normal chat
  message, never codes or tokens.
- **Never slow down chat**: the chat message is sent immediately, enhancements
  that arrive late are applied afterwards or dropped.
- **Compact**: messages are encoded with ASN.1 uPER, since addon messages are
  small and throttled.
- **Future compatible**: an older kackla ignores what it doesn't understand
  from a newer one, and the protocol can be replaced completely if needed.
- **Robust**: received data is untrusted, malformed or hostile messages are
  dropped without errors.

Not goals: guaranteed delivery, and keeping data secret (anyone in the
channel with an addon listening to our prefix can read it).

## What WoW provides

| Item | Value | Source |
| :-- | :-- | :-- |
| Send | `C_ChatInfo.SendAddonMessage(prefix, message, chatType, target)` | UI source |
| Result | `Enum.SendAddonMessageResult`: `Success`, `AddonMessageThrottle`, `ChannelThrottle`, `AddOnMessageLockdown`, `InvalidChatType`, `NotInGroup`, `NotInGuild`, … | UI source |
| Receive | `CHAT_MSG_ADDON(prefix, text, channel, sender, target, zoneChannelID, localID, name, instanceID)` | UI source |
| Prefix | registered with `C_ChatInfo.RegisterAddonMessagePrefix`, at most 16 characters | wiki |
| Message bytes | 1-255 arrive unchanged, a NUL cuts the message off there (still reported as `Success`) | Forever check |
| Message length | 255 bytes, longer messages are cut to 255 (still reported as `Success`) | Forever check |
| Chat types | PARTY, RAID, GUILD, CHANNEL (target: channel number) and WHISPER (target: full name, "First Last") deliver; RAID in a party arrives as PARTY; SAY and YELL return `InvalidChatType`; INSTANCE_CHAT returns `NotInGroup` outside finder groups | Forever check |
| Throttle | per prefix, a burst of 10, then about 1 message per second | Forever check |
| Send result | `Success` doesn't mean delivered: whispers to an unknown name and OFFICER without officer rights report `Success` too | Forever check |
| Recoloring shown lines | chat frames keep each line's `lineID`, `chatFrame:TransformMessages(predicate, transform)` rewrites shown lines (Blizzard does this in `ItemRefHandlersShared.lua`) | UI source |

## Layers

From the feature down to WoW:

1. **Message**: the feature's data, e.g. the colors of one chat message,
   encoded with uPER.
2. **Framing**: version byte and fragment header, splitting messages longer
   than one addon message.
3. **Byte stuffing**: COBS, removes NUL bytes.
4. **Send queue**: throttling, priorities and dropping stale messages.
5. **Transport**: `SendAddonMessage` and `CHAT_MSG_ADDON`.

Each layer only knows the one below it, so the encoding (layer 1) can be
replaced without touching throttling, and the other way around.

## Byte stuffing: COBS, not base64

Addon messages allow every byte except NUL, so the encoded bytes only need
their NUL bytes removed. A text encoding such as base64 removes far more than
needed and costs much more:

| Encoding | Overhead | uPER bytes per 255-byte message |
| :-- | :-- | :-- |
| base64 | 33 % | 191 |
| base85 (Z85) | 25 % | 204 |
| escape NUL and the escape byte | about 1 % on average, 100 % worst case | 127 worst case |
| [COBS](https://en.wikipedia.org/wiki/Consistent_Overhead_Byte_Stuffing) | 1 byte per 254, plus 1 | **254, always** |

COBS (Consistent Overhead Byte Stuffing) replaces each NUL with the distance
to the next one. Its fixed worst case means every frame can hold 254 bytes,
whatever the data. That makes fragmentation simple. Encoding and decoding are
about 30 lines of Lua each, without bit operations.

A higher base than 64 doesn't help either: the closer a text encoding gets to
the 255 allowed byte values, the closer it gets to plain bytes, which COBS
already is.

## Framing

Each addon message (frame), before COBS:

| Bytes | Content |
| :-- | :-- |
| 1 | protocol version, a plain byte, currently 1 |
| 2 | `FrameHeader`, uPER (13 bits, padded) |
| up to 251 | a fragment of the encoded `Message` (254 bytes per frame minus the 3 above) |

```asn1
FrameHeader ::= SEQUENCE {
    messageId      INTEGER (0..255),  -- per sender, wraps around
    fragmentIndex  INTEGER (0..15),
    lastFragment   BOOLEAN
}
```

- The version byte is outside uPER, so a future version can change everything
  after it, including the ASN.1 module. A receiver drops frames with a version
  it doesn't know. It may tell the player once that a newer kackla is in use.
- Most messages fit in one frame (`fragmentIndex` 0, `lastFragment` TRUE).
  Longer ones are reassembled per sender and `messageId`, with at most 16
  fragments (about 4 KB). Because of the throttle, that takes about 16
  seconds, so features should keep their messages small.
- Incomplete messages are dropped after a timeout (e.g. 30 seconds).

## Messages

The ASN.1 module, to be kept in the repo (e.g. `docs/kackla.asn`) as the
source of truth for the encoder and decoder:

```asn1
Kackla DEFINITIONS AUTOMATIC TAGS ::= BEGIN

Message ::= CHOICE {
    chatColors  ChatColors,
    ...
}

-- Colors for a chat message the sender sent, "from here on" spans
ChatColors ::= SEQUENCE {
    textHash  INTEGER (0..65535),  -- hash of the sent chat text
    spans     SEQUENCE (SIZE (1..32)) OF ColorSpan,
    ...
}

ColorSpan ::= SEQUENCE {
    start  INTEGER (0..255),  -- byte offset in the sent chat text
    color  Color
}

Color ::= CHOICE {
    reset    NULL,                       -- back to the channel's color
    rgb      INTEGER (0..16777215),      -- 0xRRGGBB
    named    NamedColor,
    class    ClassColor,
    quality  ItemQuality,
    ...
}

NamedColor ::= ENUMERATED {
    red, green, blue, yellow, orange, purple, pink, cyan, white, gray, black,
    ...
}

ClassColor ::= ENUMERATED {
    warrior, paladin, hunter, rogue, priest, deathKnight, shaman, mage,
    warlock, monk, druid, demonHunter, evoker,
    ...
}

ItemQuality ::= ENUMERATED {
    poor, common, uncommon, rare, epic, legendary, artifact, heirloom,
    ...
}

END
```

- The receiver turns `named`, `class` and `quality` into colors with its own
  game data (`RAID_CLASS_COLORS`, the item quality colors), so they match the
  receiver's game version. Only the enumeration lists are kackla's own.
- Size estimate: a message with two colored spans is about 7 bytes of uPER,
  11 bytes as a frame.

## Chat colors: matching chat and addon messages

Colors are only used in kackla's active channels (setChannels and
setPlayerChannels), like the alias and emoticons. In an active channel whose
chat type doesn't allow addon messages, the color tokens are removed and the
message is sent without colors.

Sending:

1. The sender types `:#red:`, `:#epic:`, `:#ff8000:` … and `:#:` to reset.
2. The SendChatMessage hook removes the color tokens and builds the
   `ChatColors` spans. Offsets refer to the final text, after the alias
   format and emoticon replacement. A span may not start inside a link
   (`|H…|h…|h`) or a raid icon tag (`{rt1}`).
3. The `ChatColors` addon message is sent first, then the chat message, both
   to the same chat type and channel, without delay.
4. If the addon message can't be sent (chat type not supported, throttled,
   locked down), the chat message is still sent, without colors.

Receiving:

- Addon messages are kept for a short time (e.g. 10 seconds), keyed by
  sender, chat type, channel and `textHash`.
- A chat message filter (`ChatFrameUtil.AddMessageEventFilter`) on the chat
  events looks up a waiting `ChatColors` and inserts the color codes.
- If none is waiting, the filter remembers the line's sender, `textHash` and
  `lineID`. When the `ChatColors` arrives later, the line is recolored with
  `TransformMessages` in each chat frame. Lines that have scrolled away
  are not changed.

The sender of an addon message is given by the server, and only a
`ChatColors` from the same sender matches a chat line. So nobody can color
someone else's messages.

`textHash` has to give the same result in WoW and in the tests on every Lua
version, and plain Lua 5.1 has no bit operations. So it should use plain
arithmetic, e.g. `h = (h * 31 + byte) % 65521` for each byte of the text.
Its 16 bits only have to tell apart one sender's messages in one channel
within a few seconds.

## Send queue

- One queue for the prefix, sending at most what the throttle allows. The
  queue checks the `SendAddonMessageResult` of each send.
- Messages have a priority and an expiry time. Chat colors are real-time:
  if they can't be sent within a couple of seconds they are dropped, since
  late colors are useless.
- Fragments of one message are sent in order, without other messages in
  between.

## uPER encoder and decoder

A file of its own, `uper.lua`, independent of the rest of kackla so it can be
tested on its own. It only implements what the messages above use, and grows
with the messages. It is expected to become a full implementation in time,
so it is built for that from the start:

- **Types are data**: each ASN.1 type is a Lua table describing it, mirroring
  the ASN.1 module, e.g. `{type = "INTEGER", min = 0, max = 255}`. Encoding
  and decoding walk these descriptions, with one encode and one decode
  function per ASN.1 type. Adding a type means adding those two functions,
  adding a message means adding descriptions.
- **Bit writer and reader** at the bottom, with the uPER building blocks on
  top of them: constrained whole numbers, normally small numbers, length
  determinants and open types. Every type encoding is built from those, as in
  X.691.
- **No bit operations**: Lua 5.1 has none, WoW adds a `bit` library that the
  tests don't have. Bits are packed with arithmetic, values stay below 2^53.
- **Clear failure for missing features**: an ASN.1 feature that isn't
  implemented yet (a type, an unconstrained integer, a length over 16K, …)
  fails with an error saying so, never with a wrong encoding.
- **Test vectors**: the tests check exact encoded bytes, ideally made with an
  independent uPER encoder (e.g. asn1tools in Python), so the Lua encoder
  isn't only tested against itself.

Needed now, for the messages above:

| ASN.1 | Used by |
| :-- | :-- |
| INTEGER with lower and upper bound | `FrameHeader`, `ColorSpan.start`, `textHash`, `rgb` |
| BOOLEAN | `FrameHeader.lastFragment` |
| NULL | `Color.reset` |
| ENUMERATED with extension marker | `NamedColor`, `ClassColor`, `ItemQuality` |
| CHOICE with extension marker | `Message`, `Color` |
| SEQUENCE with extension marker | `ChatColors` |
| SEQUENCE OF with SIZE bounds | `ChatColors.spans` |

Extension markers are the one thing that can't wait: the first release has to
decode messages from later versions. Encoding never sets the extension bits
yet, since there are no additions, but decoding has to skip unknown additions:

- unknown CHOICE alternatives: the message is ignored
- unknown ENUMERATED values: treated as unknown, e.g. no color
- unknown SEQUENCE additions: skipped

Skipping needs open types and length determinants, so those are part of the
first version and are tested with hand-made encodings of future messages.

## Robustness

- Decoding runs in `pcall`, a malformed frame is dropped silently.
- All lengths are bounded by the ASN.1 constraints, and the decoder checks
  them before allocating anything.
- Limit the number of waiting addon messages, chat lines and reassembly
  buffers per sender, and drop the oldest when full.
- Decoded data is only ever used as data, never run as code or used as a
  format string.

## Versioning rules

- Within a protocol version, changes are only additions after the `...`
  extension markers: new `Message` alternatives, new `SEQUENCE` fields, new
  `ENUMERATED` values. uPER lets older decoders skip them.
- Never reorder, remove or change the constraints of existing items. When
  that is needed, increase the version byte.
- The tests include encoded test messages from every released version, so
  older messages keep decoding.

## Open questions

Answered by using a temporary slash command`/kackla checkAddonMessages`
(see "What WoW provides"), still open:

- INSTANCE_CHAT in a dungeon or battleground finder group.
- What `AddOnMessageLockdown` covers.

What the answers mean for the design:

- Frames must never be longer than 255 bytes: longer ones are cut off
  silently, so the framing layer checks the length before sending.
- NUL really cuts messages off, so COBS is needed.
- With a burst of 10 and about 1 per second, chat colors (one frame per
  chat message) fit easily, but long multi-frame messages are slow.
- Send results only detect throttling and impossible chat types, never
  delivery.
- Colors can't be used in SAY and YELL.

## Sources

- [C_ChatInfo.SendAddonMessage](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage)
- [AddOn communications protocol](https://warcraft.wiki.gg/wiki/AddOn_communications_protocol)
- [Ace3 commit on the 4.4.0 per-prefix throttle](https://github.com/WoWUIDev/Ace3/commit/1824e8b51a5ba7ae968421707933601ba7c79a28)
- [LibDeflate, encoding for the addon channel](https://safeteewow.github.io/LibDeflate/source/LibDeflate.lua.html)
- [Consistent Overhead Byte Stuffing](https://en.wikipedia.org/wiki/Consistent_Overhead_Byte_Stuffing)
- wow-ui-source (`forever` branch): `ChatInfoDocumentation.lua`,
  `ChatConstantsDocumentation.lua`, `ItemRefHandlersShared.lua`

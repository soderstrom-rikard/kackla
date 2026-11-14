-- Emoticon shortcuts, :name: in a sent message is replaced with the symbol
-- before it is sent, so other players see the symbol without any addon.
-- Like the alias, this is only done in the channels set with setChannels
-- and setPlayerChannels.
--
-- Only symbols that WoW's default fonts show are listed. Tested in game by
-- sending them to a channel and listing them with /kackla emoticons:
-- dingbats (e.g. ✓ ✨ ❤), emoji (e.g. 😀 👍) and ★ ☆ show as boxes. Raid
-- icons don't need shortcuts, the game already turns {star}, {skull},
-- {rt1}-{rt8} etc. into icons.
--
-- Names are lowercase, matched case-insensitive and may only contain
-- letters and digits. Filled shapes get the short name, outlined ones an
-- "open" prefix.

-- {name, symbol} in the order they are shown in the emoticon picker
kacklaEmoticonList = {
    -- misc symbols
    {"smile", "☺"},
    {"darksmile", "☻"},
    {"sun", "☼"},
    {"female", "♀"},
    {"male", "♂"},
    {"spade", "♠"},
    {"club", "♣"},
    {"heart", "♥"},
    {"diamond", "♦"},
    {"note", "♪"},
    {"notes", "♫"},

    -- shapes
    {"square", "■"},
    {"opensquare", "□"},
    {"up", "▲"},
    {"right", "►"},
    {"down", "▼"},
    {"left", "◄"},
    {"circle", "●"},
    {"opencircle", "○"},
    {"lozenge", "◊"},
    {"block", "█"},
    {"shade", "░"},

    -- arrows and math
    {"arrowleft", "←"},
    {"arrowup", "↑"},
    {"arrowright", "→"},
    {"arrowdown", "↓"},
    {"arrowleftright", "↔"},
    {"infinity", "∞"},
    {"approx", "≈"},
    {"ne", "≠"},
    {"le", "≤"},
    {"ge", "≥"},

    -- punctuation
    {"bullet", "•"},
    {"ellipsis", "…"},
    {"dagger", "†"},
    {"ddagger", "‡"},
    {"tm", "™"},
    {"euro", "€"},
    {"permille", "‰"},
    {"lsaquo", "‹"},
    {"rsaquo", "›"},

    -- latin-1
    {"copyright", "©"},
    {"registered", "®"},
    {"degree", "°"},
    {"plusminus", "±"},
    {"middot", "·"},
    {"section", "§"},
    {"laquo", "«"},
    {"raquo", "»"},
    {"times", "×"},
    {"divide", "÷"},
}

-- name -> symbol, used when replacing
kacklaEmoticons = {}
for _, entry in ipairs(kacklaEmoticonList) do
    kacklaEmoticons[entry[1]] = entry[2]
end

-- The game turns these tags into raid icons in received messages, so they
-- need no replacement. The names are English, other game languages have
-- their own, {rt1}-{rt8} work in all.
kacklaRaidIcons = {
    {"{rt1}", "{star}"},
    {"{rt2}", "{circle}"},
    {"{rt3}", "{diamond}"},
    {"{rt4}", "{triangle}"},
    {"{rt5}", "{moon}"},
    {"{rt6}", "{square}"},
    {"{rt7}", "{cross}"},
    {"{rt8}", "{skull}"},
}

-- Texture escape showing raid icon index locally, |T escapes are not sent
-- to other players
function kacklaRaidIconTexture(index)
    return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. index .. ":0|t"
end

-- Replaces :name: with its symbol, unknown names are left as they are.
-- Links (|H...|h[text]|h) are left untouched, their data contains colons.
function kacklaReplaceEmoticons(msg)
    local function replace(text)
        return (string.gsub(text, ":(%w+):", function(name)
            return kacklaEmoticons[string.lower(name)]
        end))
    end

    local parts = {}
    local pos = 1
    while true do
        local s, e = string.find(msg, "|H.-|h.-|h", pos)
        if not s then
            break
        end
        table.insert(parts, replace(string.sub(msg, pos, s - 1)))
        table.insert(parts, string.sub(msg, s, e))
        pos = e + 1
    end
    table.insert(parts, replace(string.sub(msg, pos)))
    return table.concat(parts)
end

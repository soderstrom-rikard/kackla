-- The types of docs/kackla.asn as uper.lua type descriptions. That file is
-- the source of truth, keep this one matching it.

kacklaMessages = {}
local m = kacklaMessages

m.FrameHeader = {
    type = "SEQUENCE",
    fields = {
        {"messageId", {type = "INTEGER", min = 0, max = 255}},
        {"fragmentIndex", {type = "INTEGER", min = 0, max = 15}},
        {"lastFragment", {type = "BOOLEAN"}},
    },
}

m.NamedColor = {
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

m.ClassColor = {
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

m.ItemQuality = {
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

m.Color = {
    type = "CHOICE",
    extensible = true,
    alternatives = {
        {"reset", {type = "NULL"}},
        {"rgb", {type = "INTEGER", min = 0, max = 16777215}},
        {"named", m.NamedColor},
        {"class", m.ClassColor},
        {"quality", m.ItemQuality},
    },
}

m.ColorSpan = {
    type = "SEQUENCE",
    fields = {
        {"start", {type = "INTEGER", min = 0, max = 255}},
        {"color", m.Color},
    },
}

m.ChatColors = {
    type = "SEQUENCE",
    extensible = true,
    fields = {
        {"textHash", {type = "INTEGER", min = 0, max = 65535}},
        {"spans", {type = "SEQUENCE OF", min = 1, max = 32, of = m.ColorSpan}},
    },
}

m.Message = {
    type = "CHOICE",
    extensible = true,
    alternatives = {
        {"chatColors", m.ChatColors},
    },
}

return kacklaMessages

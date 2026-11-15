# Introduction

Kackla is a minimal wow-addon that aims at helping with social interactions.

## Versions

The changes in each version are listed in [ChangeLog.md](ChangeLog.md).

## Installation

From 0.0.6 onwards each GitHub release has a `kackla-VERSION.zip` and a `release.json`, so addon managers
that install from GitHub releases can install and update kackla from the repository URL, for example
[strongbox](https://github.com/ogri-la/strongbox), [WowUp](https://wowup.io),
[CurseBreaker](https://github.com/AcidWeb/CurseBreaker) and [instawow](https://github.com/layday/instawow).

You can also download the zip from the latest release and extract it into your Interface/AddOns
World of Warcraft directory, it contains the `kackla` folder.

Once installed you likely want to run

```
/kackla setAlias YOUR_ALIAS
```

Replacing `YOUR_ALIAS` with whatever alias you are looking for.

If you have a character where you don't want an alias, log into it and run

```
/kackla setPlayerAlias
/kackla setPlayerFormat %s%s
```

## Making a release

```
make dist
```

This runs the tests and creates `dist/kackla-VERSION.zip` and `dist/release.json`, the version and the
interface numbers are read from the .toc files. Create a GitHub release (not a draft or pre-release) and
attach both files as release assets.

## Commands

```txt
/kackla [COMMAND] ([ARGS])
  Without COMMAND opens the settings window
COMMANDS
  emoticons
    Lists the :name: shortcuts that are replaced
    with their symbol in channels where the alias
    is used
  getAlias
    Gets the global alias
  getChannels
    Gets the global channels
  getFormat
    Gets the global format
  getPlayerAlias
    Gets the player alias
  getPlayerChannels
    Gets the player channels
  getPlayerFormat
    Gets the player format
  help [COMMAND]
    Print help, if command is supplied shows help for
    that command
  setAlias ALIAS
    Sets the global alias
  setChannels [CHANNELS]
    Sets the comma-separated global channels
    where the alias is used, e.g. GUILD,SAY,MyChannel
    Without CHANNELS, or with ALL, the alias is used
    in all channels
  setFormat FORMAT
    Sets the global format
  setPlayerAlias ALIAS
    Sets the player alias
  setPlayerChannels [CHANNELS]
    Sets the comma-separated player channels where
    the alias is used, overriding the global channels
    ALL uses the alias in all channels, even when the
    global channels are restricted
    Without CHANNELS the global channels are used
  setPlayerFormat FORMAT
    Sets the player format
```

## Formatting

The `setFormat` and `setPlayerFormat` takes a FORMAT string.
It expects 2 `%s` switches in the format. The first is where your alias
(global or player specific) goes. The second is the actual chat message.

Example
```txt

/kackla setFormat [ %s ]\10%s

```
As you can see you can use \NUMBER to insert a character by its char code.

Here are some common once.

| Character Code    | Character Name        |
| :---------        | :--------             |
|  9                | tab character         |
| 10                | new-line character    |
| 32                | space character       |
| 37                | procent % character   |

## Colors

Color tokens color the text after them, for everyone with kackla. Players
without kackla see the message without the tokens.

```txt
/g loot: :#epic:Thunderfury:#: is mine
/p :#red:pull:#: in 10, :#ff8000:stay out of fire
```

| Token | Color |
| :--------- | :-------- |
| `:#red:` | a basic color: red, green, blue, yellow, orange, purple, pink, cyan, white, gray, black |
| `:#mage:` | a class color: warrior, paladin, hunter, rogue, priest, deathknight, shaman, mage, warlock, monk, druid, demonhunter, evoker |
| `:#epic:` | an item quality color: poor, common, uncommon, rare, epic, legendary, artifact, heirloom |
| `:#ff8000:` | a hex color, also short as `:#f80:` |
| `:#:` | back to the channel's color |

Colors work in guild, officer, party, raid, instance, whisper and custom
channels, not in say, yell or emotes, where the tokens are just removed.

The Colors tab of the ☺ picker (below the chat menu button) inserts the
named colors. Any other color can be picked on the color wheel in the
settings window (`/kackla` or right-click ☺), which inserts its hex token.

## Bumping version

```
sed -i 's/## Version: [0-9.]\+/## Version: 0.0.3/g' kackla*.toc
```

and add a section for the new version at the top of [ChangeLog.md](ChangeLog.md).

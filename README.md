# Introduction

Kackla is a minimal wow-addon that aims at helping with social interactions.

## Versions

| Version       | Description                                       |
| :---------    | :--------                                         |
| 0.0.1         | Adds customizable prompts (similiar to Identity2) |
| 0.0.2         | Added `kackla help` to be able to list commands and usage in game. Also added .editorconfig |
| 0.0.3         | Added kackla.test.lua for simplified testing      |
| 0.0.4         | Simplified setting the format using slash command |
| 0.0.5         | Added `setChannels`, `getChannels`, `setPlayerChannels` and `getPlayerChannels` to limit the alias to chosen chat types (SAY, GUILD, …) and custom channels. `setPlayerChannels ALL` lets a character use the alias in all channels even when the global channels are restricted |
| 0.0.6         | Added `:name:` emoticon shortcuts (e.g. `:heart:` ♥, `:smile:` ☺) that are replaced with their symbol in channels where the alias is used, so other players see them without any addon. List them with `/kackla emoticons`, or pick them and raid icons from the new ☺ button below the chat menu button |

## Installation

Currently the only way to install this is to manually download the repo and place it in a folder called Kackla
in your Interface/Addons World of Warcraft directory.

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

## Commands

```txt
/kackla [COMMAND] ([ARGS])
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

## Bumping version

```
sed -i 's/## Version: [0-9.]\+/## Version: 0.0.3/g' kackla*.toc
```

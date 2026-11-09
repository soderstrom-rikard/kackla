# Introduction

Kackla is a minimal wow-addon that aims at helping with social interactions.

## Versions

| Version       | Description                                       |
| :---------    | :--------                                         |
| 0.0.1         | Adds customizable prompts (similiar to Identity2) |
| 0.0.2         | Added `kackla help` to be able to list commands and
 usage in game. Also added .editorconfig                            |
| 0.0.3         | Added kackla.test.lua for simplified testing      |

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
  getAlias
    Gets the global alias
  getFormat
    Gets the global alias
  getPlayerAlias
    Gets the player alias
  getPlayerFormat
    Gets the player alias
  help [COMMAND]
    Print help, if command is supplied shows help for that command
  setAlias ALIAS
    Sets the global alias
  setFormat FORMAT
    Sets the global format
  setPlayerAlias ALIAS
    Sets the player alias
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

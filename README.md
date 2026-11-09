# Introduction

Kackla is a minimal wow-addon that aims at helping with social interactions.

## Versions

| Version    | Description |
| :--------- | :-------- |
| 0.0.1   | Adds customizable prompts (similiar to Identity2) |
| 0.0.2   | Added `kackla help` to be able to list commands and
 usage in game. Also added .editorconfig|
| 0.0.3   | Added kackla.test.lua for simplified testing |

## Installation

Currently the only way to install this is to manually download the repo and place it in a folder called Kackla
in your Interface/Addons World of Warcraft directory.

## Commands

```txt
/kackla [COMMAND] ([ARGS])
COMMANDS
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
    use \37 for % and \32 for space
  setPlayerAlias ALIAS
    Sets the player alias
  setPlayerFormat FORMAT
    Sets the player format
    use \37 for % and \32 for space
```

## Bumping version

```
sed -i 's/## Version: [0-9.]\+/## Version: 0.0.3/g' kackla*.toc
```

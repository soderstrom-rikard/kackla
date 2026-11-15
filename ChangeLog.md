# Changelog

Newest first.

## 0.0.8

- Added chat colors: `:#red:`, `:#mage:`, `:#epic:`, `:#ff8000:` and more
  color the text after them, `:#:` goes back to the channel's color. Players
  with kackla see the colors, everyone else sees the message without the
  tokens. Works in guild, officer, party, raid, instance, whisper and custom
  channels
- The ☺ button now opens a picker window with an Emoticons and a Colors tab,
  the Colors tab inserts the named, class and item quality colors
- Added a color picker to the settings window, its color wheel inserts any
  color as a hex token
- Added a communication layer for messages between kackla clients (hidden
  addon messages encoded with ASN.1 uPER and COBS), see
  docs/communication-layer.md
- Added a copy window for text from kackla, e.g. test reports

## 0.0.7

- Added a settings window for the alias, format and channels, globally and
  per character, with a preview of how your messages will look
- Open it with a bare `/kackla` or by right-clicking the ☺ button, the help
  is now `/kackla help`
- The settings window refuses formats that would drop your message, such as
  an empty format or a single `%s`
- Releases come with a `release.json`, so addon managers such as strongbox,
  WowUp, CurseBreaker and instawow can install kackla from GitHub
- Split the tests into one file per Lua file, `make test` runs them all

## 0.0.6

- Added `:name:` emoticon shortcuts (e.g. `:heart:` ♥, `:smile:` ☺) that are
  replaced with their symbol in channels where the alias is used, so other
  players see them without any addon
- List them with `/kackla emoticons`
- Pick emoticons and raid icons from the new ☺ button below the chat menu
  button

## 0.0.5

- Added `setChannels`, `getChannels`, `setPlayerChannels` and
  `getPlayerChannels` to limit the alias to chosen chat types (SAY, GUILD, …)
  and custom channels
- `setPlayerChannels ALL` lets a character use the alias in all channels even
  when the global channels are restricted

## 0.0.4

- Simplified setting the format using slash command

## 0.0.3

- Added kackla.test.lua for simplified testing

## 0.0.2

- Added `kackla help` to be able to list commands and usage in game
- Added .editorconfig

## 0.0.1

- Adds customizable prompts (similiar to Identity2)

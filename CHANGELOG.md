# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-10-08

### Added

- Dark control panel with three macros: Hold Click, Auto Clicker and Hold Keys, plus a Stop all hotkey.
- Rebindable hotkeys, including modifier combinations and the middle and side mouse buttons (Mouse 4 / Mouse 5).
- Auto Clicker speed from 0.01 to 1000 clicks per second, with decimals and a plain-language hint (e.g. "1 click per 5 seconds"). Speed changes apply while it's running.
- On-screen keyboard for choosing which keys Hold Keys holds, including mouse buttons.
- 3-second countdown when a macro is started from its button.
- Minimize to the system tray, with tray menu options to show the window, stop all macros or exit.
- Settings saved to `MacroUI.ini`.

### Removed

- `LeftClick.ahk`, the original single-purpose hold-left-click script. Its behavior is now the Hold Click macro.

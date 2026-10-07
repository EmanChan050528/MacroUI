# MacroUI

A small, dark-themed control panel for toggle-style macros on Windows, built with [AutoHotkey v2](https://www.autohotkey.com/). Everything is in one script, so there's nothing else to install.

## Macros

| Macro | Default hotkey | What it does |
|---|---|---|
| **Hold Click** | `Z` | Holds the left, right or middle mouse button down until you toggle it off. |
| **Auto Clicker** | `F6` | Clicks repeatedly at a set speed, from 0.01 to 1000 clicks per second. Decimals work, and a hint under the box spells out the rate (e.g. `0.2` → "1 click per 5 seconds"). |
| **Hold Keys** | `F7` | Holds every key you pick on an on-screen keyboard, all at once. Mouse buttons can be picked too. |
| **Stop all** | `F12` | Releases everything immediately. |

## Getting started

1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Double-click `MacroUI.ahk`.

## Usage

- **Toggle a macro:** press its hotkey, or click **Start** / **Stop**. Starting from the button waits 3 seconds first so you can switch to your game or move the mouse. Click again during the countdown to cancel.
- **Change a hotkey:** click the hotkey box, then press a key or a middle/side mouse button (Mouse 4 / Mouse 5). Hold Ctrl, Alt, Shift or Win to add them. Esc cancels; Backspace or Delete clears the hotkey.
- **Pick keys to hold:** click the box under **Keys to hold** to open the on-screen keyboard. Click keys to select or deselect them.
- **Run in the background:** minimize the window and it moves to the system tray. Hotkeys keep working. Click the tray icon to bring it back; right-click it for **Stop all macros** and **Exit**.
- **Closing the window** exits the app and releases anything still held.

Settings are saved automatically to `MacroUI.ini` next to the script.

## Notes

- Hold Keys sends one key-down per key and doesn't auto-repeat. Games that read key state work fine; a text field will only type the character once.
- Binding a mouse side button as a hotkey blocks its normal action (like browser Back) while MacroUI is running.
- Some games with anti-cheat block simulated input.
- Hotkeys don't fire while you're typing in MacroUI's own speed box.

## License

[MIT](LICENSE)

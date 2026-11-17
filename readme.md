# EVE Operator Overview

_TL;DR: EVE-O Preview but for MacOS_

This application helps keeping an eye on your EVE Online game windows. It shows a set of semi-transparent thumbnails and allows for easy switching to them.

Feedback: **Valeria Bessen** via eve-mail

The application works within the same constraints as EVE-O:

- Does not modify EVE Online interface
- Does not send keyboard/mouse commands
- Does not interact with EVE Online in any way except bringing its windows to foreground

I have no intention of breaking EVE Online EULA/ToS and if you have any concerns about that please notify me.

# How to install

1. Drop `EVE Operator.app` into your Applications folder
2. On launch, application will ask for screen recording and accessibility permissions. Accessibility permission is needed to send EVE Online window to foreground
3. Visit settings window's Permissions tab to validate that everything is working properly.

# Features

1. Previews:

   - Set thumbnail's opacity
   - Set thumbnail's size
   - Arrange thumbnails in multiple rows
   - Keep them on top or not
   - Highlighting active client thumbnail
   - click or ⌘-click to drag

![screenshot](docs/previews.heic)

2. Labels (character name on thumbnail)

   - Set label color
   - Set font size
   - Set position of label

3. Hotkeys

   - The app tracks which characters you use and assigns F-keys to them. Here you can set which modifier keys will be used (e.g. ⌘F1, ⌘⇧F1 and so on). Keep in mind that if your Mac set to use function keys as media keys, you'll need to press <key>fn</key> key as well.

4. Characters

   - You can rearrange characters to set the order of appearance. Characters will keep their shortcut even if they're not online.
   - You can set per-character label color to help identify the preview. You can also automatically use their EVE Online theme settings (i.e. if you have red primary color in EVE the label will be also red). Works only with custom themes at the moment but you can copy the built-in theme.

5. Permissions

   - Use this tab to check that everything is working properly.

6. Other

   - Enable/disable the Menu Bar icon
   - Set path to EVE Online application (the default is`~/Library/Application Support/EVE Online/SharedCache/tq/EVE.app`). EVE Operator uses this to identify windows belongning to EVE Online.
   - Set path to settings folder (or detect it automatically). This path is needed to read theme colors

# Tips

- The application works best if you set all EVE Online clients to "Fixed window" and put them on the same Space. This allows for immediate change between clients without sliding animation and also hides the purple "this window is being recorded" button. "Fullscreen" mode works though.

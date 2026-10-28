<p align="center">
  <img src="assets/brand/app-icon.png" width="128" height="128" alt="Pir app icon">
</p>

<h1 align="center">Pir</h1>

<p align="center">Copy it. Keep it in sight.</p>

<p align="center">
  <a href="https://caldis.github.io/Pir/">Website</a> ·
  <a href="https://github.com/Caldis/Pir/releases/latest">Download</a>
</p>

<p align="center">English · <a href="README.zh-CN.md">简体中文</a></p>

Pir is a native macOS menu bar app that keeps clipboard images, editable text, and file references in always-on-top, borderless windows. Move and resize each pin to keep what you need within reach.

## Features

### Images

- Pin images from your clipboard, including transparent images and Retina screenshots with their logical display size preserved.
- Switch between filling the window with a crop and fitting the whole image. The window keeps its size and position; your display mode is saved and carried over when you pin it again.
- Copy the original image from the floating window.

### Text

- Select, edit, and copy text directly in a pin. Edits are restored when Pir restarts.
- Drag the space at the top to move the window, or hold `Option` while dragging the text. Resize from the edges; narrow windows wrap text and scroll vertically.
- Text and background colors follow the macOS appearance. New pins trim leading and trailing whitespace without changing your clipboard or internal formatting.

### Files

- Copy files or folders in Finder, then pin them as references with native icons or a list view.
- Select by dragging a selection rectangle, toggle items with `Command`, add to a selection with `Shift`, double-click to open, or drag files to Finder.
- Right-click to open, move to Trash, get info, rename, reveal in Finder, or remove from the list. Get Info opens Pir's native file information windows with selectable, copyable fields. Batch renaming numbers files and preserves extensions.

**File actions affect the original files.** Renaming and moving to Trash update references across pins, including files inside affected folders. Only successfully trashed items and their descendant references are removed. **Remove from List** removes only the pin's references and keeps the original files; removing the last item closes the pin.

## Get started

Requires **macOS 13 or later**, on Apple Silicon or Intel Macs.

1. [Download the latest disk image](https://github.com/Caldis/Pir/releases/latest) and drag Pir into Applications.
2. Open Pir and complete the welcome screen. You can record a shortcut and try pinning the Pir logo there.
3. Copy an image, text, or files, then press **`⇧⌘V`** (`Shift` + `Command` + `V`) to pin the content. A saved custom shortcut continues to work.
4. Drag a pin to move it and use its edges to resize. Hover over it to reveal the controls in the upper-left corner.

| Pin | Controls, from left to right |
| --- | --- |
| Image | Close, restore size, display mode, copy |
| Text | Close, restore size, copy |
| Files | Close, restore size |

The copy button briefly shows a checkmark after a successful copy. Global shortcuts and shortcut recording require no Accessibility permission.

## Preferences and recovery

Click the menu bar icon and choose **Preferences**. The four tabs are General, Pins, Updates, and About.

| General setting | What it does |
| --- | --- |
| Launch at login | Starts Pir when you log in to macOS |
| Hide menu bar icon | Hides the icon; open Pir again to access Preferences |
| Shortcut | Records or clears the global shortcut used to pin content |

The **Pins** tab lists all pins and lets you pin them again, show, hide, delete, or clear all after confirmation. Hidden states persist across restarts. Pir restores pin content, sizes, and positions on restart, with placement saved for each display.

After onboarding, regular launches stay quiet. Open Pir again while it is running to show Preferences, including when its menu bar icon is hidden. In **Updates**, you can check manually or enable checks at startup. Updates come from Pir's GitHub Releases through Sparkle.

## Local storage and privacy

Pir reads the clipboard when you trigger it. Pin sessions are stored locally in `~/.config/pir/`; closing a pin removes its saved record. File pins retain file URL references. Closing a file pin or removing a reference does not delete the original file; **Move to Trash** acts on the original file.

## License

Pir uses the [Pir Source License 1.0](LICENSE), a **source-available** license. It permits use, copying, modification, and distribution, including selling copies, subject to its terms. Copies must retain the license and copyright notice; modified distributions must identify their changes and must not present themselves as official Pir releases.

Distributing a covered application through an application marketplace, free or paid, requires separate written permission from Caldis / BIAO CHEN. The license defines covered applications and marketplaces; the copyright holder retains their own distribution rights. This is **not the MIT License or an OSI-approved open source license**. Third-party components keep their own licenses; see [third-party notices](THIRD_PARTY_NOTICES.md).

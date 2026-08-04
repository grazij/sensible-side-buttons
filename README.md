<img src="icon.png" width=150 />

> **This is a fork.** Upstream ships an Intel-only build. This fork produces a universal binary that runs natively on both Apple Silicon and Intel Macs, distributed as a signed and notarized DMG through my Homebrew tap.

## Install

Via Homebrew:

```sh
brew tap grazij/tap
brew install --cask sensible-side-buttons
```

Or download the DMG from [Releases](https://github.com/grazij/sensible-side-buttons/releases), open it, and drag **SensibleSideButtons** to your Applications folder. The DMG is notarized by Apple, so it installs without security warnings.

## About

macOS mostly ignores the M4/M5 mouse buttons, commonly used for navigation. Third-party apps can bind them to ⌘+[ and ⌘+], but this only works in a small number of apps and feels janky. With this tool, your side buttons will simulate 3-finger swipes, allowing you to navigate almost any window with a history. As seen in the Logitech MX Master!

Extensive information on this tweak can be found here: http://sensible-side-buttons.archagon.net

## Launch at login

To ensure SensibleSideButtons opens whenever you start your computer:

**macOS 13 Ventura and later**

1. Open System Settings
1. Click General in the left panel
1. Click Login Items
1. Click the plus button under "Open at Login"
1. Go to wherever you put the app (probably your Applications folder) and double-click it

**macOS 12 Monterey and earlier**

1. Open System Preferences
1. Click Users & Groups
1. Click your username in the left panel
1. Click Login Items at the top
1. Click the plus button at the bottom
1. Go to wherever you put the app (probably your Applications folder) and double-click it

# gesturemouse

Tiny macOS daemon that turns the Logitech MX Master 3S thumb **gesture button**
into a per-direction action launcher, and inverts the mouse scroll wheel
without touching trackpad natural scrolling.

Open source (MIT). Config-file driven. No GUI. Distributed as a Homebrew tap.

## What it does

The thumb gesture button on the MX Master 3S sends a plain mouse button event
on macOS (no native Logitech driver = no gestures). `gesturemouse` watches
that button via a `CGEventTap`, measures cursor movement while it is held, and
fires a keystroke based on direction on release.

Default mapping:

| Action            | Keystroke          | macOS result               |
|-------------------|--------------------|----------------------------|
| Click (no move)   | `ctrl+up`          | Mission Control            |
| Gesture left      | `ctrl+left`        | Previous Space             |
| Gesture right     | `ctrl+right`       | Next Space                 |
| Gesture down      | `ctrl+down`        | App Exposé                 |
| Gesture up        | `cmd+shift+4`      | Screenshot region          |

It also flips the **vertical** scroll direction for discrete (mouse) scroll
events only. Trackpad scrolling is left alone.

## Install

```bash
brew tap supermar1010/gesturemouse https://github.com/supermar1010/gesturemouse
brew install gesturemouse
brew services start gesturemouse
```

On first run `gesturemouse` writes a default config to
`~/.config/gesturemouse/config.json` if none exists.

### Grant Accessibility permission

On first run the binary asks for Accessibility access. Open
**System Settings → Privacy & Security → Accessibility** and toggle the
switch for `gesturemouse`. The daemon polls in the background and picks the
permission up automatically — no need to restart the service.

The binary embeds an `Info.plist` (bundle id
`com.supermar1010.gesturemouse`, `LSUIElement=true`) and is ad-hoc signed,
so System Settings lists it by name instead of by raw path. Because ad-hoc
signatures use a content-hash designated requirement, you'll still need to
re-toggle the switch after a `brew upgrade` that produces a new binary
hash; polling makes that a one-toggle action without a service restart.

### Disable conflicting mappings

If you also run Mac Mouse Fix or Logi Options+, remove their binding for
**Taste 6 / Button 6** so both apps don't fight over the same press.

## Config

`~/.config/gesturemouse/config.json`:

```json
{
  "button": 5,
  "moveThreshold": 25,
  "actions": {
    "click": { "key": "up",    "mods": ["ctrl"] },
    "left":  { "key": "left",  "mods": ["ctrl"] },
    "right": { "key": "right", "mods": ["ctrl"] },
    "up":    { "key": "4",     "mods": ["cmd", "shift"] },
    "down":  { "key": "down",  "mods": ["ctrl"] }
  },
  "scrollInvert": {
    "verticalMouseOnly": true,
    "horizontalMouseOnly": false
  }
}
```

| Field                          | Meaning                                                  |
|--------------------------------|----------------------------------------------------------|
| `button`                       | 0-indexed mouse button. MX Master 3S thumb gesture = `5` |
| `moveThreshold`                | px of movement before a press counts as a gesture       |
| `actions.{click,left,right,up,down}` | Keystroke to fire per direction                   |
| `scrollInvert.verticalMouseOnly`   | Flip mouse vertical scroll; trackpad unaffected      |
| `scrollInvert.horizontalMouseOnly` | Flip mouse tilt-wheel scroll; trackpad unaffected    |

Supported `key` values: `left`, `right`, `up`, `down`, `space`, `return`,
`tab`, `esc`, `delete`, `0`–`9`, `f1`–`f12`.

Supported `mods` values: `cmd`, `shift`, `ctrl`, `alt` (= `opt`).

Restart the service after editing:

```bash
brew services restart gesturemouse
```

## Logs

```bash
tail -f "$(brew --prefix)/var/log/gesturemouse.log"
```

## Build from source

```bash
swiftc gesturemouse.swift -O \
  -framework CoreGraphics -framework Carbon -framework ApplicationServices \
  -o gesturemouse
./gesturemouse
```

Requires Xcode Command Line Tools (`xcode-select --install`).

## License

MIT.

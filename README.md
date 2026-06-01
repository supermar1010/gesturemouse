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

macOS will block the event tap until you allow it. Open
**System Settings → Privacy & Security → Accessibility**, click `+`, and add
the binary at:

```
$(brew --prefix)/bin/gesturemouse
```

(On Apple Silicon that resolves to `/opt/homebrew/bin/gesturemouse`, on Intel
`/usr/local/bin/gesturemouse`.)

Restart the service after granting:

```bash
brew services restart gesturemouse
```

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
    "verticalMouseOnly": true
  }
}
```

| Field                          | Meaning                                                  |
|--------------------------------|----------------------------------------------------------|
| `button`                       | 0-indexed mouse button. MX Master 3S thumb gesture = `5` |
| `moveThreshold`                | px of movement before a press counts as a gesture       |
| `actions.{click,left,right,up,down}` | Keystroke to fire per direction                   |
| `scrollInvert.verticalMouseOnly` | Flip mouse scroll vertical; trackpad unaffected       |

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

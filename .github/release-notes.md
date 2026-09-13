Built by GitHub Actions from the tagged source.

### Fixed
- Swiping partway and dragging back to cancel no longer switches the wrong way or leaves the Dock stuck mid-gesture.
- Rapid Ctrl+arrow presses and key repeat no longer drop switches. Toggling "Animate Switch" mid-animation is safe.
- A cancelled trackpad gesture no longer makes the next swipe ignored.
- A dropped switch no longer blocks the edge until the next real Space change.
- Multiple displays with "Displays have separate Spaces" now use the display that has the active Space.
- App version in Info.plist now matches the release.

### Install
1. Download `SPACE.dmg` and open it
2. Drag `SPACE.app` into `Applications`
3. First launch: right-click SPACE.app and choose Open (the build is not notarized)
4. Grant Accessibility permission when prompted

### FAQ
- My app isn't working! Go into Accessibility settings, remove the permission, restart the app, then grant it again.

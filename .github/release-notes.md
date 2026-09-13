Built by GitHub Actions from the tagged source.

### New
- In-app updates. The menu shows the installed version and a "Check for Updates" item. SPACE checks GitHub once a day; when a newer release exists the item becomes "Install Update", which downloads the DMG, verifies its sha256 against GitHub's digest and its code signature, swaps the app in place, and relaunches.

### Install
1. Download `SPACE.dmg` and open it
2. Drag `SPACE.app` into `Applications`
3. First launch: right-click SPACE.app and choose Open (the build is not notarized)
4. Grant Accessibility permission when prompted

### FAQ
- My app isn't working! Go into Accessibility settings, remove the permission, restart the app, then grant it again.

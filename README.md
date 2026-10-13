# Copie

Copie is a native macOS 15+ menu bar clipboard history app. It saves readable pasteboard representations, including image data, locally. Selecting an item copies it back to the system clipboard; press **⌘V** in the destination app to paste it.

## Build and run

The ready local build is at `dist/Copie.app`. Open it directly to use Copie. Keep it at a stable path; if you want launch at login, move it to Applications before enabling that setting.

Open `Copie.xcodeproj` in Xcode and run the **Copie** scheme, or build from Terminal:

```sh
xcodebuild -project Copie.xcodeproj -scheme Copie -configuration Debug -derivedDataPath /private/tmp/CopieDerived CODE_SIGNING_ALLOWED=NO build
open /private/tmp/CopieDerived/Build/Products/Debug/Copie.app
```

Copie's icon appears in the menu bar. Click it or press **⌘⇧V** to open the history popover beneath it. Click elsewhere or press Escape to close it. Use search, arrow keys, and Return to choose an entry. Open Settings from the gear icon to change either shortcut, adjust the storage limit, delete history, or enable launch at login.

Open About Copie from the info icon in the history popover. Before distributing the app, replace `developerName`, `supportEmail`, and `coffeeURL` in `AboutDetails` in `Copie/Views.swift`. The bug-report and coffee buttons stay disabled until their links are configured.

Saved images show a thumbnail beside their history entry. Copie saves a full-quality backup of each Finder image file when it fits within the history limit. Selecting a backed-up image-file entry copies the image content, even if the original file is moved or deleted. Older entries without a full backup can use their saved thumbnail at lower resolution when the original file is unavailable. Press **⌃⇧⌘S** or click **Capture Area** in the picker to select part of the screen; the result is copied as image content and saved in history. macOS may request Screen Recording access when you first use this action.

Run focused storage and pasteboard checks with `zsh scripts/test-smoke.sh`.

For Mac App Store distribution, see [APP_STORE_RELEASE.md](APP_STORE_RELEASE.md). The `dist` build is for local use and is not a signed Store archive.

History lives in `~/Library/Application Support/Copie`. The default storage limit is 1 GB. Copie also saves full copies of regular Finder files when they fit within that limit. Selecting one copies a file reference to the saved copy, preserving its filename even if the original is moved or deleted. Folders remain references to their original locations and their contents are not backed up. Private or temporary pasteboard formats can only be kept when their data is readable at capture time.

# Mac App Store release plan

Copie is a native macOS menu bar app. The current `dist/Copie.app` is a local, unsigned build. It is not an App Store upload artifact.

## Required before uploading

1. **Choose a permanent bundle identifier.** The project currently uses `com.local.Copie`. Reserve an identifier owned by the developer account, then use the same identifier in Xcode and the App Store Connect app record. Apple associates uploaded builds with the record by bundle ID and version. A different bundle ID will also give the Store build a different sandbox container and separate local preferences/history from today's test build.
2. **Enable App Sandbox and signing for the Store build.** Mac App Store apps require App Sandbox. The project currently has `CODE_SIGNING_ALLOWED = NO` and no entitlements file. Set the Apple Developer team, enable automatic signing, add only the entitlements the app needs, and archive a signed Release build. Keep the local build separate until the sandboxed build is tested.
3. **Exercise every core feature in that sandboxed build.** Check automatic clipboard capture and pasteboard access prompts, menu bar startup, global shortcuts, search, text/rich text/images, copied Finder files and backup restore, storage trimming, Settings, launch at login, and Capture Area. A private-pasteboard probe confirmed that a sandboxed process could read a file URL received through the pasteboard while direct access to the same file was denied. It did not test the complete Copie app or interactive screen capture. If Capture Area fails, replace the `/usr/sbin/screencapture` process path with a ScreenCaptureKit implementation.
4. **Make clipboard capture clear to new users.** Copie reads the general pasteboard while running and saves readable content locally. Explain this on first launch and provide an obvious way to stop capture or quit. Recent macOS versions can ask permission for programmatic pasteboard reads; verify the experience on the current macOS release.
5. **Prepare the listing.** Create the macOS app record, choose a final name and category, write description and review notes, provide screenshots, set price/availability/age rating, and publish a privacy policy URL. `Info.plist` now declares the Productivity category. Add the publisher's real copyright string before upload.
6. **Validate and test before review.** Archive in Xcode, run **Validate App**, upload to App Store Connect, test the processed build with TestFlight, then submit that build for App Review. The first upload should not be treated as the public release.

## Privacy facts to verify in the listing

- Clipboard history, thumbnails, and full image/regular-file backups are stored on the user's Mac in Copie's Application Support directory, subject to the selected history limit.
- The current code has no developer server, analytics SDK, advertising SDK, or network upload of clipboard contents. Under Apple's definition, data stored only on the device is not “collected” for the App Privacy label. Reassess this if the app gains syncing, telemetry, crash reporting, or third-party SDKs.
- Capture Area is user-initiated and uses macOS Screen Recording access. Clearing history is available in Settings. Deleting the app alone does not erase its Application Support data.
- The Store sandbox will use a different container from the current `com.local.Copie` test build. Decide whether existing testers need an explicit history import path.

## Account decisions still needed

- Permanent reverse-DNS bundle ID and Apple Developer team
- Publisher name/copyright and support contact
- Public privacy-policy URL and support URL
- App Store name, subtitle, screenshots, and pricing

## Apple references

- [Preparing your app for distribution](https://developer.apple.com/documentation/Xcode/preparing-your-app-for-distribution)
- [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- [Distributing your app for beta testing and releases](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [Create an App Store Connect app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app)
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)

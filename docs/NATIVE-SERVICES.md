# Native services

`SINNativeServices` is Objective-C and uses only AppKit, Foundation, CoreGraphics, ImageIO and CommonCrypto from the installed macOS SDK. It does not install libraries, programs, fonts or packages.

The bridge shares the original editor's message shapes. The shell supplies each document's path, Save As destination, stable document identity and owner window. Completion handlers return on the main queue. The shell must enforce read-only state and save a new document before separate-image storage or a relative original-image reference.

- Images are normalized to PNG by ImageIO. Separate files are stored in the HTML file's sibling folder with the same stem. SHA-256 content deduplication preserves filenames after a user renames an existing image.
- Original images remain ordinary relative or `file:` references in saved HTML. `sin-asset://original/` display addresses encode the whole absolute path once. Use `localPathForSource:base:error:` when handling these requests to preserve percent signs and Unicode filenames.
- Native clipboard writes HTML and Unicode text. Private document fragments preserve image references within the same document; portable HTML crosses document boundaries. Reads also accept RTF, Markdown files, image files, PNG, TIFF and SVG. Annotation copy keeps editable JSON objects alongside the selected SVG or PNG representation.
- Paste as Text requests only literal Unicode text. Document-image copy publishes PNG and TIFF; annotation PNG/SVG copy also retains editable layer metadata.
- Slice export chooses a folder once, creates a fresh named output directory, validates each PNG with ImageIO and publishes cells sequentially without replacing existing files. An anchored directory descriptor prevents path replacement from redirecting a batch. Progress and cancellation retain completed cells; a failed or stale request does not overwrite another file.
- Templates and the ten most recent colors persist in JSON under the app's data directory.
- Link and YouTube metadata is fetched only on explicit insertion/paste requests. Requests use ephemeral URLSession instances, bounded data sizes and timeouts. No font downloads or telemetry are performed.
- External images open in the user's default macOS viewer; videos open in the default browser.

Screen capture calls the installed `/usr/sbin/screencapture` tool. **Capture** offers region, window or display selection, a 0, 3, 5 or 10 second countdown (3 by default), and optional cursor inclusion for region/display capture. **Region Capture** preserves the original one-click workflow: a fixed three-second countdown, no options dialog, no cursor, and separate PNG storage in the document's image folder regardless of the paste-storage preference. Countdown has a Cancel button and Escape shortcut.

Region selection uses a frozen, undimmed desktop across all displays and a pixel-grid magnifier in the opposite corner of the active display. Drag selects the region; arrow keys move one physical pixel, Shift-arrows move ten, Space starts/finishes keyboard selection, scrolling adjusts magnification, and Escape or right-click cancels. The output is composed at the highest pixel density of the displays it intersects. Each display can also be captured directly through Capture.

Window selection uses Apple's native window picker, which highlights the chosen window. This replaces the Windows monitor/application thumbnail gallery. macOS controls Screen Recording permission, requested only after the user chooses a capture action. The main window is restored after completion or cancellation.

The build signs the app with an existing keychain identity instead of an ad-hoc
code hash, preserving its designated requirement across changed builds. This is
how macOS recognizes previously authorized code. A transition from older ad-hoc
builds may require one fresh approval. The app does not reset the privacy database
or cache permission as an application preference; it checks the current OS grant
before requesting access. `scripts/test-signing.sh` verifies mutual requirement
compatibility after a signed bundle's contents change without requesting capture
permission. Live grant persistence remains an OS-level acceptance check.

Remaining platform differences: Apple's interactive window picker does not include the cursor; use Capture's region mode with Include Cursor to include it. The Windows system mouse-speed adjustment is replaced with per-pixel arrow-key positioning and adjustable magnification, without changing system mouse settings. Live Windows thumbnail tiles are replaced by the native highlighted-window picker and named display choices. Actual OS permission prompts, multi-monitor overlays with mixed DPI, cursor placement and global focus restoration need manual checks on the intended Mac configuration.

Run the local native service checks with:

```sh
clang -fobjc-arc -fmodules -Wno-deprecated-declarations \
  -framework AppKit -framework ImageIO -framework CoreGraphics \
  Sources/SINNativeServices.m Sources/SINSliceExport.m Tests/native-services-tests.m \
  -o /tmp/SinAIPrompt-native-services-tests
/tmp/SinAIPrompt-native-services-tests
```

The 139 checks cover storage/deduplication, literal text paste and PNG/TIFF copy, malformed pixels, encoded original-image references, relative-reference relocation, SVG and asynchronous image reads, template persistence, recent colors, YouTube URL validation, cross-display image composition and one-pixel Retina crops. Clipboard tests snapshot every existing item and format, restore them in a finally block, and verify restoration. The suite does not request screen access or call the network.

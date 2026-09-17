# Sin — AI Prompt for Mac

Objective-C macOS port of [Sincioco/SinAIPrompt](https://github.com/Sincioco/SinAIPrompt).
The native shell uses AppKit and WKWebView; the rich-text editor and layered image
annotation reuse the original application's plain HTML, CSS and JavaScript.

**No Swift, npm, third-party libraries, downloaded tools, database, AI service,
package restoration or network build step.** Build with the Apple developer tools
already installed on your Mac.

## Build and run

```sh
./build.sh
open "build/Sin AI Prompt.app"
```

Or double-click `Build.command` to build and open the application. The app bundle
is self-contained and uses macOS frameworks. You can copy it to Applications.
Local builds use an existing code-signing identity in your Mac's keychain so
macOS can recognize the app after a rebuild. The build automatically uses the
identity when exactly one valid identity is available. If there are several, set
`SIN_CODE_SIGN_IDENTITY` to its name or SHA-1 from
`security find-identity -v -p codesigning`. Keep using the same identity.
Certificates and private keys are never created, imported or stored in this
repository. Builds are not notarized. Building uses `xcrun clang`, `sips`,
`iconutil`, `security` and `codesign` supplied by Apple, with no network signing
step or dependency installer.

For a disposable build without a certificate, `SIN_CODE_SIGN_IDENTITY=- ./build.sh`
explicitly selects ad-hoc signing. Such builds cannot retain privacy permission
reliably when their contents change; the signing regression check rejects them.

Run `./scripts/package.sh` to build `build/SinAIPromptMac.zip` for copying to
another Mac with the same processor architecture. The deployment target is
macOS 13.3 or newer; this build was validated on macOS 26.6.2 with Apple silicon.

For an independent portable profile:

```sh
"build/Sin AI Prompt.app/Contents/MacOS/SinAIPrompt" --data-dir "/Volumes/Data/Sin AI Prompt"
```

## Editing

- New, open, save, Save As, Save All, duplicate, rename, close, recent documents,
  multiple windows, draggable document tabs and a resizable navigation pane.
- Full-width formatting ribbon above the navigation pane: fonts, sizes, foreground/highlight palettes with
  shared recent colors, formatting painter, paragraph styles, headings, lists,
  alignment, links, code blocks and image tools.
- Code blocks retain the original language lexers, full/preview/collapsed modes,
  captions and editable source. Coloring is lexical rather than compiler based.
- Switch between visual editing and native HTML source with **⇧⌘U**. Source has
  line numbers, wrapping, native undo, encoding choices and LF/CRLF selection.
- Find/replace supports HTML source or visual text, match case, whole words,
  regular expressions, wrapping, a result list and Replace All. Regex work runs
  in a disposable worker so an expensive expression cannot lock the editor.
- Markdown paste/conversion and export, standalone HTML export, read-only locks,
  document contents navigation, date/time formats and separators.
- HTML head content and original scripts are preserved when saving. Document
  scripts stay blocked in the editor; trusted editing code is separate.

New documents use the Windows naming format `yyyy-MM-dd HHmm - Prompt N`, using
their creation time in the Mac's local time zone. Save and auto-save add `.html`.
Recovery retains the original draft name, including older `Prompt N` names and
names you choose yourself.

Right-click a document in **Documents** or on its tab for the same commands:
Rename, Duplicate, Pin/Unpin, Lock/Unlock, Delete, Copy Full Path,
Copy for AI Use, Open Containing Folder, Revert to Last Saved, and Close.
Commands apply to the document you clicked. Copy for AI Use saves and locks that
document, then copies the instruction referring to its path. Revert asks before
discarding changes, and Delete moves files to Trash. File-dependent commands are
disabled for unsaved drafts.
Document names use the available sidebar width as you resize it.

## Images and capture

Paste or drop images, choose embedded PNG, separate PNG, or an original-file
reference. Separate images live in the folder named after the HTML document and
use SHA-256 content deduplication, including reuse after image renaming.

Double-click an image, or choose **Editor**, to edit arrows, lines, rectangles,
ellipses, text, image layers, colors, thickness, opacity, cropping and corner
radii. Multi-selection, layer ordering, copy/paste, undo/redo, zoom, editable
metadata and PMT version 1 object templates retain the original data formats.
Original source images survive annotation and reversible crop changes.

**Capture** uses native Mac display/window choices and configurable delay/cursor
options. **Region Capture** starts a cancellable three-second countdown directly,
then provides an undimmed frozen desktop, opposite-corner magnifier and pixel
selection across monitors. Region Capture excludes the cursor and inserts a
separate PNG in the document's image folder, matching the original workflow.
The first capture needs macOS **Screen & System Audio Recording** permission;
allow access in System Settings when you choose to use this feature. The native
window picker replaces Windows' live window-thumbnail gallery.

If you used an earlier ad-hoc build, macOS may require one new approval after
switching to the certificate-signed build. Subsequent builds retain the same
code-signing identity. This fixes rebuild-related permission loss; permission
remains controlled by macOS. See [Apple's explanation of code identity and privacy
permissions](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

Image, text, Markdown and PDF previews stay outside the open document collection.
PDFKit supplies the offline PDF viewer. Finder replaces Explorer; Trash replaces
the Recycle Bin. Image rename updates its parent document references; unsafe
image-folder deletion is rejected while existing images are still referenced.

## Saving and recovery

Settings, sessions and templates are JSON files in
`~/Library/Application Support/Sin AI Prompt` by default. Settings can relocate
application storage to an empty folder while keeping the old profile as backup.
The chosen directory is recorded in `data-location.json` at the default location;
`--data-dir` explicitly selects any profile. Browser cache is disposable and
separate from documents and profile data.

Atomic saves detect external changes and offer copy/reload/overwrite choices.
Save As preserves the original document and its asset folder. Rename moves the
HTML and its matching image folder together, retaining pending unsaved edits.
Recovery snapshots preserve unsaved documents; settings include an optional
folder for autosaving new documents, startup restoration and save-on-close.

## Mac shortcuts

| Action | Shortcut |
| --- | --- |
| New / Open / Save | ⌘N / ⌘O / ⌘S |
| Save As / Save All | ⇧⌘S / ⌥⌘S |
| New window / Close document | ⇧⌘N / ⌘W |
| Visual / HTML source | ⇧⌘U |
| Find / Replace | ⌘F / ⌥⌘F |
| Next / Previous match | ⌘G / ⇧⌘G |
| Navigation pane | ⇧⌘L |
| Next / Previous document | ⇧⌘] / ⇧⌘[ |
| Bold / Italic / Underline | ⌘B / ⌘I / ⌘U |
| Undo / Redo | ⌘Z / ⇧⌘Z |
| Date/time / Separator | ⌘D / ⌘L |
| Zoom in / out / reset | ⌘+ / ⌘− / ⌘0 |
| Settings | ⌘, |

## Validation and implementation

```sh
./test.sh
```

This builds the app, verifies that a changed signed bundle retains its designated
requirement, runs native persistence, service and unused-image scanner
checks, parses the JavaScript with Apple's installed JavaScriptCore, then runs
editor and native shell checks in the real WKWebView using an isolated temporary
profile. The latest integrated run passed 199 checks; the
[parity audit](docs/PARITY.md) records each suite's evidence and remaining manual
cases. Clipboard tests restore the prior pasteboard. No screen-recording
permission is requested by automated tests. Generated results and screenshots
stay in ignored directories.

- [Feature parity and verification](docs/PARITY.md)
- [WebKit compatibility and bridge](docs/WEB-PORT.md)
- [Native services and capture behavior](docs/NATIVE-SERVICES.md)
- [Reference source revision and artwork](docs/SOURCE-ORIGIN.md)

Optional URL metadata, remote document images and YouTube playback need a network
connection. Editing local documents, annotations, persistence, build and tests do
not require third-party services. Online playback depends on the video's embedding
policy; Open In Browser is available. Other macOS versions, live screen capture
permissions and mixed-monitor UI behavior need target-machine acceptance checks.

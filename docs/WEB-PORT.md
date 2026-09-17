# Web editor port

`Resources/Web` reuses SinAIPrompt's own editor, annotation, Markdown, highlighting,
search, formatting, and test modules. No npm, downloaded runtime, or third-party
JavaScript is required. AppKit and the machine's WebKit render these local files.

## Native boundary

The application loads `sin-asset://app/index.html`. Relative document assets use
`sin-asset://document/`; individually approved original images may use a separate
host handled by the native asset handler. The custom scheme belongs only to the
application and does not need a local HTTP server.

`bridge.js` posts JSON objects to
`window.webkit.messageHandlers.sinNative.postMessage({type, ...data, id})`.
For every request with an `id`, native code calls
`window.sinNativeReply({id, result})` or
`window.sinNativeReply({id, error: "message"})`. Events sent through `send` have no
ID and do not require replies. `window.sinNativeMessage(data)` delivers native
events; `onNativeMessage(callback)` registers a listener and returns its removal
function. The original WebView2 bridge remains available as a fallback.

Native requests used by the editor:

| Request | Input | Result |
| --- | --- | --- |
| `editor-fonts` | — | CSS string for locally installed font aliases |
| `editor-copy` | `html`, `text`, optional `internalHtml` | No value |
| `editor-paste` | — | `{html,text,image,markdown,base,preserveImageMarkup}`; fields optional |
| `read-image` | `source` | Image data URL |
| `save-image`, `reuse-image`, `save-image-as` | `data` PNG data URL | Relative image path; reuse may return null |
| `reference-image` | `source`, `absolute`, `base` | `{reference,display}` or null on cancellation |
| `map-original-image` | `source`, `base` | `{source,display}` |
| `relocate-original-image` | `source`, `base` | Updated saved reference |
| `rename-image` | `source` | No value |
| `screen-capture` | — | PNG data URL or null on cancellation |
| `region-capture` | — | `{source,storage:"separate"}` or null on cancellation |
| `open-image` | `data` | No value |
| `open-video` | `video` YouTube ID | No value |
| `link-preview` | `url` | Preview metadata or null |
| `youtube-preview` | `url`, `saveThumbnail` | YouTube metadata or null |
| `annotation-mode` | `open` boolean | No value |
| `annotation-copy` | `format` (`svg`/`png`), `content`, `objects` JSON | No value |
| `annotation-paste` | — | `{objects,image}`; fields optional |
| `templates-load`, `templates-save` | `templates` on save | Array on load; no value on save |
| `export-template` | `contents` JSON string | No value |
| `recent-colors`, `color-used` | `value` on color-used | Array of hex strings on load |
| `drop-paths` | `names` array, `kind` (`documents`/`images`) | Whether the native drag pasteboard was handled |
| `drop-files` | `kind`, `files:[{name,type,data}]` | No value |

`drop-paths` preserves each dropped document's actual folder. If WebKit receives
data without a filesystem URL, `drop-files` transfers data URLs instead. Neither
path depends on Chromium-only `File.path` or additional-object APIs.

Events: `ready`, `painted`, `change` (`html`), `command` (`command`, `html`),
`source`, `image-status` (`source`), `ribbon-height` (`height`), `chrome-overlay`
(`modal`, `rects`), `startup-error` (`message`, optional `source`/`line`).

## JavaScript entry points

The native shell calls `window.editor` after the `ready` event:

| Method | Purpose |
| --- | --- |
| `load(html, base?)`, `ready()` | Load and await the sandboxed document |
| `html(flush?)`, `setBase(base)` | Serialize or change its asset folder, preserving the caret |
| `captureView()`, `restoreView(state)` | Save/restore `{selectionStart,selectionLength,scroll}` using rendered text offsets |
| `focus()`, `command(name,value?)` | Focus and execute editing actions |
| `insertImage(source,storage?)`, `setImageStorage(storage)` | Insert inline, separate, or original-reference images |
| `openAnnotation(image?,source?)`, `pasteCode(existing?)` | Open the full annotation editor or source block dialog |
| `setReadOnly(bool)`, `setToolbarWrap(bool)`, `setNavigationInset(width)` | Apply native UI state |
| `outline.items()`, `outline.jump(index)` | Read and navigate the content outline |
| `search(options)` | Async find/replace with case, whole-word, regex and wrap options |
| `renameImageFolder(html,old,new)`, `renameImageFile(html,documentURL,oldURL,newURL,caseSensitive?)` | Rewrite saved references; native caller supplies the volume's case behavior for image-file renames |
| `renameOpenImageFolder(old,new)`, `renameOpenImageFile(documentURL,oldURL,newURL)` | Rewrite displayed references |
| `beginPortable(duplicate?)`, `beginMarkdown(folder?)`, `beginRelocate()` | Begin asynchronous export, returning a key |
| `exportResult(key)` | Poll for `{html}` or `{error}`; null means pending |
| `stopMedia()` | Close the temporary media player |

The Markdown preview exposes `window.preview.load(html)` and also accepts
`window.sinNativeMessage({html})`.

## macOS changes and safety

Command shortcuts work throughout editing and annotation; Shift-Command-Z
performs redo. Option-Command-F opens Replace; Command-G/Shift-Command-G find
next/previous; Control-Tab and Shift-Command-brackets switch documents.
Option-Command-S saves all. Command-H remains the system Hide shortcut.
UI labels use Mac symbols. UUID generation uses
`crypto.getRandomValues` when the custom scheme lacks `crypto.randomUUID`.
Local reference rewrites recognize both the original Windows document host and
the new native scheme. Image-file rename comparisons preserve case on
case-sensitive volumes and match case variants on case-insensitive volumes.
WebKit-compatible UI fonts are selected from installed system fonts.

Regular expressions still execute in a terminable worker with the original
750 ms limit. The worker uses a Blob built from a local first-party function,
avoiding WebKit's restrictions on worker scripts loaded from custom schemes.

WebKit suppresses parent-owned editor event handlers in the Windows version's
no-scripts sandbox. On Mac, documents and Markdown previews use sandboxed frames
with `allow-same-origin allow-scripts` and a first, application-inserted CSP meta:
`script-src 'none'; object-src 'none'; frame-src 'none'; form-action 'none'`.
Document-authored inline/external/data scripts, event attributes, JavaScript
links, and nested browsing contexts stay blocked, while trusted parent-owned
editor callbacks work. Later document CSP tags cannot relax the first policy.
Meta refresh is disabled during editing and restored in the saved source.
The native bridge must accept messages only from its main frame and map assets
only from explicitly approved document/image locations. Saving strips runtime
styles, base URLs, editing attributes, temporary selections, original-image
display mappings, and media overlays.

WebKit's rich-text insertion normalizes `details`, `summary`, and `figure` in ways
that corrupt structured code and video blocks. The Mac adapter uses temporary
presentation tables to retain exact DOM content and native Undo identity.
Serialization removes those containers, preserving ordinary portable HTML.

## Verification

Run in a real application WKWebView after `window.editor.ready()`:

```javascript
import('./mac-self-test.js').then(module => module.run())
```

The result is an array of passing assertions; failures reject with the failed
assertion. This suite covers the Mac bridge, sandbox, UUIDs, image path rewriting,
the original source-block and document-tools tests, Markdown, regex workers,
annotation rendering/templates, and standalone export. It also exercises all
paragraph presets, color palette, font sizing, ribbon
overflow, read-only/outline/video presentation, reversible and permanent crop,
and annotation Command shortcuts, native object clipboard, templates and Apply.
Template contents are restored after the test; the native test harness preserves
and restores NSPasteboard around clipboard checks.
The original Windows
full suite remains in `self-test.js`; its `test-mouse`, `test-key`, screenshots,
Windows path assertions and native-layout test requests require a separate
native automation adapter and are not evidence of a Mac test pass.

`SinAIPrompt --self-test` uses an isolated temporary profile, runs these checks in
the actual application WKWebView, then runs native shell checks. The native
harness restores every available NSPasteboard item/data type, writes
`Tests/last-web-results.json`, saves `build/self-test.png`, and exits nonzero if a
check fails. Failure reports retain previously passing check names and a stack.
The latest integrated run passed 157 checks: 129 browser/editor checks and 28
native shell checks. This includes source/visual switching, Save with caret and
Undo retention, lazy editor isolation, read-only native commands, source-search
workers, export replacement and asset reuse, untouched HTML preservation,
external-file conflicts and multi-window recovery. The test uses local
video fixtures; it does not exercise online playback or request capture access.
See [the parity audit](PARITY.md) for coverage and remaining manual cases.

# Sin AI Prompt: Windows to macOS parity audit

Reference: `sincioco/sinaiprompt`, revision
`f6a3bc8da83e761bed6882d32d92bfe173cd47cf` (October 17, 2026), including the
17 commits after the original `a137bea` baseline. Feature inventory comes from
the reference README, native source, browser modules, and self-tests. This audit
distinguishes code reuse and implementation from demonstrated behavior. The
Windows application's own passing tests are not evidence that the Mac host passes.

No npm, package manager, third-party application library, downloaded runtime, or
Swift is required. Objective-C hosts Apple AppKit/WebKit/Foundation services and
the application's existing HTML/CSS/JavaScript editor modules.

Evidence labels identify passing checks on this Mac: **Model** is
`Tests/StoreTests.m`; **Services** is `Tests/native-services-tests.m`;
**Scanner** is `Tests/UnusedImageTests.m`; **App integration** is the real
AppKit/WKWebView run in `Resources/Web/mac-self-test.js` and
`Sources/SINNativeSelfTest.m`, `Sources/SINContextMenuSelfTest.m`,
`Sources/SINDocumentWorkflowSelfTest.m` and `Sources/SINProjectSelfTest.m`.
**Recovery**, **Projects** and **Slices** identify the corresponding standalone
`Tests/RecoveryTests.m`, `Tests/ProjectTests.m` and `Tests/SliceExportTests.m` suites.
**UI smoke** identifies an interaction observed in
the running Mac app. **Code inspection** identifies implemented behavior without
a dedicated passing assertion. **Manual** identifies remaining acceptance checks.
A passing check covers its stated case, not every interaction in a row.

| Original feature | Mac implementation / equivalent | Evidence |
| --- | --- | --- |
| New/open/save HTML, timestamped `yyyy-MM-dd HHmm - Prompt N` names, modified marker | AppKit commands and SINDocument/SINStore; creation-time draft names retained in recovery | Model for local creation timestamp, sequential and recovered numbering, legacy/custom draft names, and collision-safe autosave filenames; App integration for Save and source caret/Undo; UI smoke for native Open panel and edit/save/Undo. Manual: remaining save-panel paths |
| Save As preserves original, copies matching image assets, rebases references | Transactional native model copy and local URL rebase | Model for file/asset copy, rebase, confirmed replacement, compatible asset merging and preserved unknown files. Manual: Save As panel interactions |
| HTML head and script source retained; editor does not execute document scripts | Existing serialization plus WebKit sandbox and first CSP policy | App integration for source roundtrip, scripts/events/JavaScript links/nested frames blocked, refresh disabled, later CSP unable to loosen policy |
| Source / visual editor switching | NSTextView and WKWebView | App integration for source edits, Save caret/Undo, and return to visual; UI smoke for fresh-document switching retaining its unmodified state |
| Rich text fonts, sizes, text colors, highlighting, bold/italic/underline/strike | Existing browser ribbon and contenteditable editor | App integration for font service, sizes, palette, highlighting and selection retention. Manual: font/emphasis combinations and formatting painter |
| Headings, styles, alignment, lists, nested numbering, links | Existing document styles and editor modules | App integration for styles, continue/restart/custom numbering, Undo, nested Markdown lists and link unlinking. Manual: alignment and complex list gestures |
| Full-width ribbon above navigation | Full-width WKWebView, inset document and measured native navigation layout | App integration for divider/window resizing, source switching, zoom, popover overlap and modal input; UI smoke for the full-width ribbon |
| Modern paragraph styles; split color buttons; recent shared colors | Bundled editor with native profile persistence | App integration for all five styles, 70-color palette and ribbon overflow; Services for recent-color cap/deduplication. Manual: shared history across picker UI |
| Paste Code: eight languages, full/preview/collapsed modes, lexical coloring | Original modules with WebKit structured-block insertion adapter | App integration for all eight lexers, exact source, captions, disclosure, modes, insertion/edit/save/Markdown and native Undo/Redo |
| URL cards, YouTube inline playback/fullscreen/browser link, optional local thumbnail | Browser cards plus native URL metadata / image services | App integration for card/inline/embed conversion, insertion, metadata preservation and Undo/Redo; Services for YouTube URL parsing. Manual: online metadata, playback, fullscreen and saved thumbnail |
| Find/replace in HTML and visual text; regex, case/whole word/wrap, counts, result list, next/previous/replace/all | Native floating panel and upstream matcher in a 750 ms disposable worker | App integration for source selection, visual matching/navigation/replacement, formatting preservation, 2,600 results and invalid/pathological regex; UI smoke for Find reporting 1 of 2 matches. Manual: every panel option combination |
| Clipboard image: inline Base64, separate PNG, original file reference | NSPasteboard and native image storage services | Services for PNG/SVG, Unicode HTML, text, Markdown file clipboard and image services. Manual: TIFF/RTF/image-file paste UI and storage choices |
| Default image storage preference, including per-paste choice | Profile preference passed into original image insertion module | Code inspection. Manual: preference and per-paste choice UI |
| Separate PNG content hash reuse and matching document folder | CommonCrypto SHA-256 and Apple image conversion | Services for saved PNG, escaped folder, deduplication after rename and malformed-image rejection |
| Original reference relative/absolute, Save As reference rebasing | NSURL file paths and native model relative paths | Model and Services for rebase, original URL resolution, base href, Unicode and literal percent paths. Manual: image picker UI |
| Cross-drive references | macOS paths share one filesystem namespace; absolute file URLs remain available | Services for absolute references. Manual: separately mounted volume |
| Same-document image clipboard storage preservation | Existing image/clipboard metadata with NSPasteboard bridge | Services for internal reference retention and portable HTML across document identities |
| Region capture with countdown, cross-monitor selection, magnifier, no cursor | Native macOS capture and selection overlay | Services for synthetic mixed-density monitor composition, one-pixel selection and cancellation. Manual: permissions, real monitors, countdown and magnifier |
| Capture permission across rebuilds | Existing certificate-backed signing identity and stable bundle ID | Signing regression verifies that changed bundle hashes retain the same designated requirement and satisfy each other's identity checks. Manual: OS grant after migration from ad-hoc signing and capture across later rebuilds |
| Image resize, fullscreen, external viewer, annotation entry points | Browser image UI + NSWorkspace preview/open | App integration opens annotation editor. Manual: resize, fullscreen, external viewer and mouse entry points |
| Layered annotation: shapes, text, move/resize/endpoints, Shift geometry | Existing annotation canvas modules | App integration for rectangle layers, duplication, inspector geometry and editable templates; UI smoke for drawing a rectangle with a pointer drag. Manual: other shapes, manipulation and Shift geometry |
| Annotation stroke/fill/opacity/arrow size, layer visibility/order/multi-select | Existing annotation model and controls | App integration for four palettes and inspector controls. Manual: all effects, layer ordering/visibility and multi-selection gestures |
| Editable layer clipboard; PNG/SVG output to other apps | Existing serialization plus NSPasteboard bridge | Services and App integration for public PNG/SVG plus editable object metadata, copy/paste and restored pasteboard contents |
| Reversible crop/corner radii, original pixels retained | Existing annotation crop and metadata modules | App integration for crop/radii geometry, reset bounds and baked pixels clearing crop metadata |
| Expanding canvas, fit and 5–400% zoom, undo/redo | Existing annotation pan/zoom/history modules | App integration for transparent content bounds, solid canvas dimensions and keyboard/menu Undo/Redo. Manual: pan/zoom/fit gestures and full range |
| Annotation Apply retains document width and metadata | Existing PNG render and data-sin-annotation metadata | App integration for Apply returning editable layers and PNG; UI smoke for inline Apply/save and reopening the editable rectangle through the Image menu. Manual: existing image-width preservation |
| Object templates, import/export .pmt-template.json, unsupported types rejected | Existing template schema + templates.json native persistence | Model, Services and App integration for persistence, editable geometry, save and reuse. Manual: import/export panels and unsupported files |
| Standalone HTML embeds local images and CSS backgrounds, explicit missing-asset error | Existing portable export invoked by native save panel | App integration for image embedding, replacement, unchanged original and removal of runtime/private URLs; Services for missing-image errors. Manual: CSS-background export, save panel and missing-asset export UI |
| Markdown paste/export and separate exported assets | Existing Markdown conversion + native asset output | App integration for headings, emphasis, nested lists, links, tables, code, blank lines and source roundtrip. App integration also verifies actual matching-folder PNG output, reuse without duplicates, replacement and concurrent destination conflicts. Manual: export panel |
| Rename HTML and matching asset folder; unsaved edits stay unsaved | Native model transaction, occupied folder rejection, rollback path | Model for rename/rebase/collision, case-only names and unsaved edits. Manual: rollback fault injection |
| Rename image updates saved and unsaved parent HTML, extension retained | Native explorer operation plus JS reference transformation | App integration for encoded/native URLs and case-sensitive/insensitive reference rewrites. Manual: full explorer file transaction |
| Read-only / document lock | POSIX write permissions + editor access preference | Model for lock/save rejection; App integration for visual/source edit guards, native insertion guard and retained outline access |
| UTF-8, BOM, UTF-16 LE/BE, UTF-32 LE/BE, ANSI | Foundation strict text conversion; ANSI = Windows-1252, plus Mac Roman / Latin-1 | Model for encodings and loss rejection; automatic detection limit below |
| Newline selection and preserving untouched mixed line endings | Native normalized buffer and original-byte preservation | Model for CRLF and unchanged mixed-ending bytes |
| External file conflict checks | SHA-256 fingerprint and explicit copy/reload/overwrite choice | Model for rejected/explicit overwrite; App integration for conflicting writes from two windows. Manual: choice-panel paths |
| Autosave with optional separate document directory | Native autosave model and host timer | Model for reservation/collision. Manual: timer-driven save |
| Session recovery includes unsaved text, selection/zoom, active document | JSON session and .bak recovery | Model for text, active ID and corruption fallback; App integration for visual selection, multi-window groups and reopened ownership. Manual: zoom/scroll recovery UI |
| Application storage relocation; old files retained as backup | Profile directory copy with occupied destination rejection | Model for relocation, retained backup and occupied destination |
| --data-dir selects existing profile | Native app launch argument handling | Code inspection. Manual: launch with an existing portable profile |
| Browser cache separated from persistent profile | WKWebsiteDataStore.nonPersistentDataStore | Code inspection of explicit nonpersistent WebKit configuration |
| Native titlebar, tabs, resizable document list, ordering/pinning/recent files | AppKit window, native navigator, profile recent list; filename labels follow the available row width | App integration for lazy document switching, buffer isolation and label resizing. UI smoke for a timestamped filename displayed in full at the existing sidebar width. Manual: drag order and recent-file UI |
| Document and tab right-click commands | Shared native commands with Emoji, Private, Combine, project destinations and selection-aware deletion alongside Rename, Duplicate, Pin/Lock, path/AI copy, folder, Revert and Close | Context-menu integration checks cover labels/order, draft/saved/missing/locked/pinned states, inactive-document targeting, duplication, lock/AI copy, confirmed/cancelled Revert and Close. Manual: system emoji picker and project-folder chooser |
| Prompt Explorer supported file filter, icons, folders, lazy children, filesystem refresh | NSOutlineView/NSWorkspace and native filesystem enumeration | Code inspection. Manual: filters, links and refresh UI |
| Image/text/Markdown/PDF previews outside document collection | Native preview host; PDFKit replaces Windows WebView2 PDF viewer | App integration for preview collection isolation and retained active HTML. Manual: each preview format and return UI |
| Unused-image colors and safe image-folder deletion based on current HTML | Native explorer reference scan and file action checks | Scanner for unsaved/cross-document references, CSS/srcset/base URLs, entity/percent paths, matching folders, case identity and fail-closed errors. Manual: explorer colors and Trash interaction |
| Delete to Recycle Bin, reveal file, open containing folder | NSWorkspace recycle, Finder reveal, Finder open | Code inspection. Manual: cancellation, file errors and Finder/Trash UI |
| Startup creates only active editor; remaining editors lazy | Native editor dictionary created on activation | App integration for lazy creation and buffer isolation. Manual: 100-document startup performance |
| Common Windows Ctrl shortcuts and F keys | Mac Command shortcuts; F5 where native convention permits | App integration for annotation shortcuts, modal menu Undo/Redo routing and Mac labels. Manual: remaining menu equivalents |
| Date/time choices and separators | NSDateFormatter/native menu commands | Code inspection. Manual: complete format-menu parity |
| Offline build and application bundle | Installed Apple clang/SDK, shell build script, bundled app resources | Built and ran on this Mac without package downloads |

## October synchronization

These additions close the feature gaps identified against the newer Windows
revision. Native Mac menus and system pickers follow macOS conventions; the
editor and annotation controls reuse the corresponding upstream modules.

| Updated Windows behavior | Mac implementation / equivalent | Evidence |
| --- | --- | --- |
| Two pinned AI reference documents and Help commands for fresh copies | Bundled offline HTML; missing-file recovery and numbered fresh copies preserve existing files and pending edits | App integration |
| Document emoji, removal and twenty recent choices | Native Emoji & Symbols picker and JSON metadata shown in tabs, Documents and Explorer | App integration for metadata and closed-file combine labels. Manual: system picker interaction |
| Filename filter and ordered multi-file selection | Debounced native search field, separate ordered checkbox selections for Documents and Explorer | App integration for filtering and order. Manual: repeated pointer selection gestures |
| Combine selected documents, preserve assets and mark processed sources | Detached HTML merge with rebased local references; existing emoji retained, otherwise ❌ | App integration for source order, source preservation, other-window pending text, closed-file emoji and HTML safety |
| Private documents and Show Private Documents | Per-document metadata hides tabs/list, companion folders and recent-file entries while retaining recovery | App integration. Visibility control is not encryption |
| Delete selected files and unsaved drafts | One confirmation, native Trash, all open instances removed only after successful deletion | App integration for cancel/confirm, saved files and drafts; existing companion image files are preserved |
| Physical projects, create/move menu, project suffixes | `Project - Name` folders, transactional batch moves with companion assets and saved/unsaved reference rewriting | Projects and App integration for batches, cross-window pending edits, lazy editors, locks, external changes, conflicts and rollback |
| Title paragraph supplies first-save filename | Retains creation timestamp, sanitizes title, reserves a nonconflicting HTML filename | App integration for actual title-based save and rename/emoji continuity |
| Markdown opens as an editable converted HTML document | Numbered copies under the profile's Markdown Imports directory with rebased asset URLs | App integration for repeated imports and unchanged source |
| Persistent annotation tools and object locks | Upstream toolbar/model, locked-layer menu/inspector, deletion and movement guards | App integration for repeated drawing, lock operations, templates, clipboard and stale-crop prevention |
| Direct PNG/SVG object copy and document-image copy | Public NSPasteboard image representations plus editable annotation object metadata; click, right-click or Control-click a document image and choose Copy Image | Services and App integration for image-menu targeting, read-only copying, original dimensions and exact pixels; text context menus remain native |
| Image rows/columns, cell copy, Save All Slices, separate editable image layers | Canvas cell geometry and native exclusive PNG export with progress/cancel and completed-file retention | Slices and App integration for exact pixels, geometry, locks, copy, progress, cancellation and failure; Manual: destination picker |
| Paste as Text, full Clear Formatting, styled date insertion | Plain-text native bridge, reversible whole-document clearing and H2 date followed by Normal paragraph | Services and App integration for newlines, literal Markdown/URLs, Undo/Redo, preserved source structures and date style |
| Spellcheck visibility, heading and list improvements | Persisted spelling preference and upstream formatting/list modules | App integration |
| Background recovery and idle editor synchronization | Serial coalescing JSON writer, atomic publication, 600 ms edit-idle synchronization and lightweight view-state capture | Recovery for ordering, retry, direct-write invalidation, large snapshots, backups and partial failures; App integration for editor state |
| Contents pane alongside navigation, nested image folders and unused-image colors | Separate native outline, HTML companion-folder children and semantic reference scanner | App integration for simultaneous pane layout; Scanner for reference safety. Manual: large-folder responsiveness |
| Image path status, LF/CRLF/CR, default HTML app selection | Native status callback, explicit line-ending menu and Settings action using Apple's default-application API | Code inspection; existing model encoding checks. Manual: default-association change and system authorization |

Run all local checks with the installed compiler and Apple frameworks:

```sh
./test.sh
```

The October synchronization and image-menu update passed 107 persistence assertions, 58 background
recovery assertions, 71 physical-project assertions, 139 native service checks,
25 slice-export assertions, 62 unused-image scanner checks, and syntax parsing of
59 JavaScript modules. The signing regression also passed.
The integrated app run passed 356 checks (235 browser/editor checks and 121 native
shell, document-workflow and project checks); its result is recorded in
`Tests/last-web-results.json` with a
snapshot at `build/self-test.png`. Counts include fixture and request assertions;
they are not counts of distinct features. **Manual** cases above remain outside
the demonstrated automated coverage. Live capture and online playback are not
invoked by these tests.

An additional temporary HFSX volume run passed 85 project assertions, exercising
real cross-volume publication and case-sensitive asset-name mappings. The volume
was detached and removed afterward. Initial editor flush and overlapping reload
regressions verify that native load completion publishes the baseline before
reading HTML, preserving untouched bytes and independent pending edits.

Automatic legacy-encoding detection uses UTF BOMs, then UTF-8, then Windows-1252;
BOM-less Mac Roman cannot be unambiguously detected from bytes alone.

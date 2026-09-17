# Sin AI Prompt for Mac

Native Objective-C macOS port of Sincioco/SinAIPrompt. Keep feature parity with the
pinned upstream revision recorded in docs/SOURCE-ORIGIN.md.

## Implementation

- Objective-C, AppKit, Foundation, WebKit, PDFKit, ImageIO, CoreGraphics and other
  installed Apple frameworks only. No Swift, npm, third-party libraries, package
  managers, downloaded tools, external runtimes or build-time network access.
- Reuse the project's plain HTML/CSS/JavaScript modules. No framework or bundler.
- Keep it simple: cohesive native owners and small, direct APIs.
- Never execute user document scripts inside the editor. Keep the document iframe
  sandboxed and enforce the first runtime CSP that blocks all document scripts,
  inline event attributes, frames and objects. Restrict native bridge messages to
  the bundled app main frame. WebKit may use allow-scripts only together with that
  CSP so trusted host event listeners work; security regression tests are required.
- Preserve document data, unsaved edits, original image files, and JSON recovery.
  Atomic writes must detect external changes. Destructive file actions use Trash.

## Verification

- Run ./build.sh and ./test.sh using the installed Apple toolchain.
- Run relevant real WKWebView tests for editing changes; syntax checks alone are
  not proof of browser compatibility. Keep tests isolated from user profiles.
- Run git diff --check. Exclude app binaries, generated tests, user profiles,
  credentials, user HTML documents and image captures from commits.
- Report what actually passed and any remaining platform differences.

## Commits

Use the same Codex commit convention as PMT:

- Every Codex-created commit subject starts exactly with `Sin and Codex: `.
- For nontrivial work, describe Summary, Changes, Validation, and Known limitations
  in the body. State tests actually performed; never claim unverified parity.
- Commit coherent, validated work. Preserve unrelated edits; never rewrite pushed
  history. Commit and push completed work when requested by the user.

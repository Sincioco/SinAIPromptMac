# Source provenance

The reference application is [Sincioco/SinAIPrompt](https://github.com/Sincioco/SinAIPrompt),
inspected at revision `a137beaec59d4e6ac7141d63c572742d1b1d0e48`.

`Resources/Web/` begins with that application's own plain HTML, CSS, JavaScript,
and browser regression tests. Mac changes adapt its native bridge, local asset
scheme, keyboard conventions, and browser editing behavior to WKWebView. These
are first-party application sources, not an installed third-party library.
`Resources/AppIcon.png` is the original Sin AI Prompt artwork from the same source.
The macOS shell, persistence, clipboard, capture, search and build scripts are
Objective-C / Apple framework implementations in this repository.

The editor source itself identifies Sin Notepad and PMT as its behavior origins;
see the upstream README for those original references. No new license terms have
been assigned to the original source or artwork.

Codex commits follow the user's PMT convention: subjects start with
`Sin and Codex: `, followed by a concrete description of the changes and actual
validation in the commit body.

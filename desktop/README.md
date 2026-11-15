# Windows desktop · 2.4 preview

The existing `Sources/` macOS application is unchanged. This directory contains an Electron desktop port for Windows 10/11 x64, using the same companion artwork and local Markdown/KaTeX libraries.

## For users

Download the Windows installer (`.exe`) or portable archive (`.zip`) from the repository's Windows preview release. Unzip the entire portable archive before running `PaperCompanion.exe`. No Node.js or Python installation is needed.

Import a PDF, choose your familiarity, and configure an OpenAI-compatible model in Settings. Translation is manual; importing a paper makes no model requests. Any target-language name can be entered. Enable page images only for a model that supports image input. DeepSeek's default text model leaves this option off.

The Windows distribution includes Tectonic 0.15.0 and a Noto CJK font. First PDF compilation downloads TeX packages over the internet; subsequent runs reuse Tectonic's cache. It may take several minutes. Reading/chat works without a TeX download. Keep the original PDF when verifying formulas; translation and layout reconstruction are not exact reproductions.

Windows API keys are encrypted using Electron safeStorage (Windows DPAPI). Settings and paper histories live under `%APPDATA%/paper-companion-desktop/` (the runtime's Electron userData directory). A key encrypted for one Windows account cannot be copied to another account; enter it again there. Text and optional page images are sent only to the configured model endpoint. Chat rendering has no CDN dependencies.

This Windows preview supports PDF text selection, continuous reading, three familiarity levels, multi-language translation, LaTeX PDF/TeX export, right-hand AI chat, persisted conversation summaries, learning reports, persistent highlight notes, and region capture with OCR.

Region capture ("框选") rasterizes the selected part of the page and, when page images are enabled, asks the configured **vision model** to transcribe it; the crop is also attached to the next question. It is not an offline OCR engine: enable "发送论文页面图片" and use a vision-capable model. Without vision, the crop is kept but no text is extracted.

Highlights are stored with the paper, drawn over the page, and can carry a note; the right sidebar has a "笔记" tab to review and edit them.

Tables: the translation prompt now requires Markdown pipe tables (outer pipes and a `| --- |` separator), and a page whose translated table still looks like space-aligned rows is sent through one extra "reshape into a Markdown table" pass before typesetting. The translation cache key was bumped, so existing papers translate again instead of reusing flattened tables. For table-heavy pages, enable page images and use a vision-capable model; without an image the model only sees flattened PDF text.

Windows still does not implement independent per-provider keys or automatic cross-platform data migration. Scan-only PDFs require an image-capable model for translation. Mixed-column figures and exact source page alignment are not reconstructed. Language entry is unrestricted, but rare scripts can require additional fonts/typesetting support.

The package is unsigned by default: SmartScreen may show an unknown publisher. The 2.4.1 preview was demoed on real Windows 10/11 hardware by an early tester (2026-11-15); CI additionally runs unit, Electron UI, LaTeX, packaging and packaged-app checks on windows-2022.

### Code signing

A trusted signature needs a Windows code-signing certificate; there is no way to remove the SmartScreen warning without one. Once you have an OV/EV certificate (`.pfx`) or Azure Trusted Signing, add repository secrets:

- `WINDOWS_CSC_LINK` — base64 of the `.pfx` (or a URL electron-builder can read)
- `WINDOWS_CSC_KEY_PASSWORD` — its password

The Windows workflow passes them to electron-builder, which signs the `.exe` and the installer automatically. Until then, testers should verify `SHA256SUMS.txt` from the release and use "More info → Run anyway".

## Development

Node.js 22+ and npm:

```sh
cd desktop
npm ci
npm test
npm start
```

On Windows, fetch the pinned engine and font before integration tests or packaging:

```sh
npm run fetch:tex
npm run test:e2e
npm run build:win
```

On macOS, the same integration test can use an installed `/Library/TeX/texbin/xelatex`; macOS production builds continue to use `../build.sh` and the Swift app.

The test opens an actual Electron window, uses an ephemeral local mock SSE model server, and creates isolated data under a temporary directory. It does not access real API keys or send papers to an external AI service. `PC_E2E`, `PC_TEST_HOME` and `PC_TEST_PDF` are ignored by packaged applications.

Windows CI runs unit tests, actual UI tests, TeX compilation and export, then builds an NSIS installer and ZIP and verifies the packaged welcome artwork and settings UI. Screenshots, Playwright traces on failure, and reports are uploaded as Actions artifacts. A `v*-windows*` tag publishes a prerelease only after the Windows job succeeds.

## Dependencies and licenses

- Electron (MIT), PDF.js (Apache-2.0), electron-builder (MIT), Playwright (Apache-2.0). Versions are pinned in `package-lock.json`; build tools are not shipped as application runtime code.
- Shared Marked, DOMPurify, KaTeX and highlight.js: see `../Resources/Chat/THIRD_PARTY.md` and bundled vendor license files.
- Tectonic 0.15.0: downloaded from its official release, archive SHA-256 checked; upstream license included in `resources/tex/TECTONIC-LICENSE.txt`.
- Noto Sans CJK SC, Sans2.004: font SHA-256 checked; SIL Open Font License included in `resources/tex/NOTO-LICENSE.txt`.
- Artwork remains the existing project's companion assets, unchanged.

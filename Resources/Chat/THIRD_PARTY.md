# Bundled chat renderer dependencies

All scripts, styles, and fonts load locally, without a CDN or runtime network requests.

- marked 12.0.2: `vendor/marked/marked.umd.js`, MIT, `vendor/marked/LICENSE.md`.
- DOMPurify 3.2.7: `vendor/dompurify/purify.min.js`, Apache-2.0 OR MPL-2.0, `vendor/dompurify/LICENSE`.
- KaTeX 0.16.22: `vendor/katex`, MIT (font notices included), `vendor/katex/LICENSE`.
- @highlightjs/cdn-assets 11.11.1: `vendor/cdn-assets`, BSD-3-Clause, `vendor/cdn-assets/LICENSE`.

Downloaded from their versioned npm registry packages. Model HTML is sanitized before insertion; KaTeX uses trust:false. External web links open only after a click, in the system browser.

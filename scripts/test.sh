#!/bin/sh
# Headless checks. XeLaTeX reading tests run only when xelatex is installed.
set -e
cd "$(dirname "$0")/.."

OUT="${TMPDIR:-/tmp}/pc-tests-$$"
mkdir -p "$OUT"
trap 'rm -rf "$OUT"' EXIT

SWIFT="swiftc -target arm64-apple-macos13.0"

echo "▸ conversation memory and answer length"
$SWIFT \
  Sources/Models.swift Sources/ConversationMemory.swift Sources/ChatEngine.swift \
  tests/ConversationMemoryTests.swift -o "$OUT/memory"
"$OUT/memory"

echo "▸ shelf"
$SWIFT -framework AppKit \
  Sources/Models.swift Sources/ConversationMemory.swift Sources/Store.swift Sources/Shelf.swift \
  tests/ShelfTests.swift -o "$OUT/shelf"
"$OUT/shelf"

echo "▸ translation layout policy"
$SWIFT -framework AppKit -framework PDFKit \
  Sources/Models.swift Sources/ConversationMemory.swift Sources/PaperLayout.swift Sources/TranslationTeX.swift \
  tests/LayoutPolicyTests.swift -o "$OUT/layout"
"$OUT/layout"

XELATEX=""
for candidate in /Library/TeX/texbin/xelatex /opt/homebrew/bin/xelatex /usr/local/bin/xelatex; do
  if [ -x "$candidate" ]; then XELATEX="$candidate"; break; fi
done
if [ -n "$XELATEX" ]; then
  echo "▸ reading pdf ($XELATEX)"
  $SWIFT -framework AppKit -framework PDFKit \
    Sources/Models.swift Sources/ConversationMemory.swift Sources/PaperLayout.swift \
    Sources/TranslationTeX.swift Sources/LearningReport.swift Sources/Theme.swift \
    Sources/ReadingNavigator.swift tests/ReadingPDFTests.swift -o "$OUT/reading"
  "$OUT/reading"
else
  echo "▸ reading pdf skipped: xelatex is not installed"
fi

echo "✓ tests passed"

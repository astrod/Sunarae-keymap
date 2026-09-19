#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/web-probe build/InputProbe.app/Contents/Resources
cp Tests/WebProbe/package.json Tests/WebProbe/package-lock.json Tests/WebProbe/editor.js build/web-probe/
npm ci --prefix build/web-probe --ignore-scripts --no-audit --no-fund
node build/web-probe/node_modules/esbuild/bin/esbuild build/web-probe/editor.js --bundle --format=iife --outfile=build/InputProbe.app/Contents/Resources/editor.js
cp Tests/WebProbe/index.html build/InputProbe.app/Contents/Resources/index.html
codesign --force --sign - build/InputProbe.app

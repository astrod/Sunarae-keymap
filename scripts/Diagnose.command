#!/bin/bash
set -euo pipefail
artifact_dir="$(cd "$(dirname "$0")" && pwd)"
"$artifact_dir/Support/diagnose.sh" "$artifact_dir"

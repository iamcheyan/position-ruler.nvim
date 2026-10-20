#!/usr/bin/env bash
# Run the position-ruler.nvim test suite.
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for test_file in "$root_dir"/tests/*_spec.lua; do
  nvim --headless -u NONE \
    --cmd "set rtp^=$root_dir" \
    -l "$test_file"
done

echo "position-ruler.nvim tests: OK"

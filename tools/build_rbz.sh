#!/usr/bin/env bash
# Packages the extension as dist/drawer_maker_pro.rbz (install via Extension Manager).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/dist"
rm -f "$root/dist/drawer_maker_pro.rbz"
cd "$root/src"
zip -qr "$root/dist/drawer_maker_pro.rbz" drawer_maker_pro.rb drawer_maker_pro
echo "Built dist/drawer_maker_pro.rbz"

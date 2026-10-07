#!/usr/bin/env bash
# Apply the Consul config entries: service protocols, then the explicit allows,
# then the catch-all deny. Files are numbered so allows always land before the deny.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for f in "$ROOT"/consul/config-entries/*.hcl; do
  echo "consul config write $(basename "$f")"
  consul config write "$f"
done

echo
consul intention list

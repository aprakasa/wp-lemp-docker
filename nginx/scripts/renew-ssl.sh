#!/bin/bash
set -euo pipefail

~/.acme.sh/acme.sh --renew-all --ecc --force 2>/dev/null || true
nginx -s reload 2>/dev/null || true

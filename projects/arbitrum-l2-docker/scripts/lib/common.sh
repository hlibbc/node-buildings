#!/usr/bin/env bash
# scripts/lib/common.sh — shared utilities for arbitrum-l2-docker scripts

ERRORS=0

_ok()   { printf '  [OK]    %s\n' "$*"; }
_info() { printf '  INFO    %s\n' "$*"; }
_warn() { printf '  [WARN]  %s\n' "$*"; }
_fail() { printf '  [FAIL]  %s\n' "$*"; ERRORS=$((ERRORS + 1)); }

# Resolve project root and load .env
# Usage: init_project  (call from any script)
init_project() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    PROJECT_DIR="$(cd "$script_dir/.." && pwd)"

    if [ ! -f "$PROJECT_DIR/.env" ]; then
        echo "[ERROR] .env not found at $PROJECT_DIR/.env"
        echo "        Run: cp .env.sample .env"
        exit 1
    fi
    set -a
    # shellcheck source=/dev/null
    . "$PROJECT_DIR/.env"
    set +a
}

# Source resolved L1 config (written by 01-load-l1-config.sh)
load_resolved_l1_config() {
    local resolved="$PROJECT_DIR/config/resolved-l1-config.env"
    if [ ! -f "$resolved" ]; then
        echo "[ERROR] config/resolved-l1-config.env not found"
        echo "        Run: pnpm run load:l1"
        exit 1
    fi
    # shellcheck source=/dev/null
    . "$resolved"
}

# HTTP JSON-RPC helper
# Usage: _rpc <url> <json_body>
_rpc() {
    local url="$1" body="$2"
    curl -s --connect-timeout 5 --max-time 30 -X POST \
        -H 'Content-Type: application/json' \
        -d "$body" \
        "$url" 2>/dev/null
}

# Validate 0x-prefixed 40-char hex address
# Returns 0 if valid, 1 if not
is_valid_address() {
    printf '%s' "$1" | grep -qE '^0x[0-9a-fA-F]{40}$'
}

# Convert hex to decimal (works for reasonable integers up to shell int limit)
hex_to_dec() {
    local h="${1#0x}"
    printf '%d' "0x${h}" 2>/dev/null || echo 0
}

# Return 0 (true) if the hex wei value is zero, 1 (false) otherwise
# Handles 0x0, 0x00, 0x, empty, and arbitrary-length hex
# Do NOT use hex_to_dec for zero-check — large wei values overflow shell integers
hex_is_zero() {
    local h
    h="${1#0x}"          # strip 0x prefix
    h="${h#"${h%%[!0]*}"}"  # strip leading zeros
    [ -z "$h" ]          # empty after stripping = zero
}

# Format a hex wei value as "X.XXXXXX ETH" using node for big-integer safety.
# Falls back to raw hex on node failure.
# Security: hex_val is validated as 0x[0-9a-fA-F]+ before use and passed via
# environment variable (not string interpolation) to prevent command injection.
format_wei_eth() {
    local hex_val="${1:-0x0}"
    # Reject anything that is not a valid 0x-prefixed hex literal
    if ! printf '%s' "$hex_val" | grep -qE '^0x[0-9a-fA-F]+$'; then
        echo "$hex_val"
        return
    fi
    if command -v node &>/dev/null && [ -d "${PROJECT_DIR:-}/node_modules" ]; then
        HEX_VAL="$hex_val" node -e '
try {
  const b = BigInt(process.env.HEX_VAL);
  const eth = b / 10n**18n;
  const rem = b % 10n**18n;
  const dec = rem.toString().padStart(18,"0").replace(/0+$/,"").slice(0,6) || "0";
  process.stdout.write(eth.toString() + "." + dec + " ETH");
} catch(e) { process.stdout.write(process.env.HEX_VAL + " (parse error)"); }
' 2>/dev/null || echo "$hex_val"
    elif command -v node &>/dev/null; then
        HEX_VAL="$hex_val" node -e '
try { const b=BigInt(process.env.HEX_VAL); process.stdout.write(b.toString()+" wei"); }
catch(e) { process.stdout.write(process.env.HEX_VAL); }
' 2>/dev/null || echo "$hex_val"
    else
        echo "$hex_val"
    fi
}

# Check a JSON artifact file for private key / mnemonic / secret / password fields.
# Uses jq paths to inspect every field name in the JSON tree.
# Returns 0 (true — found forbidden field) if any suspicious field is detected, 1 otherwise.
# Usage: artifact_has_secret_field <path>
# Suspicious field names (case-insensitive): private, privkey, mnemonic, secret, password
# Note: txHash is a 32-byte hex value but its field name is "txHash", not a secret keyword,
#       so jq path-name matching avoids false positives from value content.
artifact_has_secret_field() {
    local file="$1"
    [ -f "$file" ] || return 1
    jq -e '
      paths(scalars) |
      map(tostring | ascii_downcase) |
      .[] |
      select(
        test("private") or
        test("privkey") or
        test("mnemonic") or
        test("secret") or
        test("password")
      )
    ' "$file" >/dev/null 2>&1
}

# Derive Ethereum address from private key using ethers.js
# Requires node_modules/ethers installed in PROJECT_DIR
# Usage: derive_address "$PRIVATE_KEY"
# Returns: lowercase 0x-prefixed address, or empty string on failure
derive_address() {
    local pk="$1"
    [ -z "$pk" ] && { echo ""; return 1; }
    [ ! -d "${PROJECT_DIR:-}/node_modules" ] && { echo ""; return 1; }
    PK_TO_DERIVE="$pk" PROJECT_ROOT="${PROJECT_DIR}" node -e "
const path = require('path');
const {ethers} = require(path.join(process.env.PROJECT_ROOT, 'node_modules', 'ethers'));
try {
    const w = new ethers.Wallet(process.env.PK_TO_DERIVE);
    process.stdout.write(w.address.toLowerCase());
} catch(e) { process.exit(1); }
" 2>/dev/null || echo ""
}

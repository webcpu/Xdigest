#!/bin/bash
# Security audit for a Swift project before pushing to a public repo or
# tagging a release. Catches BOTH:
#   1. Secrets that gitleaks knows about (AWS keys, API tokens, private keys).
#   2. PII that gitleaks ignores (developer name, absolute paths with
#      /Users/<name>/, hardcoded email addresses).
#
# Usage:
#   ./scripts/security-check.sh           # full audit, exit 1 on any finding
#   ./scripts/security-check.sh --quick   # skip full git history scan (faster)
#
# Reference: ~/.claude/skills/security-audit/SKILL.md describes the procedure
# this script automates, including how to interpret findings.

set -euo pipefail

QUICK=0
for arg in "$@"; do
    case "$arg" in
        --quick) QUICK=1 ;;
        *)       echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

FINDINGS=0

# -----------------------------------------------------------------------------
# Phase 1 — gitleaks: working tree
# -----------------------------------------------------------------------------

echo "==> Phase 1: gitleaks (working tree)"
if ! command -v gitleaks >/dev/null 2>&1; then
    echo "    SKIP: gitleaks not installed. brew install gitleaks"
else
    if gitleaks detect --source . --no-banner --redact 2>&1 | sed 's/^/    /'; then
        echo "    OK"
    else
        echo "    FAIL: gitleaks found secrets in the working tree"
        FINDINGS=$((FINDINGS + 1))
    fi
fi

# -----------------------------------------------------------------------------
# Phase 2 — gitleaks: full git history
# -----------------------------------------------------------------------------

if [ "$QUICK" = "1" ]; then
    echo "==> Phase 2: gitleaks (full history) — SKIPPED (--quick)"
else
    echo "==> Phase 2: gitleaks (full history)"
    if ! command -v gitleaks >/dev/null 2>&1; then
        echo "    SKIP: gitleaks not installed"
    else
        if gitleaks detect --source . --no-banner --redact --log-opts="--all" 2>&1 | sed 's/^/    /'; then
            echo "    OK"
        else
            echo "    FAIL: gitleaks found secrets in git history"
            echo "    (the secret is exposed in every clone — rotate the credential)"
            FINDINGS=$((FINDINGS + 1))
        fi
    fi
fi

# -----------------------------------------------------------------------------
# Phase 3 — personal identifier grep (developer name)
# -----------------------------------------------------------------------------

echo "==> Phase 3: developer name leak"
NAME="$(git config user.name || true)"
# If git config user.name matches the GitHub repo owner (derived from
# `origin`), it's a public handle -- the whole point is that it's in
# URLs and code that references the repo. Not a PII leak. Skip the
# check to avoid false positives on projects where user.name is a
# GitHub handle rather than a real name.
REPO_OWNER=""
REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"
if [ -n "$REMOTE_URL" ]; then
    REPO_OWNER=$(printf '%s' "$REMOTE_URL" | sed -nE 's#.*github\.com[:/]([^/]+)/.*#\1#p')
fi

if [ -z "$NAME" ]; then
    echo "    SKIP: git config user.name is empty"
elif [ -n "$REPO_OWNER" ] && [ "$NAME" = "$REPO_OWNER" ]; then
    echo "    SKIP: git config user.name ('$NAME') equals the repo owner -- public handle"
else
    # Exclude docs/license files where the name legitimately appears.
    HITS=$(git ls-files \
        | grep -v -iE '(^|/)(LICENSE|AUTHORS|CHANGELOG|CONTRIBUTORS|NOTICE)($|\.|/)' \
        | grep -v -E '\.md$' \
        | xargs -I{} grep -l -F -- "$NAME" {} 2>/dev/null || true)
    if [ -z "$HITS" ]; then
        echo "    OK (searched for '$NAME')"
    else
        echo "    FAIL: '$NAME' hardcoded in:"
        echo "$HITS" | sed 's/^/      /'
        echo "    fix: auto-discover from keychain / env / git config instead"
        FINDINGS=$((FINDINGS + 1))
    fi
fi

# -----------------------------------------------------------------------------
# Phase 4 — hardcoded absolute paths
# -----------------------------------------------------------------------------

echo "==> Phase 4: absolute path leak (/Users/<name>/)"
HITS=$(git ls-files \
    | grep -v -E '\.md$' \
    | xargs grep -l -E '/Users/[a-zA-Z0-9_-]+/' 2>/dev/null || true)
if [ -z "$HITS" ]; then
    echo "    OK"
else
    echo "    FAIL: hardcoded /Users/ paths in:"
    echo "$HITS" | sed 's/^/      /'
    echo "    fix: replace with \$HOME, \$SCRIPT_DIR, or a relative path"
    FINDINGS=$((FINDINGS + 1))
fi

# -----------------------------------------------------------------------------
# Phase 5 — .gitignore defensive coverage
# -----------------------------------------------------------------------------

echo "==> Phase 5: .gitignore defensive patterns"
REQUIRED_PATTERNS=(
    ".env"
    ".env.*"
    "*.pem"
    "*.key"
    "*.p12"
    "secrets/"
    "credentials.json"
)
MISSING=()
for pattern in "${REQUIRED_PATTERNS[@]}"; do
    if ! grep -qF -- "$pattern" .gitignore 2>/dev/null; then
        MISSING+=("$pattern")
    fi
done
if [ ${#MISSING[@]} -eq 0 ]; then
    echo "    OK"
else
    echo "    FAIL: .gitignore is missing defensive patterns:"
    for p in "${MISSING[@]}"; do
        echo "      $p"
    done
    echo "    fix: add the missing lines to .gitignore"
    FINDINGS=$((FINDINGS + 1))
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo
if [ "$FINDINGS" -eq 0 ]; then
    echo "==> Clean. Safe to push/release."
    exit 0
else
    echo "==> $FINDINGS phase(s) reported findings. Fix before pushing."
    exit 1
fi

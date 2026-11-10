#!/bin/sh
set -e

# Unit test for Asura OS systemctl and journalctl compatibility bridge
SCRIPT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
SYSTEMCTL="$SCRIPT_DIR/system/helpers/systemctl"
JOURNALCTL="$SCRIPT_DIR/system/helpers/journalctl"

echo "=== Testing systemctl --version ==="
OUT="$("$SYSTEMCTL" --version)"
echo "$OUT" | grep -q "systemd" || (echo "FAIL: --version did not output systemd" && exit 1)

echo "=== Testing systemctl daemon-reload ==="
"$SYSTEMCTL" daemon-reload

echo "=== Testing .service file generation ==="
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_SVC_FILE="$TMP_DIR/sample-ollama.service"
cat >"$TEST_SVC_FILE" <<'EOF'
[Unit]
Description=Ollama Service

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
WorkingDirectory=/var/lib/ollama
Environment="OLLAMA_HOST=0.0.0.0:11434"
Restart=always
EOF

# Override paths using subshell environment
(
    # Mock systemd unit discovery path
    mkdir -p "$TMP_DIR/etc/systemd/system" "$TMP_DIR/etc/sv" "$TMP_DIR/var/service"
    cp "$TEST_SVC_FILE" "$TMP_DIR/etc/systemd/system/ollama.service"

    # Replace /etc/systemd and /etc/sv targets inside isolated test run
    sed -e "s|/etc/systemd/system|$TMP_DIR/etc/systemd/system|g" \
        -e "s|/etc/sv|$TMP_DIR/etc/sv|g" \
        -e "s|/var/service|$TMP_DIR/var/service|g" \
        "$SYSTEMCTL" > "$TMP_DIR/test-systemctl"
    chmod +x "$TMP_DIR/test-systemctl"

    "$TMP_DIR/test-systemctl" enable ollama.service

    # Verify runit files were created
    test -f "$TMP_DIR/etc/sv/ollama/run"
    test -x "$TMP_DIR/etc/sv/ollama/run"
    test -f "$TMP_DIR/etc/sv/ollama/log/run"
    test -L "$TMP_DIR/var/service/ollama"

    grep -q "/usr/local/bin/ollama serve" "$TMP_DIR/etc/sv/ollama/run"
    grep -q "export OLLAMA_HOST=0.0.0.0:11434" "$TMP_DIR/etc/sv/ollama/run"
    grep -q "svlogd -tt /var/log/ollama" "$TMP_DIR/etc/sv/ollama/log/run"

    # Test disable
    "$TMP_DIR/test-systemctl" disable ollama
    test ! -L "$TMP_DIR/var/service/ollama"
)

echo "=== Testing journalctl --help ==="
"$JOURNALCTL" --help | grep -q "journalctl"

echo "PASS: systemctl bridge test ok"

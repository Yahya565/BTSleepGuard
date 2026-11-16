#!/bin/zsh
set -euo pipefail
LABEL=local.btsleepguard
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Applications/BTSleepGuard.app"
echo "✓ BTSleepGuard removed"

#!/bin/zsh
# Removes BTSleepGuard (same as ./install.sh --uninstall).
exec zsh "${0:A:h}/install.sh" --uninstall

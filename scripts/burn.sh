#!/usr/bin/env bash
# Snelkoppeling om vanaf de command-line te burnen.
# Draait de echte burner-wrapper onder /opt/quitchat-burner.
# Gebruik: sudo ./burn.sh
exec /opt/quitchat-burner/wrappers/burn.sh "$@"

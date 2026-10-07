#!/bin/sh
# Harmless slow script: gives time to kill -9 a session mid-tool.
i=0
while [ "$i" -lt "${1:-60}" ]; do echo "tick $i"; sleep 1; i=$((i + 1)); done

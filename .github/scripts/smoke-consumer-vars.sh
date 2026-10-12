#!/usr/bin/env bash
# Verify: the consumer's vars reach the modules
set -euo pipefail
version=$(task release:version)
case "$version" in
  9.9.9-dev.*) echo "✔ consumer vars reach the modules ($version)" ;;
  *) echo "✖ expected a 9.9.9 base, got $version" >&2; exit 1 ;;
esac

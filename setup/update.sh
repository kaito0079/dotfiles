#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")/../" && pwd)"

# scriptファイルに実行権限を付与
chmod a+x scripts/*

if [ "$(uname)" == "Darwin" ] ; then
  "${SCRIPT_DIR}"/scripts/update_brewfile.sh
fi

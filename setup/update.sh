#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")/../" && pwd)"

# scriptファイルに実行権限を付与
chmod a+x "${SCRIPT_DIR}"/setup/*.sh

if [ "$(uname)" == "Darwin" ] ; then
  "${SCRIPT_DIR}"/setup/update_brewfile.sh
fi

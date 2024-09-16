#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")/../" && pwd)"

if [ "$(uname)" == "Darwin" ] ; then
	echo "MacOS!"
    "${SCRIPT_DIR}"/scripts/init_mac.sh
fi


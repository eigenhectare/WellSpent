#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "${script_directory}/watch-physical-p2.sh" "$@" hold-inbox

#!/usr/bin/env bash
# SPDX-FileCopyrightText: © Vegard IT GmbH (https://vegardit.com) and contributors
# SPDX-FileContributor: Sebastian Thomschke, Vegard IT GmbH
# SPDX-License-Identifier: Apache-2.0
#
set -eu

run-with() {
  local shell="$1"
  if command -v parallel >/dev/null; then
    mkdir -p ~/.parallel
    touch ~/.parallel/will-cite
  fi
  if command -v "$shell" >/dev/null; then
    "${0%/*}"/test.sh "$shell"
  else
    echo "Skipping testing with shell [$shell]..."
  fi
}

run-with bash
run-with dash
run-with ksh
run-with zsh
run-with busybox

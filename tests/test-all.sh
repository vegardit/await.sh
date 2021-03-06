#!/usr/bin/env bash
#
# Copyright 2019-2021 by Vegard IT GmbH, Germany, https://vegardit.com
# SPDX-License-Identifier: Apache-2.0
#
# @author Sebastian Thomschke, Vegard IT GmbH
#
set -eu

run-with() {
  local shell="$1"
  if command -v parallel >/dev/null; then
    mkdir -p ~/.parallel
    touch ~/.parallel/will-cite
    local bats_jobs="-j 6"
  fi
  if command -v "$shell" >/dev/null; then
    ${0%/*}/test.sh "$shell"
  else
    echo "Skipping testing with shell [$shell]..."
  fi
}

run-with bash
run-with dash
run-with ksh
run-with zsh
run-with busybox

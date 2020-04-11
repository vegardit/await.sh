#!/usr/bin/env bash
#
# Copyright 2019-2020 by Vegard IT GmbH, Germany, https://vegardit.com
# SPDX-License-Identifier: Apache-2.0
#
# @author Sebastian Thomschke, Vegard IT GmbH
#
set -e

# install bats
if [[ ! -e ~/bats-repo ]]; then
  git clone https://github.com/bats-core/bats-core.git ~/bats-repo
  rm -rf ~/bats
  bash ~/bats-repo/install.sh ~/bats
fi

run-with() {
  local shell="$1"
  if command -v parallel >/dev/null; then
    mkdir -p ~/.parallel
    touch ~/.parallel/will-cite
    local bats_jobs="-j 6"
  fi
  if command -v "$shell" >/dev/null; then
    if [[ $shell == "busybox" ]]; then
      shell="busybox sh"
    fi
    echo "#####################################"
    echo "# Testing with shell [$shell]..."
    echo "#####################################"
    echo
    for test_file in $(command ls ${0%/*}/*.bats); do
      echo " Testing [$test_file]..."
      echo " -----------------------------------"
      TEST_SHELL="$shell" bash ~/bats/bin/bats ${bats_jobs:-} "$test_file"
    done
  else
    echo "Skipping testing with shell: $shell..."
  fi
}

run-with bash
run-with dash
run-with ksh
run-with zsh
run-with busybox

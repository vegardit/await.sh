#!/usr/bin/env bash
# SPDX-FileCopyrightText: © Vegard IT GmbH (https://vegardit.com) and contributors
# SPDX-FileContributor: Sebastian Thomschke, Vegard IT GmbH
# SPDX-License-Identifier: Apache-2.0
#
set -eu

# install bats
if [[ ! -d ~/bats/core ]]; then
  mkdir -p ~/bats
  git clone --depth=1 --single-branch https://github.com/bats-core/bats-core.git ~/bats/core
fi
if [[ ! -d ~/bats/support ]]; then
  git clone --depth=1 --single-branch https://github.com/bats-core/bats-support.git ~/bats/support
fi
if [[ ! -d ~/bats/assert ]]; then
  git clone --depth=1 --single-branch https://github.com/bats-core/bats-assert.git ~/bats/assert
fi

if command -v parallel >/dev/null; then
  mkdir -p ~/.parallel
  touch ~/.parallel/will-cite
  bats_jobs="-j 6"
fi

shells=${*:-bash dash ksh zsh busybox}

for shell in $shells; do
  export TEST_SHELL=$shell

  if hash -v "$shell" &>/dev/null; then
    echo "*************************************"
    echo "* Shell [$shell] not found, skipping tests..."
    echo "*************************************"
    continue
  fi

  if [[ $TEST_SHELL == "busybox" ]]; then
    export TEST_SHELL="busybox sh"
  fi

  echo "#####################################"
  echo "# Testing with shell [$TEST_SHELL]..."
  echo "#####################################"
  echo
  for test_file in "${0%/*}"/*.bats; do
    echo "Testing [$test_file]..."
    echo "-----------------------------------"

    # shellcheck disable=SC2086 # (info): Double quote to prevent globbing and word splitting
    bash ~/bats/core/bin/bats ${bats_jobs:-} "$test_file"
  done
done



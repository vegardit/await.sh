#!/usr/bin/env bash
# SPDX-FileCopyrightText: © Vegard IT GmbH (https://vegardit.com) and contributors
# SPDX-FileContributor: Sebastian Thomschke, Vegard IT GmbH
# SPDX-License-Identifier: Apache-2.0
#
set -eu

# install bats
if [[ ! -e ~/bats-repo ]]; then
  git clone https://github.com/bats-core/bats-core.git ~/bats-repo
  rm -rf ~/bats
  bash ~/bats-repo/install.sh ~/bats
fi

if command -v parallel >/dev/null; then
  mkdir -p ~/.parallel
  touch ~/.parallel/will-cite
  bats_jobs="-j 6"
fi

export TEST_SHELL=${1:-sh}

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
  bash ~/bats/bin/bats ${bats_jobs:-} "$test_file"
done

#!/usr/bin/env bash
#
# Copyright 2019 by Vegard IT GmbH, Germany, https://vegardit.com
# SPDX-License-Identifier: Apache-2.0
#
# @author Sebastian Thomschke, Vegard IT GmbH
#
set -e

if command -v parallel >/dev/null; then
  mkdir -p ~/.parallel
  touch ~/.parallel/will-cite
  bats_jobs="-j 6"
fi

echo "#####################################"
echo "# Testing with shell [$TEST_SHELL]..."
echo "#####################################"
echo
for test_file in $(command ls ${0%/*}/*.bats); do
  echo " Testing [$test_file]..."
  echo " -----------------------------------"
  bash /tmp/bats/bin/bats ${bats_jobs:-} "$test_file"
done

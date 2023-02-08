#!/usr/bin/env bats
# SPDX-FileCopyrightText: © Vegard IT GmbH (https://vegardit.com) and contributors
# SPDX-FileContributor: Sebastian Thomschke, Vegard IT GmbH
# SPDX-License-Identifier: Apache-2.0
#
# BATS Tests (https://github.com/bats-core/bats-core) of await-tcp.sh script
#

setup() {
  rc_ok=0
  rc_cmd_not_found=2
  rc_invalid_args=3
  rc_timed_out=4

  candidate=$BATS_TEST_DIRNAME/../await-tcp.sh
  chmod u+x $candidate

  if [ -n "$TEST_SHELL" ]; then
    candidate="${TEST_SHELL} $candidate"
  fi
}


test_with() {
  expected_rc=$1 && shift
  run $candidate "$@"
  if [ $status -ne $expected_rc ]; then
    echo "# COMMAND: $candidate $@" >&3
    echo "# ERROR: $output" >&3
    return 1
  fi
}


##############################
# test argument parsing
##############################

@test "${TEST_SHELL:-sh}: Show usage help if executed without args" {
  test_with $rc_invalid_args

  [[ $output == *"Usage:"* ]]
  [[ $output == *"ERROR: Required parameter missing"* ]]
}


@test "${TEST_SHELL:-sh}: Show usage help if executed with --help" {
  test_with $rc_ok --help

  [[ $output == *"Usage:"* ]]
  [[ $output != *"ERROR:"* ]]
}


@test "${TEST_SHELL:-sh}: Test missing TIMEOUT parameter" {
  test_with $rc_invalid_args google.com:80 -- echo UP

  [[ $output != *"UP"* ]]
  [[ $output == *"ERROR: TIMEOUT parameter must be an integer"* ]]
}


@test "${TEST_SHELL:-sh}: Test invalid -t option value" {
  test_with $rc_invalid_args -t BLA 5 google.com:80 -- echo UP

  [[ $output != *"UP"* ]]
  [[ $output == *"ERROR: Option -t must be followed by an integer"* ]]
}


@test "${TEST_SHELL:-sh}: Test missing -t option value" {
  test_with $rc_invalid_args -t -w 5 5 google.com:80 -- echo UP

  [[ $output != *"UP"* ]]
  [[ $output == *"ERROR: Option -t must be followed by an integer"* ]]
}


@test "${TEST_SHELL:-sh}: Test invalid -w option value" {
  test_with $rc_invalid_args -w BLA 5 google.com:80 -- echo UP

  [[ $output != *"UP"* ]]
  [[ $output == *"ERROR: Option -w must be followed by an integer"* ]]
}


##############################
# test await
##############################

@test "${TEST_SHELL:-sh}: Test port google.com:80 is available" {
  test_with $rc_ok 10 google.com:80 -- echo UP

  [[ $output == *"UP"* ]]
  [[ $output != *"ERROR:"* ]]
}


@test "${TEST_SHELL:-sh}: Test port google.com:84 is unavailable" {
  test_with $rc_timed_out -t 1 5 google.com:84 -- echo UP

  [[ $output != *"UP"* ]]
  [[ $output == *"ERROR:"*"did not get ready within required time"* ]]
}

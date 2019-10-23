#!/usr/bin/env bats
#
# Copyright 2019 by Vegard IT GmbH, Germany, https://vegardit.com
# SPDX-License-Identifier: Apache-2.0
#
# @author Sebastian Thomschke, Vegard IT GmbH
#
# BATS Tests (https://github.com/bats-core/bats-core) of await-http.sh script
#


setup() {
  rc_ok=0
  rc_cmd_not_found=2
  rc_invalid_args=3
  rc_timed_out=4

  candidate=$BATS_TEST_DIRNAME/../await-cmd.sh
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
  test_with $rc_invalid_args true -- echo UP

  [[ $output != *"UP"* ]]
  [[ $output == *"ERROR: TIMEOUT parameter must be an integer"* ]]
}


@test "${TEST_SHELL:-sh}: Test invalid -t option value" {
  test_with $rc_invalid_args -t BLA 5 true -- echo UP

  [[ $output != *"UP"* ]]
  [[ $output == *"ERROR: Option -t must be followed by an integer"* ]]
}


@test "${TEST_SHELL:-sh}: Test missing -t option value" {
  test_with $rc_invalid_args -t -w 5 5 true -- echo UP

  [[ $output != *"UP"* ]]
  [[ $output == *"ERROR: Option -t must be followed by an integer"* ]]
}


@test "${TEST_SHELL:-sh}: Test invalid -w option value" {
  test_with $rc_invalid_args -w BLA 5 true -- echo UP

  [[ $output != *"UP"* ]]
  [[ $output == *"ERROR: Option -w must be followed by an integer"* ]]
}



##############################
# test await
##############################

@test "${TEST_SHELL:-sh}: Test condition is met" {
  test_with $rc_ok 1 true -- echo "UP"

  [[ $output == *"UP"* ]]
  [[ $output != *"ERROR:"* ]]
}


@test "${TEST_SHELL:-sh}: Test condition is not met" {
  test_with $rc_timed_out -w 1 1 false -- echo "UP"

  [[ $output != *"UP"* ]]
  [[ $output == *"ERROR:"*"did not get ready within required time"* ]]
}


@test "${TEST_SHELL:-sh}: Kill long running test command" {
  test_with $rc_timed_out -t 1 -w 1 1 sleep 20 -- echo "UP"

  [[ $output != *"UP"* ]]
  [[ $output == *"ERROR:"*"did not get ready within required time"* ]]
}


@test "${TEST_SHELL:-sh}: Test follow-up command is not found" {
  test_with $rc_cmd_not_found 1 true -- foobar

  [[ $output != *"UP"* ]]
  [[ $output == *"ERROR: Required command 'foobar' not found"* ]]
}
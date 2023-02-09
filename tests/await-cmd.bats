#!/usr/bin/env bats
# SPDX-FileCopyrightText: © Vegard IT GmbH (https://vegardit.com) and contributors
# SPDX-FileContributor: Sebastian Thomschke, Vegard IT GmbH
# SPDX-License-Identifier: Apache-2.0
#
# BATS Tests (https://github.com/bats-core/bats-core) of await-cmd.sh script
#

function setup() {
  load ~/bats/support/load
  load ~/bats/assert/load

  readonly RC_OK=0
  readonly RC_CMD_NOT_FOUND=2
  readonly RC_INVALID_ARGS=3
  readonly RC_TIMED_OUT=4

  CANDIDATE=$(dirname "$BATS_TEST_DIRNAME")/await-cmd.sh
  chmod u+x $CANDIDATE

  if [ -n "$TEST_SHELL" ]; then
    CANDIDATE="${TEST_SHELL} $CANDIDATE"
  fi
}


function assert_exitcode() {
  expected_rc=$1 && shift
  run $CANDIDATE "$@"
  if [ $status -ne $expected_rc ]; then
    echo "# COMMAND: $CANDIDATE $@" >&3
    echo "# ERROR: $output" >&3
    return 1
  fi
}


##############################
# test argument parsing
##############################

@test "${TEST_SHELL:-sh}: Show usage help if executed without args" {
  assert_exitcode $RC_INVALID_ARGS

  assert_regex "$output" '^Usage:'
  assert_regex "$output" 'ERROR: Required parameter missing'
}


@test "${TEST_SHELL:-sh}: Show usage help if executed with --help" {
  assert_exitcode $RC_OK --help

  assert_regex "$output" '^Usage:'
  refute_regex "$output" 'ERROR:'
}


@test "${TEST_SHELL:-sh}: Test missing TIMEOUT parameter" {
  assert_exitcode $RC_INVALID_ARGS true -- echo UP

  refute_regex "$output" 'UP'
  assert_regex "$output" 'ERROR: TIMEOUT parameter must be an integer'
}


@test "${TEST_SHELL:-sh}: Test invalid -t option value" {
  assert_exitcode $RC_INVALID_ARGS -t BLA 5 true -- echo UP

  refute_regex "$output" 'UP'
  assert_regex "$output" 'ERROR: Option -t must be followed by an integer'
}


@test "${TEST_SHELL:-sh}: Test missing -t option value" {
  assert_exitcode $RC_INVALID_ARGS -t -w 5 5 true -- echo UP

  refute_regex "$output" 'UP'
  assert_regex "$output" 'ERROR: Option -t must be followed by an integer'
}


@test "${TEST_SHELL:-sh}: Test invalid -w option value" {
  assert_exitcode $RC_INVALID_ARGS -w BLA 5 true -- echo UP

  refute_regex "$output" 'UP'
  assert_regex "$output" 'ERROR: Option -w must be followed by an integer'
}



##############################
# test await
##############################

@test "${TEST_SHELL:-sh}: Test condition is met" {
  assert_exitcode $RC_OK 1 true -- echo 'UP'

  assert_regex "$output" 'UP'
  refute_regex "$output" 'ERROR:'
}


@test "${TEST_SHELL:-sh}: Test condition is not met" {
  assert_exitcode $RC_TIMED_OUT -w 1 1 false -- echo 'UP'

  refute_regex "$output" 'UP'
  assert_regex "$output" 'ERROR:.*did not get ready within required time'
}


@test "${TEST_SHELL:-sh}: Kill long running test command" {
  assert_exitcode $RC_TIMED_OUT -t 1 -w 1 1 sleep 20 -- echo 'UP'

  refute_regex "$output" 'UP'
  assert_regex "$output" 'ERROR:.*did not get ready within required time'
}


@test "${TEST_SHELL:-sh}: Test follow-up command is not found" {
  assert_exitcode $RC_CMD_NOT_FOUND 1 true -- foobar

  refute_regex "$output" 'UP'
  assert_regex "$output" "ERROR: Required command 'foobar' not found"
}
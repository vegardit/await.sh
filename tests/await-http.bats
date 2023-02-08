#!/usr/bin/env bats
# SPDX-FileCopyrightText: © Vegard IT GmbH (https://vegardit.com) and contributors
# SPDX-FileContributor: Sebastian Thomschke, Vegard IT GmbH
# SPDX-License-Identifier: Apache-2.0
#
# BATS Tests (https://github.com/bats-core/bats-core) of await-http.sh script
#

function setup() {
  load ~/bats/support/load
  load ~/bats/assert/load

  readonly RC_OK=0
  readonly RC_CMD_NOT_FOUND=2
  readonly RC_INVALID_ARGS=3
  readonly RC_TIMED_OUT=4

  CANDIDATE=$BATS_TEST_DIRNAME/../await-http.sh
  chmod u+x $CANDIDATE

  if [ -n "$TEST_SHELL" ]; then
    CANDIDATE="${TEST_SHELL} $CANDIDATE"
  fi
}


function assert_exitcode() {
  expected_rc=$1 && shift
  run $CANDIDATE "$@"

  if [ $status -ne 0 ] && [[ $output == *"wget: not an http or ftp url"* ]]; then
    # silently ignore test if wget is compiled without HTTP support.
    return 0
  fi

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
  assert_exitcode $RC_INVALID_ARGS http://google.com -- echo UP

  refute_regex "$output" 'UP'
  assert_regex "$output" 'ERROR: TIMEOUT parameter must be an integer'
}


@test "${TEST_SHELL:-sh}: Test invalid -t option value" {
  assert_exitcode $RC_INVALID_ARGS -t BLA 5 http://google.com -- echo UP

  refute_regex "$output" 'UP'
  assert_regex "$output" 'ERROR: Option -t must be followed by an integer'
}


@test "${TEST_SHELL:-sh}: Test missing -t option value" {
  assert_exitcode $RC_INVALID_ARGS -t -w 5 5 http://google.com -- echo UP

  refute_regex "$output" 'UP'
  assert_regex "$output" 'ERROR: Option -t must be followed by an integer'
}


@test "${TEST_SHELL:-sh}: Test invalid -w option value" {
  assert_exitcode $RC_INVALID_ARGS -w BLA 5 http://google.com -- echo UP

  refute_regex "$output" 'UP'
  assert_regex "$output" 'ERROR: Option -w must be followed by an integer'
}


##############################
# test await
##############################

@test "${TEST_SHELL:-sh}: Test http://google.com is available" {
  assert_exitcode $RC_OK 10 http://google.com -- echo 'UP'

  assert_regex "$output" 'UP'
  refute_regex "$output" 'ERROR:'
}


@test "${TEST_SHELL:-sh}: Test http://google.com AND https://google.com are available" {
  assert_exitcode $RC_OK 10 http://google.com https://google.com -- echo UP

  if [[ $output == *"wget: not an http or ftp url"* ]]; then
    # silently ignore test if wget is compiled without HTTP support.
    return 0
  fi

  assert_regex "$output" 'UP'
  refute_regex "$output" 'ERROR:'
}


@test "${TEST_SHELL:-sh}: Test http://google.com:84 is unavailable" {
  assert_exitcode $RC_TIMED_OUT 5 http://google.com:84 -- echo 'UP'

  refute_regex "$output" 'UP'
  assert_regex "$output" 'ERROR:.*did not get ready within required time'
}


@test "${TEST_SHELL:-sh}: Test http://google.com:443 is unavailable (protocol mismatch)" {
  assert_exitcode $RC_TIMED_OUT 5 http://google.com:443 -- echo 'UP'

  refute_regex "$output" 'UP'
  assert_regex "$output" 'ERROR:.*did not get ready within required time'
}


@test "${TEST_SHELL:-sh}: Test https://google.com:80 is unavailable (protocol mismatch)" {
  assert_exitcode $RC_TIMED_OUT 5 http://google.com:443 -- echo 'UP'

  if [[ $output == *"wget: not an http or ftp url"* ]]; then
    # silently ignore test if wget is compiled without HTTP support.
    return 0
  fi

  refute_regex "$output" 'UP'
  assert_regex "$output" 'ERROR:.*did not get ready within required time'
}


@test "${TEST_SHELL:-sh}: Test one of multiple URLs is unavailable" {
  assert_exitcode $RC_TIMED_OUT 5 http://google.com http://google.com:84 -- echo UP

  refute_regex "$output" 'UP'
  assert_regex "$output" 'ERROR:.*did not get ready within required time'
}

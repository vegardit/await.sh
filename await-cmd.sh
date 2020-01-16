#!/bin/sh
#
# Copyright 2019 by Vegard IT GmbH, Germany, https://vegardit.com
# SPDX-License-Identifier: Apache-2.0
#
# @author Sebastian Thomschke, Vegard IT GmbH
#
# https://github.com/vegardit/await.sh/
#
set -e


##############################
# Exit codes
##############################
rc_cmd_not_found=2
rc_invalid_args=3
rc_timed_out=4


##############################
# Functions
##############################
show_help() {
  echo "Usage: $0 [OPTION]... TIMEOUT TEST_COMMAND [ARG...] [-- COMMAND [ARG...]]"
  echo
  echo "Executes TEST_COMMAND repeatedly until it's exit code is 0. Then executes COMMAND."
  echo
  echo "Parameters:"
  echo "  TIMEOUT       - Duration in seconds within TEST_COMMAND must return exit code 0."
  echo "  TEST_COMMAND  - Command that will be executed to test if the waiting condition is met."
  echo "  COMMAND       - Command to be executed once the TEST_COMMAND succeeded (optional)."
  echo
  echo "Options:"
  echo "  -f       - Force execution of COMMAND even if timeout occurred."
  echo "  -t SECS  - Duration in seconds after which a TEST_COMMAND process is terminated (optional, default: 10 seconds)."
  echo "  -w SECS  - Waiting period in seconds between each execution of TEST_COMMAND (optional, default: 5 seconds)."
  echo
  echo "Examples:"
  echo "  $0 30 /opt/scripts/check_remote_services.sh -- /opt/server/start.sh --port 8080"
  echo "  $0 -w 10 30 /opt/scripts/check_remote_services.sh -- /opt/server/start.sh --port 8080"
}

assert_command_exists() {
  if ! command -v "$1" >/dev/null; then
    echo "ERROR: Required command '$1' not found"'!' >&2
    exit $rc_cmd_not_found
  fi
}

is_integer() {
  # kudos to jilles https://stackoverflow.com/a/3951175/5116073
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

build_timeout_command() {
  _timeout=$1
  if command -v timeout >/dev/null; then
    if timeout --help 2>&1 | grep -q -- "-t SECS"; then
      # BusyBox < 1.30.0 http://lists.busybox.net/pipermail/busybox-cvs/2018-August/038305.html
      # Usage: timeout [-t SECS] [-s SIG] PROG ARGS
      echo "timeout -s 9 -t ${_timeout}"
    else
      echo "timeout -s 9 ${_timeout}"
    fi
  elif command -v perl >/dev/null; then
    # kudos to pilcrow https://stackoverflow.com/a/3223441/5116073
    echo "perl -e 'alarm shift; exec @ARGV' ${_timeout}"
  else
    assert_command_exists timeout
  fi
}

##############################
# argument parsing
##############################
if [ $# -eq 1 ] && [ "$1" = "--help" ]; then
  show_help
  exit
fi

assert_command_exists grep

force_execution=false
retry_interval=5
probe_timeout=10

# option parsing
while [ $# -gt 0 ]; do
  case $1 in
    -f) shift
        force_execution=true
        ;;
    -t) shift
        if ! is_integer "$1"; then
          show_help >&2
          echo >&2
          echo 'ERROR: Option -t must be followed by an integer!' >&2
          exit $rc_invalid_args
        fi
        probe_timeout=$1 && shift
        ;;
    -w) shift
        if ! is_integer "$1"; then
          show_help >&2
          echo >&2
          echo 'ERROR: Option -w must be followed by an integer!' >&2
          exit $rc_invalid_args
        fi
        retry_interval=$1 && shift
        ;;
    *) break ;;
  esac
done

if [ $# -lt 2 ]; then
  show_help >&2
  echo >&2
  echo 'ERROR: Required parameter missing!' >&2
  exit $rc_invalid_args
fi

deadline=$1 && shift
if ! is_integer "$deadline"; then
  show_help >&2
  echo >&2
  echo 'ERROR: TIMEOUT parameter must be an integer!' >&2
  exit $rc_invalid_args
fi

test_command=$1 && shift
assert_command_exists "$test_command"

# collect parameters of test command
while [ $# -gt 0 ]; do
  if [ "$1" = "--" ]; then
    break
  fi
  case $1 in
    *'"'*) command="$command '$1'" ;;
    *)     command="$command \"$1\"" ;;
  esac
  shift
done

if [ -z "$1" ]; then
  command=""
else
  if [ "$1" != "--" ] ; then
    show_help >&2
    echo >&2
    echo "ERROR: Separator '--' is missing in parameter list!" >&2
    exit $rc_invalid_args
  fi
  shift
  if [ -z "$1" ]; then
    command=""
  else
    command="$1" && shift
    assert_command_exists "$command"
    for arg in "$@"; do
      case $arg in
        *'"'*) command="$command '$arg'" ;;
        *)     command="$command \"$arg\"" ;;
      esac
    done
  fi
fi


##############################
# waiting for condition
##############################
echo "Waiting up to $deadline seconds for [$test_command] to get ready..."
wait_until=$(( $(date +%s) + deadline ))
timeout_cmd=$(build_timeout_command "$probe_timeout")
while true; do
  set +e
  printf "=> executing [$timeout_cmd $test_command]..."
  # shellcheck disable=SC2086
  result=$(eval $timeout_cmd $test_command 2>&1)
  # shellcheck disable=SC2181
  if [ $? -eq 0 ]; then
    echo "ERROR"
    set -e
    break
  else
    echo "OK"
  fi
  set -e

  if [ "$(date +%s)" -ge $wait_until ]; then
    echo "$result" >&2
    echo >&2
    echo "ERROR: [$test_command] did not get ready within required time." >&2
    if [ "$force_execution" = "true" ]; then
      break
    else
      exit $rc_timed_out
    fi
  fi
  sleep "$retry_interval"
done
echo "SUCCESS: Waiting condition is met."


##############################
# follow-up command execution
##############################
if [ -n "$command" ]; then
  echo "Executing [$command]..."
  # shellcheck disable=SC2086
  exec $command # using exec so shell process is terminated and signals send by docker deamon are receivable by command
fi
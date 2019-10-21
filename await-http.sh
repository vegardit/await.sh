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
  echo "Usage: $0 [OPTION]... TIMEOUT URL... [-- COMMAND [ARG...]]"
  echo
  echo "Repeatedly performs HTTP GET requests until the URL returns a HTTP status code <= 399. Then executes COMMAND."
  echo
  echo "Parameters:"
  echo "  TIMEOUT  - Number of seconds within the URL must be reachable."
  echo "  URL      - URL(s) to be checked using HTTP GET."
  echo "  COMMAND  - Command to be executed once the wait condition is satisfied."
  echo
  echo "Options:"
  echo "  -f       - Force execution of COMMAND even if timeout occurred."
  echo "  -t SECS  - Duration in seconds after which a connection attempt is aborted (optional, default: 10 seconds)."
  echo "  -w SECS  - Duration in seconds to wait between retries (optional, default: 5 seconds)."
  echo
  echo "Examples:"
  echo "  $0 30 http://service1.local -- /opt/server/start.sh --port 8080"
  echo "  $0 30 http://service1.local https://service2.local -- /opt/server/start.sh --port 8080"
  echo "  $0 -w 10 30 https://service1.local -- /opt/server/start.sh --port 8080"
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

build_wget_command() {
  _wget_features=$(wget --help 2>&1)

  _wget_cmd="wget"

  if echo "${_wget_features}" | grep -q -e "GNU Wget 1.19.[4|5]"; then
    # workaround for Wget writing unwanted wget-log files https://savannah.gnu.org/bugs/?51181
    _wget_cmd="${_wget_cmd} -o /dev/null"
  fi

  if echo "${_wget_features}" | grep -q -- "--spider"; then
    _wget_cmd="${_wget_cmd} --spider"
  else
    _wget_cmd="${_wget_cmd} -s" # e.g. BusyBox 1.20
  fi

  if echo "${_wget_features}" | grep -q -- "--tries"; then
    _wget_cmd="${_wget_cmd} --tries 1" # to prevent endless retries on GNU Wget
  fi

  if echo "${_wget_features}" | grep -q -- "-S"; then
    _wget_cmd="${_wget_cmd} -S"
  fi

  echo "${_wget_cmd}"
}


##############################
# argument parsing
##############################
if [ $# -eq 1 ] && [ "$1" = "--help" ]; then
  show_help
  exit
fi

assert_command_exists grep
assert_command_exists wget

force_execution=false
retry_interval=5
probe_timeout=10

# option parsing
while [ $# -gt 0 ]; do
  case $1 in
    -f) force_execution=true ;;
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
  echo 'ERROR: DEADLINE parameter must be an integer!' >&2
  exit $rc_invalid_args
fi

# collect target addresses
targets=$1 && shift
while [ $# -gt 0 ]; do
  if [ "$1" = "--" ]; then
    break
  fi
  targets="$targets $1"
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
echo "Waiting up to $deadline seconds for [$targets] to get ready..."
wait_until=$(( $(date +%s) + deadline ))
timeout_cmd=$(build_timeout_command "$probe_timeout")
wget_cmd=$(build_wget_command)
while true; do
  no_errors=true
  last_error_msg=
  last_error_target=
  for target in $targets; do
    set +e
    echo "=> executing [$timeout_cmd $wget_cmd $target]..."
    # shellcheck disable=SC2086
    result=$(eval $timeout_cmd $wget_cmd "$target" 2>&1)
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
      no_errors=false
      last_error_msg=$result
      last_error_target=$target
    fi
    set -e
  done

  if [ "$no_errors" = "true" ]; then
    break
  fi

  case $last_error_msg in
     *"Unsupported scheme"*|*"wget: not an http or ftp url"*)
       echo "ERROR: $last_error_msg" >&2
       echo >&2
       exit $rc_invalid_args
       ;;
  esac

  if [ "$(date +%s)" -ge $wait_until ]; then
    echo "$last_error_msg" >&2
    echo >&2
    echo "ERROR: [$last_error_target] did not get ready within required time." >&2
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
  eval $command
fi
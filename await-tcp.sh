#!/bin/sh
#
# Copyright 2019-2021 by Vegard IT GmbH, Germany, https://vegardit.com
# SPDX-License-Identifier: Apache-2.0
#
# @author Sebastian Thomschke, Vegard IT GmbH
#
# https://github.com/vegardit/await.sh/
#
set -e


#################################################
# enable debug mode if requested
#################################################
if [ "${DEBUG:-}" = "1" ]; then
  if command -v "ps" >/dev/null; then
    echo "shell: $(ps -sp $$)" >&2
  fi
  PS4='+[$?] $0:$LINENO  '
  set -x
fi


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
  echo "Usage: $0 [OPTION]... TIMEOUT HOSTNAME:PORT... [-- COMMAND [ARG...]]"
  echo
  echo "Repeatedly attempts to connect to the given address until the TCP port is available. Then executes COMMAND."
  echo
  echo "Parameters:"
  echo "  TIMEOUT        - Duration in seconds within the TCP port of the given host must be reachable."
  echo "  HOSTNAME:PORT  - Target TCP address(es) to connect to."
  echo "  COMMAND        - Command to be executed once a connection could be established (optional)."
  echo
  echo "Options:"
  echo "  -f       - Force execution of COMMAND even if timeout occurred."
  echo "  -t SECS  - Duration in seconds after which a connection attempt is aborted (optional, default: 10 seconds)."
  echo "  -w SECS  - Duration in seconds to wait between retries (optional, default: 5 seconds)."
  echo
  echo "Examples:"
  echo "  $0 30 service1.local:389 -- /opt/server/start.sh --port 8080"
  echo "  $0 30 service1.local:389 service2.local:5672 -- /opt/server/start.sh --port 8080"
  echo "  $0 -w 10 30 service1.local:389 -- /opt/server/start.sh --port 8080"
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

build_nc_command() {
  _timeout=$1
  _hostname=$2
  _port=$3

  if command -v "nc" >/dev/null; then
    _nc_features="$(nc 2>&1 || :)"
    _nc_cmd="nc"

    # check if nc command has connect timeout feature
    if echo "${_nc_features}" | grep -q -e "-w timeout" -e "-w secs" -e "-w SECS"; then
      _nc_cmd="${_nc_cmd} -w ${_timeout}"
    else
      # we need to use timeout command
      _nc_cmd="$(build_timeout_command "$_timeout") ${_nc_cmd}"
    fi

    # check if nc command supports Zero-I/O mode (scanning)
    if echo "${_nc_features}" | grep -q -e "-z" -e "\[-[0-9a-zA-Z]*z[0-9a-zA-Z]*\]"; then
      _nc_cmd="${_nc_cmd} -z"
    else
      _nc_supports_z=false
    fi

    # check if nc command supports -v
    if echo "${_nc_features}" | grep -q -e "-v" -e "\[-[0-9a-zA-Z]*v[0-9a-zA-Z]*\]"; then
      _nc_cmd="${_nc_cmd} -v"
    fi

    # check how the address needs to be specified
    if echo "${_nc_features}" | grep -q -E "[|[]IPADDR PORT]"; then
      _nc_cmd="${_nc_cmd} ${_hostname}:${_port}"
    else
      _nc_cmd="${_nc_cmd} ${_hostname} ${_port}"
    fi

    if [ "${_nc_supports_z}" = "false" ]; then
      # -e must be added after the address positional parameter
      _nc_cmd="${_nc_cmd} -e /bin/true"
    fi

    echo "${_nc_cmd}"
  else
    echo "perl -e 'use IO::Socket;
my \$socket=IO::Socket::INET->new(PeerAddr => \"$_hostname\", PeerPort => $_port, Timeout => $_timeout);
if (defined \$socket) {sleep 1; (defined \$socket->connected?exit(0):exit(1))} else {exit(1)}'"

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
if ! command -v "perl" >/dev/null; then
  assert_command_exists nc
fi

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
        *'"'*) # shellcheck disable=SC2089
               command="$command '$arg'" ;;
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
while true; do
  no_errors=true
  last_error_msg=
  last_error_target=
  for target in $targets; do
    hostname=${target%%:*}
    port=${target#*:}
    nc_cmd="$(build_nc_command "$probe_timeout" "$hostname" "$port")"
    printf "=> executing [$nc_cmd]..."
    set +e
    # shellcheck disable=SC2086
    result=$(eval $nc_cmd 2>&1)
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
      echo "ERROR"
      no_errors=false
      last_error_msg=$result
      last_error_target=$target
    else
      echo "OK"
    fi
    set -e
  done

  if [ "$no_errors" = "true" ]; then
    break
  fi

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
  if [ -n "$ZSH_VERSION" ]; then
    # to prevent 'command not found: echo "UP"'
    # shellcheck disable=SC2086,SC2090
    exec ${command%% *} ${command#* }
  else
    # shellcheck disable=SC2086,SC2090
    exec ${command} # using exec so shell process is terminated and signals send by docker deamon are receivable by command
  fi
fi
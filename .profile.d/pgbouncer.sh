#!/usr/bin/env bash
# vim: ft=bash

# @see https://devcenter.heroku.com/articles/buildpack-api#profile-d-scripts
# .profile.d scripts
#
# During startup, the container starts a bash shell that source’s all .sh
# scripts in the .profile.d/ directory before executing the dyno’s command.
# An application’s config vars will already be present in the environment at
# the time the scripts are sourced.
#
# This allows buildpacks to manipulate the initial environment for all dyno
# types in the app. Potential use cases include defining initial config values
# like $PATH by exporting them into the environment, or performing other
# initialization steps necessary during dyno startup.
#
# Like the standard Linux /etc/profile.d shell startup files, these must be
# bash scripts, and their filenames must end in .sh. No guarantee is made regarding the order in which the scripts are sourced.
#
# Scripts in .profile.d/ should only be written by buildpacks. If you need to
# perform application-specific initialization tasks at the time a dyno boots,
# you should use .profile scripts, which are guaranteed to run after the
# scripts in .profile.d/.

export PGBOUNCER_COLOR_DISABLED=${PGBOUNCER_COLOR_DISABLED:-''}
export PGBOUNCER_BINARY="vendor/pgbouncer/bin/pgbouncer"
export PGBOUNCER_PROCESS_REGEX="vendor/pgbouncer/bin/[p]gbouncer"
export PGBOUNCER_CONFIG_FILE="vendor/pgbouncer/pgbouncer.ini"
export PGBOUNCER_POSTGRESQL_PORT=${PGBOUNCER_POSTGRESQL_PORT:-5432}
# how long should we wait for connections to go away before shutting down
export PGBOUNCER_SHUTDOWN_TIMEOUT=${PGBOUNCER_SHUTDOWN_TIMEOUT:-60}
export PGBOUNCER_STDERR=${PGBOUNCER_STDERR:-"vendor/pgbouncer/stderr.log"}

declare -i PGBOUNCER_SERVICE_PID
export PGBOUNCER_SERVICE_PID=

declare RED GRN YLW BLU CLR

function is-enabled() {
  (
    shopt -s extglob nocasematch
    [[ "$1" =~ ^(1|true|yes|on)$ ]]
  )
}

function define-colors() {
  if is-enabled "${PGBOUNCER_COLOR_DISABLED}"; then
    export PUR=''
    export RED=''
    export GRN=''
    export YLW=''
    export BLU=''
    export CLR=''
  else
    export RED='\033[1;37;41m'
    export PUR='\033[1;35m'
    export GRN='\033[0;32m'
    export BLU='\033[0;34m'
    export YLW='\033[1;33m'
    export CLR='\033[0m' # No Color
  fi
}

define-colors

function ts() {
  date '+%Y-%m-%d %T.%3N %Z'
}

function inf() {
  echo -e "${PUR}[$(ts)] ${GRN}INFO:  $*${CLR}"
}

function err() {
  echo -e "${PUR}[$(ts)] ${RED}ERROR: $*${CLR}"
}

function at() {
  inf "${BLU}buildpack=pgbouncer at=$*"
}

function at-status() {
  local status="$1"
  local message="$2"

  case "${status}" in
  enabled)
    at "${GRN}ENABLED  ✔︎ ${message}"
    ;;
  disabled)
    at "${YLW}DISABLED ✖︎ ${message}"
    ;;
  *)
    err "${message}"
    ;;
  esac
}

function is-pgbouncer-service-enabled() {
  if ! is-enabled "${PGBOUNCER_ENABLED}"; then
    at-status disabled pgbouncer-service
    return 1
  else
    at-status enabled pgbouncer-service
    return 0
  fi
}

function pgbouncer-current-pid() {
  /bin/ps -eopid,args | grep -E -e "${PGBOUNCER_PROCESS_REGEX}" | awk '{print $1}'
}

function pgbouncer-get-current-pid() {
  local current_pid
  current_pid=$(pgbouncer-current-pid)

  [[ -n ${current_pid} && ${current_pid} -gt 0 ]] && {
    at "pgbouncer-get-current-pid(): pid=${current_pid}" >&2
    echo -n "${current_pid}"
    return 0
  }

  at "pgbouncer-get-current-pid(): NOT RUNNING" >&2
  return 1
}

config-gen() {
  if [[ -s "${PGBOUNCER_CONFIG_FILE}" ]]; then
    inf "config-gen(): ${PGBOUNCER_CONFIG_FILE} already exists, skipping"
    return
  fi

  # Generate config files
  at "config-gen() start"
  source bin/gen-pgbouncer-conf.sh
  at "config-gen() end"

  # Overwrite config vars with pgbouncer targets
  export POSTGRES_URLS=${PGBOUNCER_URLS:-DATABASE_URL}
}

# @description
#   Returns the number of connections that pgbouncer has established
#   to PostgresSQL
function pgbouncer-current-connections-count() {
  local pid="${1:-$(pgbouncer-get-current-pid)}"

  if command -v lsof >/dev/null; then
    lsof -p ${pid} -a -P -itcp | grep -c ":${PGBOUNCER_POSTGRESQL_PORT} (ESTABLISHED)"
  elif command -v netstat >/dev/null; then
    netstat -an | grep ESTABLISHED | grep -c ":${PGBOUNCER_POSTGRESQL_PORT}"
  else
    err "pgbouncer-current-connections-count(): netstat or lsof were not found, please install them prior to running this buildpacks" >&2
    return 0
  fi
}

# @description
#   Returns # of still established connections to PostgresSQL
#   while reporting that number to the STDERR
function pgbouncer-is-no-longer-connected() {
  local pid="$(pgbouncer-get-current-pid)"

  if [[ -n ${pid} ]]; then
    local connections
    connections=$(pgbouncer-current-connections-count "${pid}")
    if [[ ${connections} -gt 0 ]]; then
      at "is-pgbouncer-connected: pid=${pid} still has ${connections} ESTABLISHED connections" >&2
    else
      at "is-pgbouncer-connected: pid=${pid} is no longer connected to the backend" >&2
    fi
    return ${connections}
  else
    return 0
  fi
}

# @description
#    This function kills pgbouncer service by sending it first SIGINT then
#    SIGKILL
function pgbouncer-stop-the-service() {
  local -i pid
  local -a signals=(INT KILL)
  local -i attempt
  local -i signal_index

  attempt=0

  while pid=$(pgbouncer-get-current-pid) && [[ ${pid} -gt 0 ]]; do
    if [[ ${attempt} -lt ${#signals[@]} ]]; then
      signal_index=$((attempt))
    else
      # after 4th attempt only send KILL
      signal_index=$((${#signals[@]} - 1))
    fi

    local signal=${signals[${signal_index}]}

    at "pgbouncer-stop-the-service(): pid=${pid} (still running) : attempt=${attempt} — sending ${signal}" >&2
    kill -${signal} ${pid}
    sleep $((1 + attempt))

    attempt=$((attempt + 1))
  done

  at "pgbouncer-stop-the-service(): pgbouncer has been shutdown" >&2
  return 0
}

function pgbouncer-initiate-shutdown() {
  local pid="${1:-$(pgbouncer-get-current-pid)}"

  [[ -z ${pid} ]] && return 0

  local -i connections interval total_wait

  interval=1
  total_wait=0

  while true; do
    connections=$(pgbouncer-current-connections-count "${pid}")
    if [[ ${connections} -gt 0 ]]; then
      at "pgbouncer-initiate-shutdown(): pid=${pid} still has ${connections} ESTABLISHED connections, waiting for them to go away..." >&2
      sleep ${interval}
      total_wait=$((total_wait + interval))
    else
      at "pgbouncer-initiate-shutdown(): pid=${pid} is no longer connected to the backend, waited for shutdown: ${total_wait} seconds" >&2
      return 0
    fi
    if [[ ${total_wait} -gt ${PGBOUNCER_SHUTDOWN_TIMEOUT} ]]; then
      break
    fi
  done

  at "pgbouncer-initiate-shutdown(): pid=${pid} exceeded shutdown timeout of ${PGBOUNCER_SHUTDOWN_TIMEOUT}, with ${connections} connections still open." >&2
  pgbouncer-stop-the-service
  return $?
}

# @description
#   Start pgbouncer service and ignore certain signals
function pgbouncer-start-as-a-service() {
  # Do not start the service if PgBouncer is not enabled
  is-pgbouncer-service-enabled || return 1

  config-gen

  trap 'pgbouncer-initiate-shutdown' SIGTERM SIGINT

  if [[ -x ${PGBOUNCER_BINARY} && -s ${PGBOUNCER_CONFIG_FILE} ]]; then
    set -x
    ${PGBOUNCER_BINARY} -d -v "${PGBOUNCER_CONFIG_FILE}" 2>"${PGBOUNCER_STDERR}"
    set +x
  else
    [[ -x ${PGBOUNCER_BINARY} ]] || err "pgbouncer-start-as-a-service(): pgbouncer binary [${PGBOUNCER_BINARY}] is not found, or not executable"
    [[ -s ${PGBOUNCER_CONFIG_FILE} ]] || err "pgbouncer-start-as-a-service(): pgbouncer config file [${PGBOUNCER_CONFIG_FILE}] is not found, or not readable"
    return 1
  fi

  sleep 1

  pgbouncer-get-current-pid || {
    err "pgbouncer-start-as-a-service(): pgbouncer failed to start: [${PGBOUNCER_BINARY} -d -v ${PGBOUNCER_CONFIG_FILE}]"
    [[ -s ${PGBOUNCER_STDERR} ]] && {
      err "pgbouncer-start-as-a-service(): STDERR:"
      cat "${PGBOUNCER_STDERR}"
      rm -f "${PGBOUNCER_STDERR}"
    }
    return 1
  }

  PGBOUNCER_SERVICE_PID=$(pgbouncer-current-pid)
  export PGBOUNCER_SERVICE_PID

  if [[ -n ${PGBOUNCER_SERVICE_PID} && ${PGBOUNCER_SERVICE_PID} -gt 0 ]]; then
    set +e
    at "pgbouncer-start-as-a-service(): pgbouncer started with PID=${PGBOUNCER_SERVICE_PID}"
    return 0
  else
    err "pgbouncer-start-as-a-service(): pgbouncer failed to stay running"
    return 1
  fi
}

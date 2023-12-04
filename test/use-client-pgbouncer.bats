#!/usr/bin/env bats

load helper
load ../.profile.d/pgbouncer.sh

setup() {
  export PGBOUNCER_OUTPUT_URLS=true
  export PGBOUNCER_ENABLED=true
  export PGBOUNCER_URLS="DATABASE_URL REPLICA_DATABASE_URL"
  export PGBOUNCER_URL_NAMES="db-primary db-replica"
  export DATABASE_URL='postgresql://user:pass@host:5432/name?query'
  export REPLICA_DATABASE_URL='postgresql://user:password@neighbours:5432/house?query'
}

teardown() {
  unset PGBOUNCER_OUTPUT_URLS
  unset PGBOUNCER_ENABLED
  unset PGBOUNCER_URLS
  unset PGBOUNCER_URL_NAMES
  unset DATABASE_URL
  unset REPLICA_DATABASE_URL
  unset DATABASE_URL_PGBOUNCER
  unset REPLICA_DATABASE_URL_PGBOUNCER
}

@test "returns success and disables when PGBOUNCER_ENABLED is not true" {
  unset PGBOUNCER_ENABLED
  run source bin/use-client-pgbouncer printenv
  assert_success
  assert_output_contains "DISABLED ✖︎ pgbouncer-service"
  assert_output_contains "ERROR: Client pgBouncer is not enabled, skipping..."
}

@test "returns success and enables when PGBOUNCER_URLS is blank" {
  unset PGBOUNCER_URLS
  run source bin/use-client-pgbouncer printenv
  assert_success
  assert_output_contains "INFO:  Client pgBouncer is enabled"
}

@test "returns success when all variables are properly set" {
  run source bin/use-client-pgbouncer printenv
  assert_success
  assert_output_contains <<EOF
INFO:  Client pgBouncer is enabled
INFO:               DATABASE_URL_PGBOUNCER | postgres://user:********@127.0.0.1:6000/db-primary
INFO:       REPLICA_DATABASE_URL_PGBOUNCER | postgres://user:********@127.0.0.1:6000/db-replica
INFO:  pgBouncer has been configured with 2 database(s).
EOF
}

@test "does not export *_PGBOUNCER urls when PGBOUNCER_VARS_DISABLED is true" {
  export PGBOUNCER_VARS_DISABLED=true
  run source bin/use-client-pgbouncer printenv
  assert_success
  assert_output_contains "INFO:  pgBouncer <VAR>_PGBOUNCER exports are disabled, skipping..."
  refute "${DATABASE_URL_PGBOUNCER}"
}

@test "sets *_PGBOUNCER variables" {
  set -e
  [ -z ${DATABASE_URL_PGBOUNCER} ]
  source bin/use-client-pgbouncer
  assert_equal $DATABASE_URL_PGBOUNCER "postgres://user:pass@host:5433/name?query"
}

@test "does not mutate original database URLs" {
  set -e

  [[ -z ${DATABASE_URL_PGBOUNCER} ]]
  [[ ${DATABASE_URL} == 'postgresql://user:pass@host:5432/name?query' ]]

  source bin/use-client-pgbouncer
  assert_equal $DATABASE_URL_PGBOUNCER "postgres://user:pass@host:5433/name?query"
  assert_equal $DATABASE_URL 'postgresql://user:pass@host:5432/name?query'
}

@test "when no arguments are passed to exec it sets PGBOUNCER_URLS and exits with 0" {
  export DATABASE_URL='postgresql://user:pass@host:5432/name?query'
  export OTHER_URL='postgresql://user:pass@host2:5432/name?query'
  export PGBOUNCER_URLS="DATABASE_URL OTHER_URL"

  source bin/use-client-pgbouncer; main

  [[ -n "${DATABASE_URL_PGBOUNCER}" ]]
  [[ -n "${OTHER_URL_PGBOUNCER}" ]]
}

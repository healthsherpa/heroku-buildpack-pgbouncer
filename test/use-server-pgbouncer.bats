#!/usr/bin/env bats

load helper

@test "returns exit code of 1 with nothing to parse" {
  run bin/use-server-pgbouncer "printenv"
  assert_failure
  assert_output_contains 'buildpack=pgbouncer at=pgbouncer-enabled'
  assert_output_contains 'buildpack=pgbouncer at=setting DATABASE_URL_PGBOUNCER'
}

@test "sets ups DATABASE_URL_PGBOUNCER" {
  export PGBOUNCER_URLS="DATABASE_URL"
  export ORIGINAL_DATABASE_URL='postgresql://user:pass@host:5432/name?query'
  export DATABASE_URL='postgresql://user:pass@host:5432/name?query'
  run bin/use-server-pgbouncer "printenv"
  assert_success
  assert_output_contains 'buildpack=pgbouncer at=pgbouncer-enabled'
  assert_output_contains 'buildpack=pgbouncer at=setting DATABASE_URL_PGBOUNCER'
  assert_output_contains 'buildpack=pgbouncer at=adding-one-to-5432'
  assert_output_contains 'buildpack=pgbouncer at=starting-app'

  assert_output_contains 'DATABASE_URL_PGBOUNCER=postgres://user:pass@host:5433/name?query'
  assert_output_contains 'DATABASE_URL=postgresql://user:pass@host:5432/name?query'
}

@test "substitutes postgres for postgresql in scheme" {
  export PGBOUNCER_URLS="DATABASE_URL"
  export DATABASE_URL='postgresql://user:pass@host:5432/name?query'
  run bin/use-server-pgbouncer "printenv"
  assert_success
  assert_output_contains 'buildpack=pgbouncer at=pgbouncer-enabled'
  assert_output_contains 'buildpack=pgbouncer at=setting DATABASE_URL_PGBOUNCER'
  assert_output_contains 'buildpack=pgbouncer at=adding-one-to-5432'
  assert_output_contains 'buildpack=pgbouncer at=starting-app'

  assert_output_contains 'DATABASE_URL_PGBOUNCER=postgres://user:pass@host:5433/name?query'
  assert_output_contains 'DATABASE_URL=postgresql://user:pass@host:5432/name?query'
}

@test "does not mutate other config vars not listed in PGBOUNCER_URLS" {
  export PGBOUNCER_URLS="DATABASE_URL"
  export DATABASE_URL='postgresql://user:pass@host:5432/name?query'
  export OTHER_URL='postgresql://user:pass@host2:5432/name?query'
  run bin/use-server-pgbouncer "printenv"
  assert_success
  assert_output_contains 'buildpack=pgbouncer at=pgbouncer-enabled'
  assert_output_contains 'buildpack=pgbouncer at=setting DATABASE_URL_PGBOUNCER'
  assert_output_contains 'buildpack=pgbouncer at=adding-one-to-5432'
  assert_output_contains 'buildpack=pgbouncer at=starting-app'

  assert_output_contains 'DATABASE_URL_PGBOUNCER=postgres://user:pass@host:5433/name?query'
  assert_output_contains 'DATABASE_URL=postgresql://user:pass@host:5432/name?query'
  assert_output_contains 'OTHER_URL=postgresql://user:pass@host2:5432/name?query'
}

@test "does not mutates config vars listed in PGBOUNCER_URLS" {
  export DATABASE_URL='postgresql://user:pass@host:5432/name?query'
  export OTHER_URL='postgresql://user:pass@host2:5432/name?query'
  export PGBOUNCER_URLS="DATABASE_URL OTHER_URL"
  run bin/use-server-pgbouncer "printenv"
  assert_success
  assert_output_contains 'buildpack=pgbouncer at=pgbouncer-enabled'
  assert_output_contains 'buildpack=pgbouncer at=setting DATABASE_URL_PGBOUNCER'
  assert_output_contains 'buildpack=pgbouncer at=setting OTHER_URL_PGBOUNCER'
  assert_output_contains 'buildpack=pgbouncer at=adding-one-to-5432'
  assert_output_contains 'buildpack=pgbouncer at=starting-app'
  assert_output_contains 'DATABASE_URL_PGBOUNCER=postgres://user:pass@host:5433/name?query'
  assert_output_contains 'DATABASE_URL=postgresql://user:pass@host:5432/name?query'
  assert_output_contains 'OTHER_URL=postgresql://user:pass@host2:5432/name?query'
}

@test "when no arguments are passed to exec it sets PGBOUNCER_URLS and exits with 0" {
  export DATABASE_URL='postgresql://user:pass@host:5432/name?query'
  export OTHER_URL='postgresql://user:pass@host2:5432/name?query'
  export PGBOUNCER_URLS="DATABASE_URL OTHER_URL"

  source bin/use-server-pgbouncer; main

  [[ -n "${DATABASE_URL_PGBOUNCER}" ]]
  [[ -n "${OTHER_URL_PGBOUNCER}" ]]
}

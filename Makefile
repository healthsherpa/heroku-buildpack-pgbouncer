build: build-heroku-22 build-heroku-24

build-heroku-22:
	@echo "Building pgbouncer in Docker for heroku-22..."
	@docker run -v $(shell pwd):/buildpack --rm -it -e "STACK=heroku-22" -w /buildpack heroku/heroku:22-build support/pgbouncer-build

build-heroku-24:
	@echo "Building pgbouncer in Docker for heroku-24..."
	@docker run -v $(shell pwd):/buildpack --rm -it -e "STACK=heroku-24" -w /buildpack heroku/heroku:24-build support/pgbouncer-build

shell:
	@echo "Opening heroku-24 shell..."
	@docker run -v $(shell pwd):/buildpack --rm -it -e "STACK=heroku-24" -e "PORT=5000" -w /buildpack heroku/heroku:24-build bash

bats:
	@bash -c "command -v brew >/dev/null && { command -v bats  >/dev/null || brew install bats-core || npm install -g bats; } "

test: 	bats
	test/run_all.sh

# Run from inside WSL2 Ubuntu as root, with the repo in the distro's own filesystem (cd ~/Assignment_Day0).
# `make all` takes you from a fresh distro to a verified, mesh-secured 3-tier app.

SHELL := /bin/bash
JOBS  := postgres redis api edge

.PHONY: all setup up down kv build deploy undeploy intentions verify chaos status logs validate help

all: up kv build deploy intentions verify ## full bring-up

setup:        ## one-time: install nomad, consul, CNI plugins, sysctls
	bash scripts/setup-wsl.sh

up:           ## start consul + nomad dev agents
	bash scripts/dev-up.sh

down:         ## stop everything (postgres data survives in /opt/nomad/volumes)
	bash scripts/dev-down.sh

kv:           ## seed Consul KV (db creds, cache TTL) that the job templates read
	bash scripts/seed-kv.sh

build:        ## build the API image Nomad will run
	docker build -t local/api:dev ./api

deploy:       ## run the jobs in dependency order
	@for j in $(JOBS); do nomad job run jobs/$$j.nomad.hcl; done

undeploy:
	@for j in edge api redis postgres; do nomad job stop -purge -yes $$j || true; done

intentions:   ## deny-by-default mesh policy + explicit allows
	bash scripts/apply-intentions.sh

verify:       ## end-to-end curl walkthrough (cache MISS -> HIT -> INVALIDATED, load-balancing)
	bash scripts/verify.sh

chaos:        ## deny api->redis, prove fail-open, restore
	bash scripts/chaos.sh

status:
	@nomad job status; echo; consul catalog services -tags; echo; consul intention list

logs:         ## tail the api task logs of every allocation
	@for a in $$(nomad job allocs -json api | jq -r '.[] | select(.ClientStatus=="running") | .ID'); do \
	  echo "== $$a"; nomad alloc logs -stderr $$a api | tail -20; done

validate:     ## job specs + consul config entries + python, against throwaway dev agents (no docker needed)
	bash scripts/validate.sh

help:
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

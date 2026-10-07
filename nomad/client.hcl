# Layered on top of `nomad agent -dev-connect` by scripts/dev-up.sh.
# Dev mode gives us a single server+client with bridge networking and Consul mesh;
# this file only adds what dev mode cannot infer.
client {
  # Backs the `volume "data"` block in jobs/postgres.nomad.hcl so the database survives
  # job restarts and re-deploys. Created by scripts/setup-wsl.sh.
  host_volume "postgres-data" {
    path      = "/opt/nomad/volumes/postgres-data"
    read_only = false
  }
}

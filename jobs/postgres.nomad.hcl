# Database tier. Reachable ONLY through the Consul service mesh: no host port is
# published, so the only way in is an mTLS connection from an allowed sidecar.
job "postgres" {
  datacenters = ["dc1"]
  type        = "service"

  group "db" {
    count = 1

    network {
      mode = "bridge"
    }

    # Stretch goal: persistent data. Maps to client.host_volume "postgres-data" in nomad/client.hcl.
    volume "data" {
      type      = "host"
      source    = "postgres-data"
      read_only = false
    }

    service {
      name = "postgres"
      port = "5432" # numeric = the port inside the alloc's network namespace that the sidecar forwards to

      connect {
        sidecar_service {}
      }

      check {
        type     = "script"
        task     = "postgres"
        command  = "pg_isready"
        args     = ["-U", "app", "-d", "app"]
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "postgres" {
      driver = "docker"

      config {
        image = "postgres:18-alpine" # verified on Docker Hub 2026-10-07
      }

      # The postgres:18 image moved its data layout: mount the parent dir, not /var/lib/postgresql/data.
      volume_mount {
        volume      = "data"
        destination = "/var/lib/postgresql"
      }

      env {
        POSTGRES_USER = "app"
        POSTGRES_DB   = "app"
      }

      # Stretch goal: secrets come from Consul KV (scripts/seed-kv.sh), not the job file.
      template {
        data        = <<-EOT
          POSTGRES_PASSWORD={{ key "app/db/password" }}
        EOT
        destination = "secrets/db.env"
        env         = true
      }

      resources {
        cpu    = 300
        memory = 256
      }
    }
  }
}

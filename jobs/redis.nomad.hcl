# Cache tier. Like postgres: mesh-only, no host port.
job "redis" {
  datacenters = ["dc1"]
  type        = "service"

  group "cache" {
    count = 1

    network {
      mode = "bridge"
    }

    service {
      name = "redis"
      port = "6379"

      connect {
        sidecar_service {}
      }

      check {
        type     = "script"
        task     = "redis"
        command  = "redis-cli"
        args     = ["ping"]
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "redis" {
      driver = "docker"

      config {
        image = "redis:8.8-alpine" # verified on Docker Hub 2026-10-07
        args = [
          # Behave like a cache: bounded memory, evict least-recently-used keys.
          "--maxmemory", "48mb",
          "--maxmemory-policy", "allkeys-lru",
          # Close idle client connections after 10s so pooled connections from the API
          # are re-established regularly -- that is what makes mesh intention changes
          # (scripts/chaos.sh) take effect within seconds instead of on the next restart.
          "--timeout", "10",
        ]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}

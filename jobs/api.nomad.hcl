# API tier. Two instances (stretch goal), each with its own Envoy sidecar that exposes
# redis and postgres on localhost inside the allocation's network namespace. The app
# never learns where those services actually run.
job "api" {
  datacenters = ["dc1"]
  type        = "service"

  group "api" {
    count = 2

    # Rolling deploys: replace one instance at a time, roll back automatically if the
    # new version never becomes healthy.
    update {
      max_parallel     = 1
      min_healthy_time = "10s"
      healthy_deadline = "3m"
      auto_revert      = true
    }

    network {
      mode = "bridge"
      # No host port at all. The API is mesh-only, like redis and postgres: the only way
      # in is through its sidecar, and clients reach it via jobs/edge.nomad.hcl. With
      # count = 2 on one node, two allocations could not share a host port anyway.
    }

    service {
      name = "api"
      # Numeric = the port inside the alloc's network namespace that the sidecar forwards
      # to. A port *label* here would register the dynamic host port instead, and the
      # sidecar would forward to 127.0.0.1:<host port>, where nothing listens -> 503.
      port = "8000"

      connect {
        sidecar_service {
          proxy {
            upstreams {
              destination_name = "redis"
              local_bind_port  = 6379
            }
            upstreams {
              destination_name = "postgres"
              local_bind_port  = 5432
            }
          }
        }
      }

      check {
        name     = "api-health" # required by expose
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
        # Consul runs checks from the host, and the app has no host port. `expose` makes
        # Nomad add a dynamic port that Envoy forwards to /health on 127.0.0.1:8000 inside
        # the netns, so the check still works without opening the app to the host.
        expose = true
      }
    }

    task "api" {
      driver = "docker"

      config {
        image = "local/api:dev" # built from ./api by `make build`
      }

      # Stretch goal: connection details come from Consul KV via consul-template.
      # 127.0.0.1 is correct here: the sidecar owns those ports in this netns.
      # change_mode = "restart" means editing the KV (e.g. the TTL) rolls the task.
      template {
        data        = <<-EOT
          DATABASE_URL=postgresql://{{ key "app/db/user" }}:{{ key "app/db/password" }}@127.0.0.1:5432/{{ key "app/db/name" }}
          REDIS_URL=redis://127.0.0.1:6379/0
          CACHE_TTL_SECONDS={{ keyOrDefault "app/cache/ttl" "60" }}
        EOT
        destination = "secrets/app.env"
        env         = true
        change_mode = "restart"
      }

      resources {
        cpu    = 300
        memory = 256
      }
    }
  }
}

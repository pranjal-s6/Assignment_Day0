# Ingress. The one thing with a fixed host port (8000). nginx proxies to its own sidecar,
# and the sidecar load-balances across every healthy "api" instance in the mesh --
# so `curl localhost:8000` works exactly as the exercise describes, even with count = 2.
job "edge" {
  datacenters = ["dc1"]
  type        = "service"

  group "edge" {
    count = 1

    network {
      mode = "bridge"
      port "http" {
        static = 8000
        to     = 80
      }
    }

    service {
      name = "edge"
      port = "http"

      connect {
        sidecar_service {
          proxy {
            upstreams {
              destination_name = "api"
              local_bind_port  = 8080
            }
          }
        }
      }

      check {
        type     = "http"
        path     = "/health" # proxied to the api, so edge is only healthy when it can reach an api
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "nginx" {
      driver = "docker"

      config {
        image = "nginx:1.31-alpine" # verified on Docker Hub 2026-10-07
        ports = ["http"]
        # Paths relative to the task dir are always allowed, no docker.volumes.enabled needed.
        volumes = ["local/default.conf:/etc/nginx/conf.d/default.conf:ro"]
      }

      template {
        data        = <<-EOT
          server {
            listen 80;
            location / {
              proxy_pass         http://127.0.0.1:8080;  # -> Envoy upstream "api"
              proxy_http_version 1.1;
              proxy_set_header   Host $host;
              proxy_set_header   X-Forwarded-For $remote_addr;
            }
          }
        EOT
        destination = "local/default.conf"
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}

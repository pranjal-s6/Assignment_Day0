# Only the api may open connections to redis. Enforced by redis's own sidecar (mTLS identity).
Kind = "service-intentions"
Name = "redis"

Sources = [
  {
    Name   = "api"
    Action = "allow"
  }
]

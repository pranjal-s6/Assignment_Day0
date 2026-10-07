# Used by scripts/chaos.sh. Overwrites 20-intentions-redis.hcl with a deny; the script
# restores the allow afterwards.
Kind = "service-intentions"
Name = "redis"

Sources = [
  {
    Name   = "api"
    Action = "deny"
  }
]

# Only the edge ingress may call the api.
Kind = "service-intentions"
Name = "api"

Sources = [
  {
    Name   = "edge"
    Action = "allow"
  }
]

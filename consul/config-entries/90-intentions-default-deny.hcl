# Deny-by-default for the whole mesh. Written LAST (file ordering) so the explicit allows
# above are already in place and nothing is cut off mid-apply. Anything not listed in
# 2x-intentions-*.hcl (e.g. edge -> redis, redis -> postgres) is refused at the sidecar.
Kind = "service-intentions"
Name = "*"

Sources = [
  {
    Name   = "*"
    Action = "deny"
  }
]

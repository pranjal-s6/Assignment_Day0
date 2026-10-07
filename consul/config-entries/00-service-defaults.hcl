# Protocol per service. HTTP services get L7 routing/metrics in Envoy; the data tier is
# plain TCP. Must be written before (or at least independently of) the intentions.
Kind     = "service-defaults"
Name     = "api"
Protocol = "http"

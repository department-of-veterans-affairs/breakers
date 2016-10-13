require 'circuit_breaker/client'
require 'circuit_breaker/outage'
require 'circuit_breaker/service'
require 'circuit_breaker/uptime_middleware'
require 'circuit_breaker/version'

require 'faraday'

module CircuitBreaker
  Faraday::Middleware.register_middleware(circuit_breaker: lambda { UptimeMiddleware })
end

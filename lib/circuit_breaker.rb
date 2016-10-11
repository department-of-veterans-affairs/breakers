require 'circuit_breaker/services'
require 'circuit_breaker/uptime_middleware'
require 'circuit_breaker/version'

require 'faraday'

module CircuitBreaker
  Faraday::Middleware.register_middleware(circuit_breaker: lambda { UptimeMiddleware })
end

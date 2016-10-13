require_relative 'lib/circuit_breaker'
require_relative 'lib/circuit_breaker/dashboard'

require 'redis'

mvi = CircuitBreaker::Service.new(
  name: 'MVI',
  host: /mvi.va.gov/,
  path: /.*/
)

evss = CircuitBreaker::Service.new(
  name: 'EVSS',
  host: /evss.va.gov/,
  path: /.*/
)

client = CircuitBreaker::Client.new(Redis.new, [mvi, evss])

run CircuitBreaker::Dashboard.new(client)

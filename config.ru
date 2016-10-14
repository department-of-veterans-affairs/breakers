require_relative 'lib/breakers'
require_relative 'lib/breakers/dashboard'

require 'redis'

mvi = Breakers::Service.new(
  name: 'MVI',
  host: /mvi.va.gov/,
  path: /.*/
)

evss = Breakers::Service.new(
  name: 'EVSS',
  host: /evss.va.gov/,
  path: /.*/
)

client = Breakers::Client.new(Redis.new, [mvi, evss])

run Breakers::Dashboard.new(client)

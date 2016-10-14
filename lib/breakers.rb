require 'breakers/client'
require 'breakers/outage'
require 'breakers/service'
require 'breakers/uptime_middleware'
require 'breakers/version'

require 'faraday'

module Breakers
  Faraday::Middleware.register_middleware(breakers: lambda { UptimeMiddleware })

  # rubocop:disable Style/AccessorMethodName
  def self.set_client(client)
    @client = client
  end
  # rubocop:enable Style/AccessorMethodName

  def self.new_connection(url_base: nil, adapter: Faraday.default_adapter)
    Faraday.new(url: url_base) do |conn|
      conn.use :breakers, @client
      conn.adapter adapter
    end
  end
end

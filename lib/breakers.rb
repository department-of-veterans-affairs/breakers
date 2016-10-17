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

  def self.client
    @client
  end

  def self.redis_prefix=(prefix)
    @redis_prefix = prefix
  end

  def self.redis_prefix
    @redis_prefix || 'brk-'
  end
end

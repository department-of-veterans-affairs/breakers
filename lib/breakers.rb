require 'breakers/client'
require 'breakers/outage'
require 'breakers/service'
require 'breakers/uptime_middleware'
require 'breakers/version'

require 'faraday'

# Implement the main module for the gem, which includes methods for global configuration
module Breakers
  Faraday::Middleware.register_middleware(breakers: lambda { UptimeMiddleware })

  # Set the global client for use in the middleware
  #
  # @param client [Breakers::Client] the client
  def self.client=(client)
    @client = client
  end

  # Return the global client
  #
  # @return [Breakers::Client] the client
  def self.client
    @client
  end

  # Breakers uses a number of Redis keys to store its data. You can pass an optional
  # prefix here to use for the keys so that they will be namespaced properly. Note that
  # it's also possible to create the Breakers::Client object with a Redis::Namespace
  # object instead, in which case this is unnecessary.
  #
  # @param prefix [String] the prefix
  def self.redis_prefix=(prefix)
    @redis_prefix = prefix
  end

  # Query for the Redis key prefix
  #
  # @return [String] the prefix
  def self.redis_prefix
    @redis_prefix || ''
  end
end

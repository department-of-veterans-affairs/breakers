require 'breakers/client'
require 'breakers/outage'
require 'breakers/outage_exception'
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

  # Set a flag that can globally disable breakers
  #
  # @param value [Boolean] should breakers do its thing globally
  def self.disabled=(value)
    @disabled = value
  end

  # Return the status of global disabling
  #
  # @return [Boolean] is breakers disabled globally
  def self.disabled?
    defined?(@disabled) && @disabled == true
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

  # Configure the middleware's handling of outages. The default is to raise a Breakers::OutageException
  # but you can also request that the response comes back with a configurable status code.
  #
  # @param [Hash] opts A hash of options
  # @option opts [Symbol] :type Pass :exception to raise a Breakers::OutageException when an error occurs. Pass :status_code to respond.
  # @option opts [Integer] :status_code If the type is :status_code, configure which code to return.
  def self.outage_response=(opts)
    @outage_response = { type: :exception }.merge(opts)
  end

  # Query for the outage response configuration
  #
  # @return [Hash] configuration for the outage response, as defined in outage_response=
  def self.outage_response
    @outage_response || { type: :exception }
  end
end

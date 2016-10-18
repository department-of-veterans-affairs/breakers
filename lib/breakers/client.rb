module Breakers
  # The client contains all of the data required to operate Breakers. Creating one and
  # setting it as the global client allows the middleware to operate without parameters
  class Client
    attr_reader :services
    attr_reader :plugins
    attr_reader :redis_connection
    attr_reader :logger

    # Create the Client object.
    #
    # @param redis_connection [Redis] the Redis connection or namespace to use
    # @param services [Breakers::Service] a list of services to be monitored
    # @param plugins [Object] a list of plugins to call as events occur
    # @param logger [Logger] a logger implementing the Ruby Logger interface to call as events occur
    def initialize(redis_connection:, services:, plugins: nil, logger: nil)
      @redis_connection = redis_connection
      @services = Array(services)
      @plugins = Array(plugins)
      @logger = logger
    end

    # Given a request environment, return the service that should handle it.
    #
    # @param request_env [Faraday::Env] the request environment
    # @return [Breakers::Service] the service object
    def service_for_request(request_env:)
      @services.find do |service|
        service.handles_request?(request_env: request_env)
      end
    end
  end
end

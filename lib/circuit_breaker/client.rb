module CircuitBreaker
  class Client
    attr_reader :services
    attr_reader :plugins
    attr_reader :redis_connection
    attr_reader :logger

    def initialize(redis_connection:, services:, plugins: nil, logger: nil)
      @redis_connection = redis_connection
      @services = Array(services)
      @plugins = Array(plugins)
      @logger = logger
      @services.each { |s| s.client = self }
    end

    def service_for_url(url:)
      @services.find do |service|
        url.host =~ service.host && url.path =~ service.path
      end
    end

    def service_for_uri_name(name:)
      @services.find do |service|
        service.uri_name == name
      end
    end
  end
end

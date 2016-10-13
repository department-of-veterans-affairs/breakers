module CircuitBreaker
  class Client
    attr_reader :services

    def initialize(redis_connection, services)
      @redis_connection = redis_connection
      @services = services
      @services.each { |s| s.redis_connection = @redis_connection }
    end

    def service_for_url(url)
      @services.find do |service|
        url.host =~ service.host && url.path =~ service.path
      end
    end

    def service_for_uri_name(name)
      @services.find do |service|
        service.uri_name == name
      end
    end
  end
end

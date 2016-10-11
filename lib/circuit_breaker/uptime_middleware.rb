require 'faraday'
require 'multi_json'

module CircuitBreaker
  class UptimeMiddleware < Faraday::Middleware
    def initialize(app, redis_connection, services)
      super(app)
      @redis_connection = redis_connection
      @services = services
    end

    def call(request_env)
      service = @services.find(request_env.url)
      last_outage = @redis_connection.zrange("cb-#{service[:name]}-outages", -1, -1)[0]
      if last_outage
        data = MultiJson.load(last_outage)
        if !data.key?('end_time')
          response = Faraday::Response.new
          response.finish(status: 503, body: 'Outage detected', response_headers: {})
          return response
        end
      end

      @app.call(request_env).on_complete do |response_env|
        if response_env.status >= 500
          apply_to_service(service, 'errors', issue: 'status', status: 500)
        end
      end
    rescue Faraday::TimeoutError
      apply_to_service(service, 'errors', issue: 'timeout')
    end

    protected

    def apply_to_service(service, list_name, data)
      if service
        @redis_connection.zadd("cb-#{service[:name]}-#{list_name}", Time.now.to_i, MultiJson.dump(data))
      end
    end
  end
end

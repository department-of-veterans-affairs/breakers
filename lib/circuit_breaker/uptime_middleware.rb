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
      last_outage = find_last_outage(service)

      if last_outage && !last_outage.over?
        if last_outage.ready_for_retest?
          lock = RetestLock.new(service, @redis_connection)
          if lock.acquire
            begin
            ensure
              lock.release
            end
          else
            return outage_response(last_outage, service)
          end
        else
          return outage_response(last_outage, service)
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

    def find_last_outage(service)
      data = @redis_connection.zrange("cb-#{service[:name]}-outages", -1, -1)[0]
      data && Outage.new(data)
    end

    def outage_response(outage, service)
      Faraday::Response.new.tap do |response|
        response.finish(
          status: 503,
          body: "Outage detected on #{service[:name]} beginning at #{outage.start_time.to_i}",
          response_headers: {}
        )
      end
    end
  end
end

require 'faraday'
require 'multi_json'

module CircuitBreaker
  class UptimeMiddleware < Faraday::Middleware
    def initialize(app, client)
      super(app)
      @client = client
    end

    def call(request_env)
      service = @client.service_for_url(request_env.url)
      last_outage = service.last_outage

      if last_outage && !last_outage.ended?
        if last_outage.ready_for_retest?
          handle_request(service, request_env, last_outage)
        else
          outage_response(last_outage, service)
        end
      else
        handle_request(service, request_env, nil)
      end
    end

    protected

    def outage_response(outage, service)
      Faraday::Response.new.tap do |response|
        response.finish(
          status: 503,
          body: "Outage detected on #{service.name} beginning at #{outage.start_time.to_i}",
          response_headers: {}
        )
      end
    end

    def handle_request(service, request_env, outage)
      return @app.call(request_env).on_complete do |response_env|
        if response_env.status >= 500
          service.add_error
        else
          service.add_success
          outage&.end!
        end
      end
    rescue Faraday::TimeoutError
      service.add_error
    end
  end
end

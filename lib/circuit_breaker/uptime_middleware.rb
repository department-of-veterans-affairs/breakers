require 'faraday'
require 'multi_json'

module CircuitBreaker
  class UptimeMiddleware < Faraday::Middleware
    def initialize(app, client)
      super(app)
      @client = client
    end

    def call(request_env)
      service = @client.service_for_url(url: request_env.url)
      last_outage = service.last_outage

      if last_outage && !last_outage.ended?
        if last_outage.ready_for_retest?
          handle_request(service: service, request_env: request_env, current_outage: last_outage)
        else
          outage_response(outage: last_outage, service: service)
        end
      else
        handle_request(service: service, request_env: request_env)
      end
    end

    protected

    def outage_response(outage:, service:)
      Faraday::Response.new.tap do |response|
        response.finish(
          status: 503,
          body: "Outage detected on #{service.name} beginning at #{outage.start_time.to_i}",
          response_headers: {}
        )
      end
    end

    def handle_request(service:, request_env:, current_outage: nil)
      return @app.call(request_env).on_complete do |response_env|
        if response_env.status >= 500
          service.add_error
          @client.logger.warn(
            msg: 'CircuitBreaker failed request',
            service: service.name,
            url: request_env.url.to_s,
            error: response_env.status
          )
        else
          service.add_success
          current_outage&.end!
        end
      end
    rescue Faraday::TimeoutError
      service.add_error
      @client.logger.warn(
        msg: 'CircuitBreaker failed request',
        service: service.name,
        url: request_env.url.to_s,
        error: 'timeout'
      )
    end
  end
end

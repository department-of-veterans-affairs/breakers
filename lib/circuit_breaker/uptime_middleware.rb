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

      if !service
        return @app.call(request_env)
      end

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
          handle_error(
            service: service,
            request_env: request_env,
            response_env: response_env,
            error: response_env.status,
            current_outage: current_outage
          )
        else
          service.add_success
          current_outage&.end!

          @client.plugins.each do |plugin|
            plugin.on_success(service, request_env, response_env) if plugin.respond_to?(:on_success)
          end
        end
      end
    rescue Faraday::TimeoutError
      handle_error(
        service: service,
        request_env: request_env,
        response_env: nil,
        error: 'timeout',
        current_outage: current_outage
      )
    end

    def handle_error(service:, request_env:, response_env:, error:, current_outage: nil)
      service.add_error
      current_outage&.update_last_test_time!

      @client.logger&.warn(
        msg: 'CircuitBreaker failed request',
        service: service.name,
        url: request_env.url.to_s,
        error: error
      )
      @client.plugins.each do |plugin|
        plugin.on_error(service, request_env, response_env) if plugin.respond_to?(:on_error)
      end
    end
  end
end

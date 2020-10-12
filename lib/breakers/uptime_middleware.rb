require 'faraday'
require 'multi_json'

module Breakers
  # The faraday middleware
  class UptimeMiddleware < Faraday::Middleware
    def initialize(app)
      super(app)
    end

    def call(request_env)
      if Breakers.disabled?
        return @app.call(request_env)
      end

      service = Breakers.client.service_for_request(request_env: request_env)

      if !service
        return @app.call(request_env)
      end

      latest_outage = service.latest_outage

      if latest_outage && !latest_outage.ended?
        if latest_outage.ready_for_retest?(wait_seconds: service.seconds_before_retry)
          handle_request(service: service, request_env: request_env, current_outage: latest_outage)
        else
          outage_response(outage: latest_outage, service: service)
        end
      else
        handle_request(service: service, request_env: request_env)
      end
    end

    protected

    def outage_response(outage:, service:)
      Breakers.client.plugins.each do |plugin|
        plugin.on_skipped_request(service) if plugin.respond_to?(:on_skipped_request)
      end
      if Breakers.outage_response[:type] == :status_code
        Faraday::Response.new.tap do |response|
          response.finish(
            status: Breakers.outage_response[:status_code],
            body: "Outage detected on #{service.name} beginning at #{outage.start_time.to_i}",
            response_headers: {}
          )
        end
      else
        raise Breakers::OutageException.new(outage, service)
      end
    end

    def handle_request(service:, request_env:, current_outage: nil)
      start_time = Time.now
      return @app.call(request_env).on_complete do |response_env|
        response_env[:duration] = (Time.now - start_time) * 1000
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

          Breakers.client.plugins.each do |plugin|
            plugin.on_success(service, request_env, response_env) if plugin.respond_to?(:on_success)
          end
        end
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      handle_error(
        service: service,
        request_env: request_env,
        response_env: nil,
        error: "#{e.class.name} - #{e.message}",
        current_outage: current_outage
      )
      raise
    rescue => e
      if service.exception_represents_server_error?(e)
        handle_error(
          service: service,
          request_env: request_env,
          response_env: nil,
          error: "#{e.class.name} - #{e.message}",
          current_outage: current_outage
        )
      end
      raise
    end

    def handle_error(service:, request_env:, response_env:, error:, current_outage: nil)
      service.add_error
      current_outage&.update_last_test_time!

      Breakers.client.logger&.warn(
        msg: 'Breakers failed request',
        service: service.name,
        url: request_env.url.to_s,
        error: error
      )
      Breakers.client.plugins.each do |plugin|
        plugin.on_error(service, request_env, response_env) if plugin.respond_to?(:on_error)
      end
    end
  end
end

# frozen_string_literal: true

# spec/uptime_middleware_spec.rb

require "spec_helper"
require "breakers/uptime_middleware"

RSpec.describe Breakers::UptimeMiddleware do # rubocop:disable Metrics/BlockLength
  let(:redis) { Redis.new }
  let(:service) do
    Breakers::Service.new(
      name: "VA",
      request_matcher: proc { |_breakers_service, request_env, _request_service_name|
        request_env.url.host =~ /.*va.gov/
      },
      seconds_before_retry: 60,
      error_threshold: 50
    )
  end
  let(:logger) { Logger.new(nil) }
  let(:plugin) { ExamplePlugin.new }
  let(:client) do
    Breakers::Client.new(
      redis_connection: redis,
      services: [service],
      logger: logger,
      plugins: [plugin]
    )
  end
  let(:connection) do
    Faraday.new("http://va.gov") do |conn|
      conn.use(:breakers, service_name: "VA")
      conn.adapter Faraday.default_adapter
    end
  end
  let(:request_env) do
    {
      service: service,
      method: :get,
      # This is the URL that the middleware will use to check uptime
      url: "http://va.gov/uptime",
      request_headers: { params: {} }
    }
  end
  let(:middleware) { described_class.new(client, { connection: connection, service_name: service.name }) }
  let(:outage) do
    Breakers::Outage.new(service: service, body: JSON.generate(start_time: Time.now, end_time: nil))
  end
  let(:forced_outage) do
    Breakers::Outage.new(service: service, body: JSON.generate(start_time: Time.now, end_time: nil, forced: true))
  end
  before do
    Breakers.outage_response = { type: :status_code, status_code: 503 }
    Breakers.client = client
  end

  context "with a 500" do # rubocop:disable Metrics/BlockLength
    let(:now) { Time.now.utc }
    let(:log) do
      {
        msg: "message",
        service: service.name,
        outage: outage,
        forced: outage&.forced?
      }
    end
    let(:log_forced_outage) do
      {
        msg: "message",
        service: service.name,
        outage: outage,
        forced: outage&.forced?
      }
    end
    before do
      Timecop.freeze(now)
      stub_request(:get, "va.gov").to_return(status: 500)
    end

    it "creates an outage" do
      connection.get "/"
      expect(service.latest_outage).to be
    end

    it "#call logs and returns on a regular outage" do
      middleware.send(:log_if_forced, latest_outage: outage, message: "test message")
    rescue StandardError => e
      expect(e).to eq(nil)
      expect(Rails.logger).to have_received(:info).with(log)
    end

    it "#call logs and returns on a forced outage" do
      middleware.send(:log_if_forced, latest_outage: forced_outage, message: "test message")
    rescue StandardError => e
      expect(e).to eq(nil)
      expect(Rails.logger).to have_received(:info).with(log_forced_outage)
    end
  end
end

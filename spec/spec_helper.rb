$LOAD_PATH.unshift File.expand_path('../lib', __FILE__)

require 'active_support/all'
require 'byebug'
require 'fakeredis/rspec'
require 'faraday'
require 'rspec'
require 'simplecov'
require 'timecop'
require 'webmock/rspec'

SimpleCov.start do
  minimum_coverage 85
end

WebMock.disable_net_connect!

require 'circuit_breaker'

# These two modules slavishly borrowed from the Faraday Middleware gem
module EnvCompatibility
  def faraday_env(env)
    if defined?(Faraday::Env)
      Faraday::Env.from(env)
    else
      env
    end
  end
end

module MiddlewareExampleGroup
  def self.included(base)
    base.let(:options) { Hash.new }
    base.let(:headers) { Hash.new }
  end

  def process(body, content_type = nil, options = {})
    env = {
      body: body,
      request: options,
      request_headers: Faraday::Utils::Headers.new,
      response_headers: Faraday::Utils::Headers.new(headers)
    }
    env[:response_headers]['content-type'] = content_type if content_type
    yield(env) if block_given?
    middleware.call(faraday_env(env))
  end
end

RSpec.configure do |config|
  config.include EnvCompatibility
  config.include MiddlewareExampleGroup
end

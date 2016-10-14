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
  minimum_coverage 95
end

WebMock.disable_net_connect!(allow: '127.0.0.1')

require 'circuit_breaker'

require_relative 'example_plugin'

require 'uri'

module Breakers
  class Service
    DEFAULT_OPTS = {
      seconds_before_retry: 60,
      error_threshold: 50,
      data_retention_seconds: 60 * 60 * 24 * 30
    }.freeze

    def initialize(opts)
      @configuration = DEFAULT_OPTS.merge(opts)
    end

    def name
      @configuration[:name]
    end

    def handles_request?(request_env)
      @configuration[:request_matcher].call(request_env)
    end

    def seconds_before_retry
      @configuration[:seconds_before_retry]
    end

    def add_error
      increment_key(key: errors_key)
      maybe_create_outage
    end

    def add_success
      increment_key(key: successes_key)
    end

    def last_outage
      Outage.find_last(service: self)
    end

    def outages_in_range(start_time:, end_time:)
      Outage.in_range(
        service: self,
        start_time: start_time,
        end_time: end_time
      )
    end

    def successes_in_range(start_time:, end_time:)
      values_in_range(start_time: start_time, end_time: end_time, type: :successes)
    end

    def errors_in_range(start_time:, end_time:)
      values_in_range(start_time: start_time, end_time: end_time, type: :errors)
    end

    def uri_name
      URI.escape(name)
    end

    protected

    def errors_key(time: nil)
      "cb-#{name}-errors-#{align_time_on_minute(time: time).to_i}"
    end

    def successes_key(time: nil)
      "cb-#{name}-successes-#{align_time_on_minute(time: time).to_i}"
    end

    def values_in_range(start_time:, end_time:, type:, sample_seconds: 3600)
      start_time = align_time_on_minute(time: start_time)
      end_time = align_time_on_minute(time: end_time)
      keys = []
      times = []
      while start_time < end_time
        times << start_time
        if type == :errors
          keys << errors_key(time: start_time)
        elsif type == :successes
          keys << successes_key(time: start_time)
        end
        start_time += sample_seconds
      end
      Breakers.client.redis_connection.mget(keys).each_with_index.map do |value, idx|
        { count: value.to_i, time: times[idx] }
      end
    end

    def increment_key(key:)
      Breakers.client.redis_connection.multi do
        Breakers.client.redis_connection.incr(key)
        Breakers.client.redis_connection.expire(key, @configuration[:data_retention_seconds])
      end
    end

    # Take the current or given time and round it down to the nearest minute
    def align_time_on_minute(time: nil)
      time = (time || Time.now).to_i
      time - (time % 60)
    end

    def maybe_create_outage
      data = Breakers.client.redis_connection.multi do
        Breakers.client.redis_connection.get(errors_key(time: Time.now))
        Breakers.client.redis_connection.get(errors_key(time: Time.now - 60))
        Breakers.client.redis_connection.get(successes_key(time: Time.now))
        Breakers.client.redis_connection.get(successes_key(time: Time.now - 60))
      end
      failure_count = data[0].to_i + data[1].to_i
      success_count = data[2].to_i + data[3].to_i

      if failure_count > 0 && success_count == 0
        Outage.create(service: self)
      else
        failure_rate = failure_count / (failure_count + success_count).to_f
        if failure_rate >= @configuration[:error_threshold] / 100.0
          Outage.create(service: self)
        end
      end
    end
  end
end

require 'uri'

module CircuitBreaker
  class Service
    attr_reader :name
    attr_reader :host
    attr_reader :path
    attr_accessor :redis_connection

    ONE_MONTH = 60 * 60 * 24 * 30

    def initialize(name:, host:, path:)
      @name = name
      @host = host
      @path = path
    end

    def add_error
      increment_key(errors_key)
      maybe_create_outage
    end

    def add_success
      increment_key(successes_key)
    end

    def last_outage
      Outage.find_last(@redis_connection, self)
    end

    def outages_in_range(start_time:, end_time:)
      Outage.in_range(
        service: self,
        start_time: start_time,
        end_time: end_time,
        redis: @redis_connection
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

    def errors_key(time = nil)
      "cb-#{name}-errors-#{align_time_on_minute(time).to_i}"
    end

    def successes_key(time = nil)
      "cb-#{name}-successes-#{align_time_on_minute(time).to_i}"
    end

    def values_in_range(start_time:, end_time:, type:)
      start_time = align_time_on_minute(start_time)
      end_time = align_time_on_minute(end_time)
      keys = []
      times = []
      while start_time < end_time
        times << start_time
        if type == :errors
          keys << errors_key(start_time)
        elsif type == :successes
          keys << successes_key(start_time)
        end
        start_time += 3600
      end
      @redis_connection.mget(keys).each_with_index.map do |value, idx|
        { count: value.to_i, time: times[idx] }
      end
    end

    def increment_key(key)
      @redis_connection.multi do
        @redis_connection.incr(key)
        @redis_connection.expire(key, ONE_MONTH)
      end
    end

    # Take the current or given time and round it down to the nearest minute
    def align_time_on_minute(time = nil)
      time = (time || Time.now).to_i
      time - (time % 60)
    end

    def maybe_create_outage
      data = @redis_connection.multi do
        @redis_connection.get(errors_key(Time.now))
        @redis_connection.get(errors_key(Time.now - 60))
        @redis_connection.get(successes_key(Time.now))
        @redis_connection.get(successes_key(Time.now - 60))
      end
      failure_count = data[0].to_i + data[1].to_i
      success_count = data[2].to_i + data[3].to_i

      if failure_count > 0 && success_count == 0
        Outage.create(@redis_connection, self)
      else
        failure_rate = failure_count / (failure_count + success_count).to_f
        if failure_rate >= 0.5
          Outage.create(@redis_connection, self)
        end
      end
    end
  end
end

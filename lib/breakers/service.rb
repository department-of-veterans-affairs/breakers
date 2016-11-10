module Breakers
  # A service defines a backend system that your application relies upon. This class
  # allows you to configure the outage detection for a service as well as to define which
  # requests belong to it.
  class Service
    DEFAULT_OPTS = {
      seconds_before_retry: 60,
      error_threshold: 50,
      data_retention_seconds: 60 * 60 * 24 * 30
    }.freeze

    # Create a new service
    #
    # @param [Hash] opts the options to create the service with
    # @option opts [String] :name The name of the service for reporting and logging purposes
    # @option opts [Proc] :request_matcher A proc taking a Faraday::Env as an argument that returns true if the service handles that request
    # @option opts [Integer] :seconds_before_retry The number of seconds to wait after an outage begins before testing with a new request
    # @option opts [Integer] :error_threshold The percentage of errors over the last two minutes that indicates an outage
    # @option opts [Integer] :data_retention_seconds The number of seconds to retain success and error data in Redis
    # @option opts [Proc] :exception_handler A proc taking an exception and returns true if it represents an error on the service
    def initialize(opts)
      @configuration = DEFAULT_OPTS.merge(opts)
    end

    # Get the name of the service
    #
    # @return [String] the name
    def name
      @configuration[:name]
    end

    # Given a Faraday::Env, return true if this service handles the request, via its matcher
    #
    # @param request_env [Faraday::Env] the request environment
    # @return [Boolean] should the service handle the request
    def handles_request?(request_env:)
      @configuration[:request_matcher].call(request_env)
    end

    # Get the seconds before retry parameter
    #
    # @return [Integer] the value
    def seconds_before_retry
      @configuration[:seconds_before_retry]
    end

    # Returns true if a given exception represents an error with the service
    #
    # @return [Boolean] is it an error?
    def exception_represents_server_error?(exception)
      @configuration[:exception_handler]&.call(exception)
    end

    # Indicate that an error has occurred and potentially create an outage
    def add_error
      increment_key(key: errors_key)
      maybe_create_outage
    end

    # Indicate that a successful response has occurred
    def add_success
      increment_key(key: successes_key)
    end

    # Force an outage to begin on the service. Forced outages are not periodically retested.
    def begin_forced_outage!
      Outage.create(service: self, forced: true)
    end

    # End a forced outage on the service.
    def end_forced_outage!
      latest = Outage.find_latest(service: self)
      if latest.forced?
        latest.end!
      end
    end

    # Return the most recent outage on the service
    def latest_outage
      Outage.find_latest(service: self)
    end

    # Return a list of all outages in the given time range
    #
    # @param start_time [Time] the beginning of the range
    # @param end_time [Time] the end of the range
    # @return [Array[Outage]] a list of outages that began in the range
    def outages_in_range(start_time:, end_time:)
      Outage.in_range(
        service: self,
        start_time: start_time,
        end_time: end_time
      )
    end

    # Return data about the successful request counts in the time range
    #
    # @param start_time [Time] the beginning of the range
    # @param end_time [Time] the end of the range
    # @param sample_minutes [Integer] the rate at which to sample the data
    # @return [Array[Hash]] a list of hashes in the form: { count: Integer, time: Unix Timestamp }
    def successes_in_range(start_time:, end_time:, sample_minutes: 60)
      values_in_range(start_time: start_time, end_time: end_time, type: :successes, sample_minutes: sample_minutes)
    end

    # Return data about the failed request counts in the time range
    #
    # @param start_time [Time] the beginning of the range
    # @param end_time [Time] the end of the range
    # @param sample_minutes [Integer] the rate at which to sample the data
    # @return [Array[Hash]] a list of hashes in the form: { count: Integer, time: Unix Timestamp }
    def errors_in_range(start_time:, end_time:, sample_minutes: 60)
      values_in_range(start_time: start_time, end_time: end_time, type: :errors, sample_minutes: sample_minutes)
    end

    protected

    def errors_key(time: nil)
      "#{Breakers.redis_prefix}#{name}-errors-#{align_time_on_minute(time: time).to_i}"
    end

    def successes_key(time: nil)
      "#{Breakers.redis_prefix}#{name}-successes-#{align_time_on_minute(time: time).to_i}"
    end

    def values_in_range(start_time:, end_time:, type:, sample_minutes:)
      start_time = align_time_on_minute(time: start_time)
      end_time = align_time_on_minute(time: end_time)
      keys = []
      times = []
      while start_time <= end_time
        times << start_time
        if type == :errors
          keys << errors_key(time: start_time)
        elsif type == :successes
          keys << successes_key(time: start_time)
        end
        start_time += sample_minutes * 60
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
      time = (time || Time.now.utc).to_i
      time - (time % 60)
    end

    def maybe_create_outage
      data = Breakers.client.redis_connection.multi do
        Breakers.client.redis_connection.get(errors_key(time: Time.now.utc))
        Breakers.client.redis_connection.get(errors_key(time: Time.now.utc - 60))
        Breakers.client.redis_connection.get(successes_key(time: Time.now.utc))
        Breakers.client.redis_connection.get(successes_key(time: Time.now.utc - 60))
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

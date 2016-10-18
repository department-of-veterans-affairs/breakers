require 'multi_json'

module Breakers
  # A class defining an outage on a service
  class Outage
    attr_reader :service
    attr_reader :body

    # Return the most recent outage on the given service
    #
    # @param service [Breakers::Service] the service to look in
    # @return [Breakers::Outage] the most recent outage, or nil
    def self.find_latest(service:)
      data = Breakers.client.redis_connection.zrange(outages_key(service: service), -1, -1)[0]
      data && new(service: service, body: data)
    end

    # Return all of the outages on the given service that begin in the time range
    #
    # @param service [Breakers::Service] the service to look in
    # @param start_time [Time] the beginning of the time range
    # @param end_time [Time] the end of the time range
    # @return [Breakers::Outage] a list of the outages in the range
    def self.in_range(service:, start_time:, end_time:)
      data = Breakers.client.redis_connection.zrangebyscore(
        outages_key(service: service),
        start_time.to_i,
        end_time.to_i
      )
      data.map { |item| new(service: service, body: item) }
    end

    # Create a new outage on the given service
    #
    # @param service [Breakers::Service] the service to create it for
    # @param forced [Boolean] is the service forced, or created via the middleware
    # @return [Breakers::Outage] the new outage
    def self.create(service:, forced: false)
      data = MultiJson.dump(start_time: Time.now.utc.to_i, forced: forced)
      Breakers.client.redis_connection.zadd(outages_key(service: service), Time.now.utc.to_i, data)

      Breakers.client.logger&.error(msg: 'Breakers outage beginning', service: service.name, forced: forced)

      Breakers.client.plugins.each do |plugin|
        plugin.on_outage_begin(Outage.new(service: service, body: data)) if plugin.respond_to?(:on_outage_begin)
      end
    end

    # Get the key for storing the outage data in Redis for this service
    #
    # @param service [Breakers::Service] the service
    # @return [String] the Redis key
    def self.outages_key(service:)
      "#{Breakers.redis_prefix}#{service.name}-outages"
    end

    # Create a new outage
    #
    # @param service [Breakers::Service] the service the outage is for
    # @param body [Hash] the data to store in the outage, with keys start_time, end_time, last_test_time, and forced
    # @return [Breakers::Outage] the new outage
    def initialize(service:, body:)
      @body = MultiJson.load(body)
      @service = service
    end

    # Check to see if the outage has ended
    #
    # @return [Boolean] the status
    def ended?
      @body.key?('end_time')
    end

    # Was the outage forced?
    #
    # @return [Boolean] the status
    def forced?
      @body['forced']
    end

    # Tell the outage to end, which will allow requests to begin flowing again
    def end!
      new_body = @body.dup
      new_body['end_time'] = Time.now.utc.to_i
      replace_body(body: new_body)

      Breakers.client.logger&.info(msg: 'Breakers outage ending', service: @service.name, forced: forced?)
      Breakers.client.plugins.each do |plugin|
        plugin.on_outage_end(self) if plugin.respond_to?(:on_outage_begin)
      end
    end

    # Get the time at which the outage started
    #
    # @return [Time] the time
    def start_time
      @body['start_time'] && Time.at(@body['start_time']).utc
    end

    # Get the time at which the outage ended
    #
    # @return [Time] the time
    def end_time
      @body['end_time'] && Time.at(@body['end_time']).utc
    end

    # Get the time at which the outage last received a new request
    #
    # @return [Time] the time
    def last_test_time
      (@body['last_test_time'] && Time.at(@body['last_test_time']).utc) || start_time
    end

    # Update the last test time to now
    def update_last_test_time!
      new_body = @body.dup
      new_body['last_test_time'] = Time.now.utc.to_i
      replace_body(body: new_body)
    end

    # Check to see if the outage should be retested to make sure it's still ongoing
    #
    # @return [Boolean] is it ready?
    def ready_for_retest?(wait_seconds:)
      (Time.now.utc - last_test_time) > wait_seconds
    end

    protected

    def key
      "#{Breakers.redis_prefix}#{@service.name}-outages"
    end

    def replace_body(body:)
      Breakers.client.redis_connection.multi do
        Breakers.client.redis_connection.zrem(key, MultiJson.dump(@body))
        Breakers.client.redis_connection.zadd(key, start_time.to_i, MultiJson.dump(body))
      end
      @body = body
    end
  end
end

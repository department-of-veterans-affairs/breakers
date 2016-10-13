require 'multi_json'

module CircuitBreaker
  class Outage
    def self.find_last(redis, service)
      data = redis.zrange("cb-#{service.name}-outages", -1, -1)[0]
      data && new(data, service, redis)
    end

    def self.in_range(service:, start_time:, end_time:, redis:)
      data = redis.zrangebyscore(
        "cb-#{service.name}-outages",
        start_time.to_i,
        end_time.to_i
      )
      data.map { |item| new(item, service, redis) }
    end

    def self.create(redis, service)
      data = MultiJson.dump(start_time: Time.now.to_i)
      redis.zadd("cb-#{service.name}-outages", Time.now.to_i, data)
    end

    def initialize(data, service, redis_connection)
      @body = MultiJson.load(data)
      @service = service
      @redis_connection = redis_connection
    end

    def to_json(*options)
      @body.to_json(*options)
    end

    def ended?
      @body.key?('end_time')
    end

    def end!
      new_body = { 'start_time' => start_time.to_i, 'end_time' => Time.now.to_i }
      key = "cb-#{@service.name}-outages"
      @redis_connection.multi do
        @redis_connection.zrem(key, MultiJson.dump(@body))
        @redis_connection.zadd(key, start_time.to_i, MultiJson.dump(new_body))
      end
      @body = new_body
    end

    def start_time
      Time.at(@body['start_time'])
    end

    def end_time
      Time.at(@body['end_time'])
    end

    def last_test_time
      (@body['last_test_time'] && Time.at(@body['last_test_time'])) || start_time
    end

    def ready_for_retest?
      (Time.now - last_test_time) > 60
    end

  end
end

require 'multi_json'

module CircuitBreaker
  class Outage
    def self.find_last(redis, service)
      data = @redis_connection.zrange("cb-#{service[:name]}-outages", -1, -1)[0]
      data && new(data)
    end

    def initialize(data)
      @body = MultiJson.load(data)
    end

    def over?
      @body.key?('end_time')
    end

    def start_time
      Time.at(@body['start_time'])
    end

    def last_test_time
      (@body['last_test_time'] && Time.at(@body['last_test_time'])) || start_time
    end

    def ready_for_retest?
      (Time.now - last_test_time) > 60
    end
  end
end

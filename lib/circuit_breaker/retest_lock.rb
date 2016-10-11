module CircuitBreaker
  class RetestLock
    def initialize(service, redis)
      @service = service
      @redis = redis
    end

    def acquire
      if @redis.setnx(key, 1) == 1
        @redis.expire(key, 120)
        return true
      end
      false
    end

    def release
      @redis.del(key)
    end

    protected

    def key
      "cb-#{@service[:name]}-retry-lock"
    end
  end
end

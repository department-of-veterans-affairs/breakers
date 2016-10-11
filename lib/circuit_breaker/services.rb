module CircuitBreaker
  class Services
    def initialize
      @services = []
    end

    def add_service(opts)
      if opts[:name] && opts[:host] && opts[:path]
        @services << opts
      else
        raise ArgumentError, 'service requires :name, :host, and :path options'
      end
    end

    def find(url)
      @services.find do |service|
        url.host =~ service[:host] && url.path =~ service[:path]
      end
    end
  end
end

module Breakers
  # The error that is raised when a request is made against a service that is
  # experiencing an outage
  class OutageException < StandardError
    attr_reader :outage
    attr_reader :service

    def initialize(outage, service)
      @outage = outage
      @service = service
    end

    def message
      "Outage detected on #{@service.name} beginning at #{@outage.start_time.to_i}"
    end
  end
end

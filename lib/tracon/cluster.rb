module Tracon
  class Cluster
    attr_accessor :domain
    attr_accessor :qualified_name

    def initialize(domain, qualified_name)
      @domain = domain
      # The cluster name, possibly qualified with a hash such as when launched
      # by Flight Launch.
      @qualified_name = qualified_name
    end

    def name
      cluster_data[:parameters]['ClusterName'] || @qualified_name
    end

    def uuid
      cluster_data[:configuration_result]['UUID']
    end

    def scheduler_type
      cluster_data[:parameters]['SchedulerType']
    end

    def flight_profile_bucket
      cluster_data[:parameters]['FlightProfileBucket']
    end

    def cu_in_use
      queues.reduce(0) do |memo, queue|
        memo += queue.current_cu
      end
    end

    def cu_max
      @cu_max ||= cluster_data[:tags]['flight:quota'].to_i
    end

    def queues
      @queues ||= AWS.queues(@domain, @qualified_name).map do |queue_data|
        Queue.new(queue_data[:spec], self, queue_data)
      end
    end

    private
    def cluster_data
      @cluster_data ||= AWS.cluster(@domain, @qualified_name)
    end
  end
end

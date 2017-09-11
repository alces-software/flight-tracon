module Tracon
  class Cluster
    attr_accessor :domain
    attr_accessor :name

    def initialize(domain, name)
      @domain = domain
      @name = name
    end

    def cu_in_use
      queues.reduce(0) do |memo, queue|
        memo += queue.current_cu
      end
    end

    def cu_max
      @cu_max ||= cluster_data[:tags]['flight:quota'].to_i
    end

    private
    def cluster_data
      @cluster_data ||= AWS.cluster(@domain, @name)
    end

    def queues
      @queues ||= AWS.queues(@domain, @name).map do |queue_data|
        Queue.new(queue_data[:spec], @cluster, queue_data)
      end
    end
  end
end

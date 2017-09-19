module Tracon
  class FlyConfig
    attr_accessor :template_set
    attr_accessor :key_pair
    attr_accessor :region
    attr_accessor :access_key
    attr_accessor :secret_key
    attr_accessor :domain
    
    def initialize(cluster, queue)
      @cluster = cluster
      @domain = cluster.domain
      @queue = queue
      @access_key = ENV['AWS_ACCESS_KEY_ID']
      @secret_key = ENV['AWS_SECRET_ACCESS_KEY']
      @template_set = ENV['FLY_TEMPLATE_SET']
      @key_pair = ENV['FLY_KEY_PAIR']
    end

    def queue_name
      @queue.name
    end

    def cluster_name
      @cluster.name
    end
  end
end

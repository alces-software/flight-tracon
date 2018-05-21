module Tracon
  class FlyConfig

    attr_accessor :access_key
    attr_accessor :cluster_name
    attr_accessor :domain
    attr_accessor :key_pair
    attr_accessor :qualified_cluster_name
    attr_accessor :queue_name
    attr_accessor :region
    attr_accessor :secret_key
    attr_accessor :template_set

    def initialize(cluster, queue)
      @domain = cluster.domain
      @access_key = ENV['AWS_ACCESS_KEY_ID']
      @secret_key = ENV['AWS_SECRET_ACCESS_KEY']
      @template_set = ENV['FLY_TEMPLATE_SET']
      @key_pair = ENV['FLY_KEY_PAIR']
      @region = Thread.current[:aws_region] || 'eu-west-1'
      @queue_name = queue.name
      @cluster_name = cluster.name
      @qualified_cluster_name = cluster.qualified_name
    end
  end
end

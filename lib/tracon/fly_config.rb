module Tracon
  class FlyConfig

    attr_accessor :access_key
    attr_accessor :cluster_name
    attr_accessor :domain
    attr_accessor :fly_executable_path
    attr_accessor :key_pair
    attr_accessor :parameter_dir
    attr_accessor :qualified_cluster_name
    attr_accessor :queue_name
    attr_accessor :region
    attr_accessor :secret_key
    attr_accessor :template_set

    def initialize(cluster, queue, parameter_dir=nil)
      @access_key = ENV['AWS_ACCESS_KEY_ID']
      @cluster_name = cluster.name
      @domain = cluster.domain
      @fly_executable_path = ENV['FLY_EXE_PATH']
      @key_pair = ENV['FLY_KEY_PAIR']
      @parameter_dir = parameter_dir
      @qualified_cluster_name = cluster.qualified_name
      @queue_name = queue.name
      @region = Thread.current[:aws_region] || ENV['AWS_REGION'] || 'eu-west-1'
      @secret_key = ENV['AWS_SECRET_ACCESS_KEY']
      @template_set = ENV['FLY_TEMPLATE_SET']
    end
  end
end

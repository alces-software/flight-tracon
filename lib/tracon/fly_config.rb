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

    def initialize
      @access_key = ENV['AWS_ACCESS_KEY_ID']
      @secret_key = ENV['AWS_SECRET_ACCESS_KEY']
      @region = Thread.current[:aws_region] || ENV['AWS_REGION'] || 'eu-west-1'
    end

    class CreateQueueBuilder
      def initialize(cluster, queue)
        @cluster = cluster
        @queue = queue
      end

      def build
        FlyConfig.new.tap do |config|
          config.key_pair = ENV['FLY_KEY_PAIR']
          config.template_set = ENV['FLY_TEMPLATE_SET']
          config.domain = @cluster.domain
          config.queue_name = @queue.name
          config.cluster_name = @cluster.name
          config.qualified_cluster_name = @cluster.qualified_name
        end
      end
    end

    class DestroyQueueBuilder
      def initialize(cluster, queue)
        @cluster = cluster
        @queue = queue
      end

      def build
        FlyConfig.new.tap do |config|
          config.domain = @cluster.domain
          config.queue_name = @queue.name
          config.cluster_name = @cluster.name
          config.qualified_cluster_name = @cluster.qualified_name
        end
      end
    end
  end
end

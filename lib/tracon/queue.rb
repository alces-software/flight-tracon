require 'tracon/fly_config'
require 'tracon/fly_runner'
require 'tracon/fly_queue_builder'

module Tracon
  class Queue
    TYPES = {
      'general-pilot' => {
        type: 'c4.large-2C-3.75GB',
        bid: '0.113',
        cu_per_node: 1,
        description: 'A general-pilot queue',
        name: 'General pilot',
      },
      'general-economy' => {
        type: 'c4.8xlarge-36C-60GB',
        bid: '1.811',
        cu_per_node: 10,
        description: 'A general-economy queue',
        name: 'General economy',
      },
      'general-durable' => {
        type: 'c4.8xlarge-36C-60GB',
        cu_per_node: 20,
        bid: '0',
        description: 'A general-durable queue',
        name: 'General durable',
      },
      'gpu-pilot' => {
        type: 'g2.2xlarge-1GPU-8C-15GB',
        cu_per_node: 5,
        bid: '0.702',
        description: 'A gpu-pilot queue',
        name: 'GPU pilot',
      },
      'gpu-economy' => {
        type: 'p2.8xlarge-8GPU-32C-488GB',
        cu_per_node: 40,
        bid: '7.776',
        description: 'A gpu-economy queue',
        name: 'GPU economy',
      },
      'gpu-durable' => {
        type: 'p2.8xlarge-8GPU-32C-488GB',
        cu_per_node: 80,
        bid: '0',
        description: 'A gpu-durable queue',
        name: 'GPU durable',
      },
      'highmem-economy' => {
        type: 'r4.8xlarge-32C-244GB',
        cu_per_node: 15,
        bid: '2.371',
        description: 'A highmem-economy queue',
        name: 'Highmem economy',
      },
      'highmem-durable' => {
        type: 'r4.8xlarge-32C-244GB',
        cu_per_node: 30,
        bid: '0',
        description: 'A highmem-durable queue',
        name: 'Highmem durable',
      },
      'balanced-economy' => {
        type: 'm4.10xlarge-40C-160GB',
        cu_per_node: 15,
        bid: '2.220',
        description: 'A balanced-economy queue',
        name: 'Balanced economy',
      },
      'balanced-durable' => {
        type: 'm4.10xlarge-40C-160GB',
        cu_per_node: 30,
        bid: '0',
        description: 'A balanced-durable queue',
        name: 'Balanced durable',
      }
    }

    UNKNOWN_SPEC = {}.freeze

    attr_accessor :name, :spec, :cluster
    attr_reader :run_fly_thread

    class << self
      def destroy_queues(cluster, queues, &block)
        # Copy across the aws_region thread local variable as the block may make
        # use of it.
        region = Thread.current[:aws_region]
        Thread.new(region) do |r|
          Thread.current[:aws_region] = r
          Engine.started(cluster)
          begin
            queues.each do |queue|
              queue.destroy(skip_engine_update: true)
            end
            threads = queues.map {|q| q.run_fly_thread}
            threads.each {|t| t.join}
            block.call unless block.nil?
          rescue
            STDERR.puts $!.message
            STDERR.puts $!.backtrace.join("\n")
          ensure
            Engine.completed(cluster)
          end
        end
      end
    end

    def initialize(name, cluster, queue_data = nil)
      @name = name
      @cluster = cluster
      @spec = TYPES[@name] || UNKNOWN_SPEC
      @queue_data = queue_data
    end

    def method_missing(s, *a, &b)
      return @spec[s] if @spec.key?(s)
      raise
    end
    
    def cu_per_node
      @spec[:cu_per_node]
    end

    def current_cu
      @cu ||= size * cu_per_node
    end

    def size
      @size ||= queue_data[:current]
    end

    def exists?
      @exists ||= queue_data.present? && queue_data.key?(:id)
    end

    def update(desired, min, max, &block)
      AWS.update_queue(queue_data, desired, min, max)
      block.call unless block.nil?
      # XXX
      # FlyRunner.new('modq', nil, fly_config).perform
    end

    def create(desired, min, max, &block)
      parameter_dir = FlyQueueBuilder.new(self, desired, min, max).perform
      fly_config = FlyConfig::CreateQueueBuilder.new(@cluster, self).build
      runner = FlyRunner.new('addq', parameter_dir, fly_config)
      run_fly(runner, &block)
    end

    def destroy(skip_engine_update: false, &block)
      fly_config = FlyConfig::DestroyQueueBuilder.new(@cluster, self).build
      run_fly(
        FlyRunner.new('delq', nil, fly_config),
        skip_engine_update: skip_engine_update,
        &block
      )
    end

    private
    def queue_data
      @queue_data ||= AWS.queue(@cluster.domain, @cluster.qualified_name, @name)
    end

    def run_fly(runner, skip_engine_update: false, &block)
      # Copy across the aws_region thread local variable as the block may make
      # use of it.
      region = Thread.current[:aws_region]
      @run_fly_thread = Thread.new(region) do |r|
        Thread.current[:aws_region] = r
        Engine.started(@cluster) unless skip_engine_update
        begin
          runner.perform
          puts runner.stdout
          puts runner.stderr
          puts runner.arn
          block.call unless block.nil?
        rescue
          STDERR.puts $!.message
          STDERR.puts $!.backtrace.join("\n")
        ensure
          @run_fly_thread = nil
          Engine.completed(@cluster) unless skip_engine_update
        end
      end
      if @run_fly_thread.join(2)
        !runner.failed?
      else
        # didn't fail after 2s, so we assume that background
        # processing is happening now.
        true
      end
    end
  end
end

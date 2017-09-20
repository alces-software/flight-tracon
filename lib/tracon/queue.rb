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
      },
      'general-economy' => {
        type: 'c4.8xlarge-36C-60GB',
        bid: '1.811',
        cu_per_node: 10,
      },
      'general-durable' => {
        type: 'c4.8xlarge-36C-60GB',
        cu_per_node: 20,
        bid: '0',
      },
      'gpu-pilot' => {
        type: 'g2.2xlarge',
        cu_per_node: 5,
        bid: '0.702',
      },
      'gpu-economy' => {
        type: 'p2.8xlarge',
        cu_per_node: 40,
        bid: '7.776',
      },
      'gpu-durable' => {
        type: 'p2.8xlarge',
        cu_per_node: 80,
        bid: '0',
      },
      'highmem-economy' => {
        type: 'r4.8xlarge',
        cu_per_node: 15,
        bid: '2.371',
      },
      'highmem-durable' => {
        type: 'r4.8xlarge',
        cu_per_node: 30,
        bid: '0',
      },
      'balanced-economy' => {
        type: 'm4.10xlarge',
        cu_per_node: 15,
        bid: '2.220',
      },
      'balanced-durable' => {
        type: 'm4.10xlarge',
        cu_per_node: 30,
        bid: '0',
      }
    }

    UNKNOWN_SPEC = {}.freeze

    attr_accessor :name, :spec, :cluster

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

    def update(desired, min, max)
      AWS.update_queue(queue_data, desired, min, max)
      # XXX
      # FlyRunner.new('modq', nil, fly_config).perform
    end

    def create(desired, min, max)
      parameter_dir = FlyQueueBuilder.new(self, desired, min, max).perform
      runner = FlyRunner.new('addq', parameter_dir, fly_config)
      run_fly(runner)
    end

    def destroy
      run_fly(FlyRunner.new('delq', nil, fly_config))
    end

    private
    def fly_config
      FlyConfig.new(@cluster, self)
    end

    def queue_data
      @queue_data ||= AWS.queue(@cluster.domain, @cluster.qualified_name, @name)
    end

    def run_fly(runner)
      t = Thread.new do
        Engine.started(@cluster)
        begin
          runner.perform
          puts runner.stdout
          puts runner.stderr
          puts runner.arn
        rescue
          STDERR.puts $!.message
          STDERR.puts $!.backtrace.join("\n")
        ensure
          Engine.completed(@cluster)
        end
      end
      if t.join(2)
        !runner.failed?
      else
        # didn't fail after 2s, so we assume that background
        # processing is happening now.
        true
      end
    end
  end
end

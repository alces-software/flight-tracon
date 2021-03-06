require 'open3'
require 'yaml'

module Tracon
  class FlyQueueBuilder
    def initialize(queue, desired, min, max, fly_config)
      @queue = queue
      @desired = desired
      @min = min
      @max = max
      @fly_config = fly_config
    end

    def perform
      create_parameter_directory
      merge_overrides
      parameter_dir
    end

    def parameter_dir
      @parameter_dir ||= File.join(
        Dir.tmpdir,
        Dir::Tmpname.make_tmpname('flight-launch-', nil)
      )
    end

    def merge_overrides
      puts "Merging overrides for 'cluster-compute' parameters"
      params = YAML.load_file(File.join(parameter_dir, "cluster-compute.yml"))
      new_params = params.merge(overrides.slice(*params.keys))
      File.write(File.join(@parameter_dir, "cluster-compute.yml.bak"), params.to_yaml)
      File.write(File.join(@parameter_dir, "cluster-compute.yml"), new_params.to_yaml)
    end

    def overrides
      cluster = @queue.cluster
      {
        'ComputeSpotPrice' => @queue.bid,
        'ComputeInitialNodes' => @desired,
        'ComputeMaxNodes' => @max,
        'ComputeInstanceTypeOther' => @queue.type,
        'ComputeInstanceType' => 'other',
        'ClusterName' => cluster.name,
        'FlightProfileBucket' => cluster.flight_profile_bucket,
        'SchedulerType' => cluster.scheduler_type,
        # XXX Min nodes!
      }
    end

    def create_parameter_directory
      fly_exe_path = @fly_config.fly_executable_path
      cmd = [fly_exe_path, '--create-parameter-directory', parameter_dir]
      puts "Creating fly parameter directory: #{cmd.inspect}"
      exit_status = Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thr|
        stdin.close
        stdout.read
        stderr.read
        wait_thr.value
      end

      unless exit_status.success?
        raise "Unable to create parameter directory"
      end
    end

  end
end

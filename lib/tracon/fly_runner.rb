#==============================================================================
# Copyright (C) 2017 Stephen F. Norledge and Alces Flight Ltd.
#
# This file is part of Alces Launch.
#
# All rights reserved, see LICENSE.txt.
#==============================================================================

require 'open3'

#
# Run the `fly` command described by the given `fly_params`.
#
module Tracon
  class FlyRunner
    attr_reader :stdout, :stderr

    def initialize(fly_params)
      @fly_params = fly_params
    end

    def perform
      log_params
      launch_with_popen3
    end

    def failed?
      @exit_status && ! @exit_status.success?
    end

    def launch_with_popen3
      cmd = @fly_params.cmd
      env = @fly_params.env
      @exit_status = Open3.popen3(env, *cmd) do |stdin, stdout, stderr, wait_thr|
        stdin.close
        @stdout = stdout.read
        @stderr = stderr.read
        wait_thr.value
      end
    end

    def log_params
      puts "Running command #{@fly_params.sanitized_cmd.inspect} in env #{@fly_params.env.inspect}"
    end
  end
end

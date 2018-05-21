#==============================================================================
# Copyright (C) 2017 Stephen F. Norledge and Alces Flight Ltd.
#
# This file is part of Alces Launch.
#
# All rights reserved, see LICENSE.txt.
#==============================================================================

require 'open3'

#
# Run the `fly` command and get the stack arn from the output.
#
# We don't want to be blocked waiting for the stack to finish launching in
# order to obatin the arn.  This class runs the fly command and reads its
# output as it is produced, so that it can obtain the arn as soon as possible.
#
# A number of utility methods for checking the status of this command have
# been added.
#
module Tracon
  class FlyRunner
    attr_reader :arn,
                :stdout,
                :stderr

    def initialize(command, parameter_dir, fly_config)
      @command = command
      @parameter_dir = parameter_dir
      @fly_config = fly_config
    end

    def perform
      cmd, env = build_command_and_environment
      log_cmd(cmd, env)
      launch_with_popen3(cmd, env)
    end

    def failed?
      @exit_status && ! @exit_status.success?
    end

    def waiting_for_arn?
      arn.nil? && @exit_status.nil?
    end

    def build_command_and_environment
      extra_args = []
      if @fly_config.template_set.present?
        extra_args << '--template-set' << @fly_config.template_set
      end
      if @fly_config.key_pair.present?
        extra_args << '--key-pair' << @fly_config.key_pair
      end
      if @fly_config.region.present?
        extra_args << '--region' << @fly_config.region
      end
      if @parameter_dir
        extra_args << '--parameter-directory' << @parameter_dir
      end
      cmd = [
        ENV['FLY_EXE_PATH'],
        'cluster',
        @command,
        @fly_config.qualified_cluster_name,
        @fly_config.queue_name,
        '--domain', @fly_config.domain,
        '--access-key', @fly_config.access_key,
        '--secret-key', @fly_config.secret_key,
        *extra_args,
      ]

      env = {
        "FLY_SIMPLE_OUTPUT" => "true"
      }

      [cmd, env]
    end

    def launch_with_popen3(cmd, env)
      @exit_status = Open3.popen3(env, *cmd) do |stdin, stdout, stderr, wait_thr|
        stdin.close
        stdout_bytes_read = read_arn(stdout, wait_thr)
        @stdout = stdout_bytes_read
        @stdout << stdout.read
        @stderr = stderr.read
        wait_thr.value
      end
    end

    def read_arn(stdout, wait_thr)
      stdout_read = ""
      while wait_thr.alive?
        lines = stdout.readpartial(512)
        stdout_read << lines
        stdout_read.split("\n").each do |line|
          if line =~ /^CREATE_IN_PROGRESS\s*[-0-9a-zA-Z]*#{@fly_config.queue_name}/
            @arn = line.gsub(/^[^(]*\(([^)]*)\)/, '\1')
            return stdout_read
          end
        end
      end
      stdout_read
    rescue EOFError
      stdout_read
    end

    def log_cmd(cmd, env)
      sanitized_cmd = cmd.map do |i|
        (i == @fly_config.access_key || i == @fly_config.secret_key) ? '[REDACTED]' : i
      end
      puts "Running command #{sanitized_cmd.inspect} in env #{env.inspect}"
    end
  end
end

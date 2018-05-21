#
# Serialize the given FlyConfig into command-line parameters and environment
# for running fly.
#
class FlyConfigSerializer
  class Result < Struct.new(:cmd, :env, :redacted_values)
    def sanitized_cmd
      cmd.map do |i|
        redacted_values.include?(i) ? '[REDACTED]' : i
      end
    end
  end

  def initialize(fly_config)
    @fly_config = fly_config
  end

  def serialize
    redacted_values = [ @fly_config.access_key, @fly_config.secret_key ]
    Result.new(command, environment, redacted_values)
  end

  def command
    raise NotImplementedError
  end

  def add_arg_if_present(arg_name, value)
    [].tap do |args|
      if value.present?
        args << arg_name << value
      end
    end
  end

  def environment
    {
      "FLY_SIMPLE_OUTPUT" => "true"
    }
  end


  class CreateQueueSerializer < FlyConfigSerializer
    def command
      [
        @fly_config.fly_executable_path,
        'cluster',
        'addq',
        @fly_config.qualified_cluster_name,
        @fly_config.queue_name,
        '--domain', @fly_config.domain,
        '--access-key', @fly_config.access_key,
        '--secret-key', @fly_config.secret_key,
        *add_arg_if_present('--template-set', @fly_config.template_set),
        *add_arg_if_present('--key-pair', @fly_config.key_pair),
        *add_arg_if_present('--region', @fly_config.region),
        '--parameter-directory', @fly_config.parameter_dir,
      ]
    end
  end

  class DestroyQueueSerializer < FlyConfigSerializer
    def command
      [
        @fly_config.fly_executable_path,
        'cluster',
        'delq',
        @fly_config.qualified_cluster_name,
        @fly_config.queue_name,
        '--domain', @fly_config.domain,
        '--access-key', @fly_config.access_key,
        '--secret-key', @fly_config.secret_key,
        *add_arg_if_present('--region', @fly_config.region),
      ]
    end
  end
end

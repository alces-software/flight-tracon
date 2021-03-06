require 'aws-sdk'
require 'active_support/core_ext/module/delegation'

Aws.config.update(
  {
    region: ENV['AWS_REGION'] || 'eu-west-1',
    credentials: Aws::Credentials.new(ENV['AWS_ACCESS_KEY_ID'], ENV['AWS_SECRET_ACCESS_KEY'])
  }
)

module Tracon
  class AWS
    class << self
      delegate :describe_auto_scaling_groups,
               :update_auto_scaling_group,
               :terminate_instance_in_auto_scaling_group,
               to: :autoscaling
      delegate :describe_stacks, to: :cfn
      
      def clusters(domain)
        flight_type = Tracon.solo_domain?(domain) ? 'solo' : 'master'
        [].tap do |a|
          res = describe_stacks
          a.concat(res.stacks)
          while res.next_token
            res = describe_stacks(next_token: res.next_token)
            a.concat(res.stacks)
          end
        end.map(&method(:cluster_from_stack))
          .select do |stack|
          stack[:tags]['flight:type'] == flight_type &&
            stack[:name].start_with?("flight-#{domain}-")
        end
      end

      def cluster(domain, cluster_name)
        stack_name = "flight-#{domain}-#{cluster_name}"
        stack_name = "#{stack_name}-master" unless Tracon.solo_domain?(domain)
        res = describe_stacks(stack_name: stack_name)
        cluster_from_stack(res.stacks[0])
      rescue Aws::CloudFormation::Errors::ValidationError
        # doesn't exist
        nil
      end

      def cluster_token(domain, cluster_name)
        stack_name = "flight-#{domain}-#{cluster_name}"
        stack_name = "#{stack_name}-master" unless Tracon.solo_domain?(domain)
        res = describe_stacks(stack_name: stack_name)
        cr = configuration_result(res.stacks[0])
        return nil if cr.nil?
        cr['Token']
      rescue Aws::CloudFormation::Errors::ValidationError
        # doesn't exist
        nil
      end

      def queues(domain, cluster_name)
        asgs.map(&method(:queue_from_asg))
          .select {|group|group[:name].start_with?("flight-#{domain}-#{cluster_name}-compute-")}
      end

      def queue(domain, cluster_name, queue_name)
        queues(domain, cluster_name).find do |group|
          group[:name].start_with?("flight-#{domain}-#{cluster_name}-compute-#{queue_name}-") ||
            group[:spec] == queue_name
        end || nil
      end

      def update_queue(queue, desired, min, max)
        update_auto_scaling_group(
          {
            auto_scaling_group_name: queue[:name],
            desired_capacity: desired,
            max_size: max,
            min_size: min,
          }
        )
      end

      def nodes(domain, cluster_name, queue_name)
        asg = asgs.find do |asg|
          label_tag = asg.tags.find {|tag| tag.key == 'AutoscalingGroupLabel'}
          spec = label_tag.value if label_tag
          asg.auto_scaling_group_name.start_with?("flight-#{domain}-#{cluster_name}-compute-#{queue_name}") ||
            (
              asg.auto_scaling_group_name.start_with?("flight-#{domain}-#{cluster_name}-compute-") &&
              queue_name == spec
            )
        end
        if asg
          asg.instances.map(&method(:node_from_asg_instance))
        else
          []
        end
      end

      def node(domain, cluster_name, queue_name, node_name)
        nodes(domain, cluster_name, queue_name).find do |node|
          node[:name] == node_name
        end || nil
      end

      def shoot_node(node_name)
        terminate_instance_in_auto_scaling_group(
          {
            instance_id: node_name,
            should_decrement_desired_capacity: true,
          }
        )
      rescue Aws::AutoScaling::Errors::ValidationError
        if $!.message =~ /Terminating instance without replacement will violate group's min size constraint./
          false
        else
          raise
        end
      end
      
      private

      def configuration_result(stack)
        c = stack.outputs.find do |output|
          output.output_key == "ConfigurationResult"
        end
        return nil if c.nil?
        JSON.parse(c.output_value).values.first.split(';').inject({}) do |h, v|
          key, value = v.split('=')
          h[key] = value
          h
        end
      end

      def asgs
        [].tap do |a|
          res = describe_auto_scaling_groups
          a.concat(res.auto_scaling_groups)
          while res.next_token
            res = describe_auto_scaling_groups(next_token: res.next_token)
            a.concat(res.auto_scaling_groups)
          end
        end
      end

      def node_from_asg_instance(asg_instance)
        {
          name: asg_instance.instance_id,
        }
      end

      def queue_from_asg(asg)
        queue_spec_match = asg.auto_scaling_group_name.match(/compute-(.*)-FlightComputeGroup/)
        queue_spec = queue_spec_match && queue_spec_match[1] || 'unknown'
        {
          id: asg.auto_scaling_group_arn,
          name: asg.auto_scaling_group_name,
          spec: queue_spec,
          current: asg.desired_capacity,
          max: asg.max_size,
          min: asg.min_size
        }.tap do |q|
          label_tag = asg.tags.find {|tag| tag.key == 'AutoscalingGroupLabel'}
          q[:spec] = label_tag.value if label_tag
        end
      end

      def cluster_from_stack(stack)
        {
          id: stack.stack_id,
          name: stack.stack_name,
          ctime: stack.creation_time,
          configuration_result: configuration_result(stack),
          parameters: {}.tap do |h|
            stack.parameters.each {|p| h[p.parameter_key] = p.parameter_value}
          end,
          tags: {}.tap do |h|
            stack.tags.each {|tag| h[tag.key] = tag.value}
          end,
          outputs: {}.tap do |h|
            stack.outputs.each do |output|
              unless output.output_key == 'ConfigurationResult'
                h[output.output_key] = output.output_value
              end
            end
          end,
        }
      end

      def cfn
        (@cfn ||= Hash.new do |h,k|
          h[k] = Aws::CloudFormation::Client.new(region: Thread.current[:aws_region])
        end)[Thread.current[:aws_region]]
      end

      def autoscaling
        (@autoscaling ||= Hash.new do |h,k|
          h[k] = Aws::AutoScaling::Client.new(region: Thread.current[:aws_region])
        end)[Thread.current[:aws_region]]
      end
    end
  end
end

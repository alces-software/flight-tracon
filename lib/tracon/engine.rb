require 'tracon/cluster'
require 'tracon/credit_checker'
require 'tracon/credit_usage'
require 'tracon/queue'
require 'tracon/node'
require 'digest/md5'

module Tracon
  class Engine

    class << self
      PEPPER = ENV['TRACON_PEPPER']

      def valid_credentials?(username, password)
        cluster, domain = username.split('.')
        if domain.nil?
          domain = cluster
          cluster = nil
        end
        if cluster.nil?
          # XXX verify for domain only.
          input = "#{domain}:#{PEPPER}"
          STDERR.puts Base64.encode64(Digest::MD5.digest(input)).inspect
          Base64.encode64(Digest::MD5.digest(input)).chomp == password
        else
          # verify for cluster
          token = AWS.cluster_token(domain, cluster)
          STDERR.puts token
          token == password
        end
      end

      def old_valid_credentials?(username, password)
        input = "#{password[0..7]}:#{username}:#{PEPPER}"
        STDERR.puts Base64.encode64(Digest::MD5.digest(input)).inspect
        Base64.encode64(Digest::MD5.digest(input)).chomp == password[8..-1]
      end

      def creator(params)
        Creator.new(params)
      end

      def destroyer(params)
        Destroyer.new(params)
      end

      def updater(params)
        Updater.new(params)
      end

      def shooter(params)
        Shooter.new(params)
      end

      def started(cluster)
        pool["#{cluster.qualified_name}.#{cluster.domain}"] = true
      end

      def completed(cluster)
        pool["#{cluster.qualified_name}.#{cluster.domain}"] = false
      end

      def in_progress?(cluster)
        pool["#{cluster.qualified_name}.#{cluster.domain}"] == true
      end

      private
      def pool
        @pool ||= {}
      end
    end

    class Creator
      attr_reader :errors

      def initialize(params)
        @cluster = Cluster.new(params[:domain], params[:cluster])
        @queue = Queue.new(params[:queue], @cluster)
        @credit_usage = CreditUsage.new(@cluster)
        @desired = params[:desired].to_i
        @min = params[:min].to_i
        @max = params[:max].to_i
        @max = @desired if @desired > @max
        @errors = []
      end

      def queue
        {
          min: @min,
          max: @max,
          desired: @desired
        }
      end

      def valid?
        if Engine.in_progress?(@cluster)
          @errors << 'operation in progress'
          return false
        end
        if @queue.exists?
          @errors << 'queue exists'
          return false
        end
        if @max < 1
          @errors << 'bad maximum (< 1)'
          return false
        end
        if @queue.spec == Queue::UNKNOWN_SPEC
          @errors << 'unknown queue spec'
          return false
        end
        # calculate number of compute units this queue will cost
        cu_desired = @desired * @queue.cu_per_node
        # compare to number of compute units currently in use (other queue current levels)
        unless @cluster.cu_max == 0 || @cluster.cu_in_use + cu_desired <= @cluster.cu_max
          @errors << 'quota exceeded'
          return false
        end

        # If the cluster consumes credits, check that the cluster's user has
        # enough credits.
        cc = CreditChecker.new(@cluster)
        unless cc.valid?
          @errors += cc.errors
          return false
        end

        true
      end

      def process
        if valid?
          # create queue params file
          # use fly to launch queue
          @queue.create(@desired, @min, @max) do
            # If the queue is created, record new credit usage.
            @credit_usage.create()
          end
        else
          false
        end
      end
    end

    class Destroyer
      attr_reader :errors

      def initialize(params)
        @cluster = Cluster.new(params[:domain], params[:cluster])
        if params[:all_queues]
          @named_queue = false
          @queues = @cluster.queues
        else
          @named_queue = true
          @queue = Queue.new(params[:queue], @cluster)
        end
        @credit_usage = CreditUsage.new(@cluster)
        @errors = []
      end

      def valid?
        if Engine.in_progress?(@cluster)
          @errors << 'operation in progress'
          return false
        end
        if @named_queue && !@queue.exists?
          @errors << 'queue not found'
          return false
        end
        true
      end

      def process
        if valid?
          # use fly to destroy the queues
          if @named_queue
            @queue.destroy do
              # If the queue is destroyed, record new credit usage.
              @credit_usage.create()
            end
          else
            Queue.destroy_queues(@cluster, @queues) do
              # When all queues are destroyed, record new credit usage.
              @credit_usage.create()
            end
          end
          true
        else
          false
        end
      end
    end

    class Updater
      attr_reader :errors

      def initialize(params)
        @cluster = Cluster.new(params[:domain], params[:cluster])
        @queue = Queue.new(params[:queue], @cluster)
        @credit_usage = CreditUsage.new(@cluster)
        @desired = params[:desired].to_i
        @min = params[:min].to_i
        @max = params[:max].to_i
        @max = @desired if @desired > @max
        @errors = []
      end

      def queue
        {
          min: @min,
          max: @max,
          desired: @desired
        }
      end

      def valid?
        unless @queue.exists?
          @errors << 'queue not found'
          return false
        end
        if Engine.in_progress?(@cluster)
          @errors << 'operation in progress'
          return false
        end
        if @min > @desired
          @errors << 'minimum larger than requested size'
          return false
        end
        # calculate number of compute units this queue will cost
        cu_desired = (@desired - @queue.size) * @queue.cu_per_node
        # compare to number of compute units currently in use (other queue current levels)
        unless @cluster.cu_max == 0 || @cluster.cu_in_use + cu_desired <= @cluster.cu_max
          @errors << 'quota exceeded'
          return false
        end

        # If we're increasing the number of compute units this queue will
        # cost for a Flight Launch cluster, check that the cluster's owner, if
        # any, has enough credits.
        if cu_desired > 0
          cc = CreditChecker.new(@cluster)
          unless cc.valid?
            @errors += cc.errors
            return false
          end
        end

        true
      end

      def process
        if valid?
          # use fly to update queue
          @queue.update(@desired, @min, @max) do
            # If the queue is updated, record new credit usage.
            @credit_usage.create()
          end
          true
        else
          false
        end
      end
    end

    class Shooter
      attr_reader :errors

      def initialize(params)
        @cluster = Cluster.new(params[:domain], params[:cluster])
        @queue = Queue.new(params[:queue], @cluster)
        @node = Node.new(params[:node], @queue)
        @credit_usage = CreditUsage.new(@cluster)
        @errors = []
      end

      def valid?
        unless @queue.exists?
          @errors << 'queue not found'
          return false
        end
        unless @node.exists?
          @errors << 'node not found'
          return false
        end
        true
      end

      def process
        if valid?
          # use fly to destroy queue
          unless @node.shoot
            @errors << 'already min size'
            false
          else
            # The node has been shot.  Record new credit usage.
            @credit_usage.create()
            true
          end
        else
          false
        end
      end
    end
  end
end

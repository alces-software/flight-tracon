require 'tracon/cluster'
require 'tracon/compute_unit_consumption_validator'
require 'tracon/credit_usage'
require 'tracon/quota_validator'
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
          if ENV['LOG_CREDENTIALS'] == 'true'
            STDERR.puts Base64.encode64(Digest::MD5.digest(input)).inspect
          end
          Base64.encode64(Digest::MD5.digest(input)).chomp == password
        else
          # verify for cluster
          token = AWS.cluster_token(domain, cluster)
          # XXX If token is nil then the cluster is gone.  We should probably
          # return a better error code than 401 Unauthorized in that case.
          if ENV['LOG_CREDENTIALS'] == 'true'
            STDERR.puts token
          end
          token == password
        end
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
        @fly_params = params[:fly] || {}
        @errors = []
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

        # Ensure that the clusters quota, if any, is not going to be exceeded.
        qc = QuotaValidator.new(@cluster, @desired, @queue)
        unless qc.valid?
          @errors += qc.errors
          return false
        end

        cc = ComputeUnitConsumptionValidator.new(@cluster, @desired, @queue)
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
          @queue.create(@desired, @min, @max, @fly_params) do
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

        # Ensure that the clusters quota, if any, is not going to be exceeded.
        qc = QuotaValidator.new(@cluster, @desired, @queue)
        unless qc.valid?
          @errors += qc.errors
          return false
        end

        cc = ComputeUnitConsumptionValidator.new(@cluster, @desired, @queue)
        unless cc.valid?
          @errors += cc.errors
          return false
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

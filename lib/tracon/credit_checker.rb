module Tracon

  # For clusters which consume flight launch credits, checks that:
  #
  #  1. the user has sufficient credits
  #  2. the cluster is not in a grace period
  #  3. the cluster's credit limit, if any, will not be exceeded
  #
  class CreditChecker
    attr_reader :errors

    def initialize(cluster, desired, queue)
      @errors = []
      @cluster = cluster
      @desired = desired
      @queue = queue
    end

    # If the cluster consumes credits, check that the cluster's user has
    # enough credits.
    def valid?
      return true if decreasing_cu_usage?
      return true if launch_cluster.nil?
      return true unless using_ongoing_credits?
      return false if owner.nil?

      validate_owner_has_compute_credits
      validate_cluster_is_not_in_grace_period
      validate_cluster_limit

      @errors.empty?
    end

    private

    def decreasing_cu_usage?
      @queue.exists? && @desired < @queue.size
    end

    def using_ongoing_credits?
      return false if payment.nil?
      payment.attributes.paymentMethod == 'credits:ongoing'
    end

    def launch_cluster
      @launch_cluster ||= JSONAPI.load_launch_cluster(@cluster).resource
    end

    def owner
      @owner ||= launch_cluster.load_relationship(:owner).resource
    end

    def payment
      @payment ||= launch_cluster.load_relationship(:payment).resource
    end

    def validate_owner_has_compute_credits
      if owner.attributes.computeCredits <= 0
        @errors << 'compute units exhausted'
      elsif owner.attributes.computeCredits < minimum_credits_required
        @errors << 'compute units insufficient'
      end
    end

    def validate_cluster_is_not_in_grace_period
      if launch_cluster.attributes.gracePeriodExpiresAt
        @errors << 'grace period active'
      end
    end

    # If we're increasing the number of compute units the cluster will
    # consume, check that there will still be `minimum_runtime` available to
    # the cluster afterwards.
    def validate_cluster_limit
      credit_limit = payment.attributes.maxCreditUsage
      return if credit_limit.nil?
      credits_available = credit_limit - credits_used
      if credits_available < minimum_credits_required
        @errors << 'compute unit limit insufficient'
      end
    end

    def credits_used
      credit_usages = launch_cluster.load_relationship(:creditUsages, {
        'page[offset]' => 0,
        'page[limit]' => 0,
      })
      credit_usages.meta.totalAccruedUsageForAp
    end

    # The number of compute units that will be in use after operation.
    def cu_desired
      if @queue.exists?
        # The additional number of compute units modifying this queue will
        # cost.
        (@desired - @queue.size) * @queue.cu_per_node
      else
        # The number of compute units creating this queue will cost.
        @desired * @queue.cu_per_node
      end
    end

    def minimum_credits_required
      ((@cluster.cu_in_use + cu_desired) * minimum_runtime / 60).ceil
    end

    def minimum_runtime
      minimum_runtime = ENV['MINIMUM_PERMITTED_RUNTIME'].to_i
      minimum_runtime > 0 ? minimum_runtime : 60
    end
  end
end

require 'json'
require 'open-uri'
require 'ostruct'

require 'tracon/jsonapi'

module Tracon
  class CreditUsage
    def initialize(cluster)
      @cluster = cluster
    end
    
    def create
      JSONAPI.create(credit_usage_url, {
        type: 'creditUsages',
        attributes: {
          queuesCuInUse: @cluster.cu_in_use(reload: true),
        },
        relationships: {
          'cluster': {
            data: { type: 'clusters', id: @cluster.uuid }
          }
        }
      })
    end

    private

    def credit_usage_url
      base_url = ENV['LAUNCH_API_BASE_URL']
      "#{base_url}/api/v1/credit-usages"
    end
  end
end

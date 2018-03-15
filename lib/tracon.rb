module Tracon
  SOLO_CLUSTER_DOMAIN = 'cluster'

  def self.solo_domain?(domain)
    domain == SOLO_CLUSTER_DOMAIN
  end
end

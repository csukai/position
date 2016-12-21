require 'haversine'
require 'ostruct'

require_relative '../geometric_helpers'

##
# Helper methods for clustering techniques
##

module Clusterers
  class Base

    private

    def distance_between(p1, p2)
      Haversine.distance(p1[:latitude], p1[:longitude], p2[:latitude], p2[:longitude]).to_meters
    end

    def centroid(visit)
      OpenStruct.new(GeometricHelpers.location_mean(visit))
    end

    def time_between(p1, p2)
      p2[:timestamp] - p1[:timestamp]
    end

    def summarise_clusters(clusters)
      clusters.map.with_index do |c, i|
        h = GeometricHelpers.location_mean(c)
        h[:id] = i
        h[:time] = c.first[:timestamp]..c.last[:timestamp] if c.first[:timestamp] # Time is only valid if we're dealing with raw points (i.e. have a timestamp property)
        c.each { |e| e.delete(:cluster_id) }
        h[:elements] = c
        h
      end
    end

  end
end
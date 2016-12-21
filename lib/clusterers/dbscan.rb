require 'ostruct'
require_relative 'base'

##
# DBSCAN, implementation based on:
#
# Martin Ester, Hans-Peter Kriegel, Jörg Sander, Xiaowei Xu, A density-based algorithm for discovering clusters in large spatial databases with noise, in:
# Proceedings of the 16th International Conference on Knowledge Discovery and Data Mining, Portland, 1996, pp. 226–231.
##

module Clusterers
  class DBSCAN < Base

    attr_reader :clusters
    alias_method :locations, :clusters

    def initialize(elements, eps, minpts = 0)
      raise unless eps >= 0

      @eps, @minpts = eps, minpts
      @cluster_counter = 0
      @elements = elements
      @noise_cluster = next_cluster_id

      cluster

      clusters = @elements.group_by { |p| p[:cluster_id] }.values
      @clusters = summarise_clusters(clusters)
    end

    def interactions
      clusters.flatten.sort_by { |i| i[:time].first }
    end

    private

    def cluster

      cluster_id = next_cluster_id

      # Search through the points, looking for a 'core point'
      @elements.each do |point|

        # If this point is unclustered (no cluster_id) and it's a core point in a cluster, expand_cluster
        # will detect the cluster and assign all points to it. In that case, create a new cluster,
        # update the point's cluster_id and start on the next unclustered point
        if !point[:cluster_id] and expand_cluster(@elements, point, cluster_id, @eps, @minpts)
          cluster_id = next_cluster_id
        end
      end
    end

    def expand_cluster(points, point, cluster_id, eps, minpts)

      # Extract the points within the Eps-neighbourhood of our point
      seeds = region_query(points, point, eps)

      # If the size of the neighbourhood is less that minpts, this is not a core point
      # Set it to noise and exit the function
      if seeds.length < minpts
        point[:cluster_id] = @noise_cluster
        return false

        # Otherwise, all the points in 'seeds' are density-reachable from our point
      else
        # Set them to belong to the cluster, and remove the point in question
        seeds.each { |point| point[:cluster_id] = cluster_id }
        seeds.delete(point)

        # While there are seeds left
        while seeds.length > 0

          # Extract the Eps-neighbourhood for each point in turn
          current_point = seeds.first
          result = region_query(points, current_point, eps)

          # If there are enough in the neighbourhood to be in a cluster, iterate over them
          if result.size > minpts
            result.each do |result_point|

              # If the point is currently unclustered or noise, join it to this cluster
              if [@noise_cluster, nil].include?(result_point[:cluster_id])

                # Also add it to the seeds list if it hadn't been classified before
                # (If it had, it was assigned to be noise but was actually a border point for this cluster)
                seeds << result_point unless result_point[:cluster_id]
                result_point[:cluster_id] = cluster_id
              end
            end
          end

          # Remove the current point from the list, because it's been processed
          seeds.delete(current_point)

        end

        # Return true because this was a valid cluster, and the algorithm is complete
        return true

      end

    end

    # Find all visits within +eps+ metres of +visit+
    def region_query(points, point, eps)
      points.select { |p| distance_between(p, point) < eps }
    end

    def next_cluster_id
      @cluster_counter += 1
    end
  end
end

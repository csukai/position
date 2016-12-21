require_relative '../datastore/land_usage_cluster'
require_relative '../datastore/distance_matrix'
require_relative '../lookup_tools/wordnet_similarity'

require 'parallel'
require 'ruby-progressbar'

include Datastore

module Clusterers

  # NB: Follows pseudocode, not ruby best practices
  class ContextTree

    attr_reader :root, :summary

    def initialize(summarised, lambda)
      @wordnet_similarity = LookupTools::WordnetSimilarity.new
      @lambda = lambda
      clusters = summarised.values.map { |h| LandUsageCluster.new(h) }
      @clusters = clusters.map { |c| [c.id, c] }.to_h
      @summary = {}
      log_info "Context Tree initialised with #{clusters.length} clusters"
    end

    def cluster

      @distanceMatrix = DistanceMatrix.new(@clusters)
      new = nil

      begin

        while @clusters.length > 1 do
          log_debug "Clustering round commencing, #{@clusters.length} items"

          # Update the distance matrix
          @distanceMatrix = distance_matrix(@distanceMatrix, new)

          # Find all pairs of clusters with the smallest distance
          closestGroups = closestGroups(@distanceMatrix)

          clusters_to_delete = []

          new = closestGroups.map do |group|
            newCluster = merge(group)
            group.each do |cluster|
              newCluster.add_child(cluster)
              cluster.parent = newCluster
              @clusters.delete(cluster.id)
              log_debug "Deleting #{cluster.id}"
              clusters_to_delete << cluster.id
            end

            # Remove the invalid entries from distanceMatrix
            @distanceMatrix.delete(clusters_to_delete)

            @clusters[newCluster.id] = newCluster
            newCluster
          end

        end

      rescue Exception => e
        raise e
      ensure
        @distanceMatrix.clean_up
      end

      @root = @clusters.values.first
    end

    def prune(threshold, xi, calculate_summary = false)
      raise "No root node to prune" unless @root
      @prune_threshold = threshold
      raise unless xi > 0
      @xi = xi
      recursive_prune(@root)
      @summary = {avg_distance: average_distance, total_information: total_information} if calculate_summary
      @root
    end

    private

    def average_distance
      distances = []
      clusters = @root.nodes_array(true)
      clusters.each do |outer|
        clusters.each do |inner|
          next if outer.object_id > inner.object_id # We only want to consider each pair once
          distances << hcd(outer, inner)
        end
      end
      return 1 unless distances.any?
      distances.mean
    end

    def total_information
      nodes = @root.nodes_array(true)
      nodes.map do |node|
        duration = node.times.map { |t| t.last - t.first }.sum
        area = node.area
        tags = node.tags.length
        ((1/3.0 * Float(duration)) + (1/3.0 * Float(area)) + (1/3.0 * Float(tags)))
      end.sum
    end

    #### Similarity Measures

    def hcd(c1, c2)
      semantic = @lambda > 0 ? 1.0 - semantic_similarity(c1, c2) : 1
      features = @lambda < 1 ? 1.0 - feature_similarity(c1, c2) : 1
      return 1 - ((@lambda * semantic) + ((1 - @lambda) * features))
    end

    def semantic_similarity(c1, c2)
      1.0 - (tag_similarity(cluster_tags(c1), cluster_tags(c2)))
    end

    def cluster_tags(cluster)
      cluster.tags.map { |k, v| "#{k}:#{v.kind_of?(Array) ? v.join(';') : v}" }
    end

    def tag_similarity(tags_1, tags_2)
      return 0.0 unless tags_1.any? and tags_2.any?
      similarity_matrix = Array.new(tags_1.length, Array.new(tags_2.length, 0.0))
      tags_1.each_with_index do |t1, i1|
        tags_2.each_with_index do |t2, i2|
          similarity = @wordnet_similarity.tag_similarity(t1, t2)
          similarity_matrix[i1][i2] = similarity || 0.0
        end
      end

      sim_12 = similarity_matrix.map { |a| a.max }.instance_eval { inject(:+) / Float(length) }
      sim_21 = similarity_matrix.transpose.map { |a| a.max }.instance_eval { inject(:+) / Float(length) }
      [sim_12, sim_21].max
    end

    def feature_similarity(c1, c2)
      1.0 - (jaccard_index(features_for(c1), features_for(c2)))
    end

    def jaccard_index(l1, l2)
      Float((l1 & l2).length) / (l1 + l2).uniq.length
    end

    def features_for(cluster)
      features = []
      features << "duration_#{avg_duration(cluster, 15)}"
      features << "timeofday_#{time_of_day(cluster, 4)}"
      features << "validcount_#{avg_valid_count(cluster, 1)}"
      features << "area_#{avg_area(cluster, 10)}"
      features
    end

    # Returns average duration rounded down to nearest n minutes
    def avg_duration(cluster, increments)
      average = cluster.average_duration
      (average / increments).floor * increments
    end

    # Returns most common start hour rounded down to the nearest block
    def time_of_day(cluster, increments)
      (cluster.mode_starthour / Float(increments)).floor * increments
    end

    # Returns the average number of individual times the cluster was valid, rounded down to the nearest n
    def avg_valid_count(cluster, increments)
      (cluster.times.length / Float(increments)).floor * increments
    end

    # Returns the average area of members of the cluster in m^2 to the nearest n
    def avg_area(cluster, increments)
      (cluster.area / Float(increments)).floor * increments
    end

    #### Pruning Measures

    def cost_benefit(cluster, parent = nil)
      parent ||= cluster.parent
      numerator = Float(utility(cluster, parent))
      denominator = Float(storage_cost(cluster, parent))
      raise unless numerator >= 0
      raise unless denominator > 0
      cb = numerator / denominator
      log_debug "CostBenefit: #{cb}"
      cb
    end

    def utility(cluster, parent)
      return 1.0 unless parent
      times = cluster.times.map { |t| t.last - t.first }.sum / Float(parent.times.map { |t| t.last - t.first }.sum)
      times = 0.0 if times.nan?
      coordsets = parent.area > 0 ? cluster.area / Float(parent.area) : 0.0
      # It is technically possible for a parent to have smaller area than a child due to taking convex hulls
      coordsets = 1.0 if coordsets > 1.0
      tags = cluster.tags.length / Float(parent.tags.length)
      utility = 1 - ((times + coordsets + tags) / 3.0)
      log_debug "Utility: #{utility} (#{times}, #{coordsets}, #{tags})"
      raise "Utility can't be > 1 or < 0 (is #{utility})" if utility > 1 or utility < 0
      utility
    end

    def storage_cost(cluster, parent)
      return @xi unless parent
      times_difference = (cluster.times - parent.times).length
      geosets_difference = (cluster.geographical - parent.geographical).length
      coords_difference = (cluster.geographical.flatten - parent.geographical.flatten).length
      sc = [@xi, times_difference, geosets_difference, coords_difference].sum
      log_debug "StorageCost: #{sc}"
      raise "StorageCost must be > 0" unless sc > 0
      sc
    end

    def recursive_prune(cluster)
      if cluster.children.any?
        unpruned_node = false
        cluster.children.each do |child|
          if recursive_prune(child) < @prune_threshold
            cluster.prune_child(child)
          else
            unpruned_node = true
          end
        end
        # You can't prune a cluster if it still has valid children
        if unpruned_node
          log_debug "Setting score to 1.0 for #{cluster.object_id}"
          1.0
        else
          s = cost_benefit(cluster)
          log_debug "Intermediary node: #{s}"
          s
        end
      else
        s = cost_benefit(cluster)
        log_debug "Score #{s} for #{cluster.osm_key}"
        s
      end

    end

    ##### General helpers

    def merge(clusters)
      clusters = clusters.dup
      base = LandUsageCluster.new()
      clusters.each do |c|
        duped_c = Marshal.load(Marshal.dump(c))
        base.merge_with!(duped_c)
      end
      base
    end

    def closestGroups(distanceMatrix)
      smallest_distance, closest_pairs = distanceMatrix.map { |_, h| h.values.min }.min, []
      log_info "Found minimum: #{smallest_distance}"
      distanceMatrix.each { |outer, h| h.each { |inner, val| closest_pairs << [@clusters[outer], @clusters[inner]] if val == smallest_distance } }
      bar = ProgressBar.create(:title => "Closest pairs", total: closest_pairs.length, format: '%t (%c of %C): |%B|')
      original_total = closest_pairs.length

      while true
        bar.progress = (original_total - closest_pairs.length)
        a1, a2 = overlapping_pairs(closest_pairs)
        break unless a1 and a2
        closest_pairs.delete(a1)
        closest_pairs.delete(a2)
        closest_pairs << (a1 + a2).uniq
      end
      closest_pairs
    end

    def overlapping_pairs(pairs)
      pairs.each_slice(12) do |pairs_slice|
        outer_res = Parallel.map(pairs_slice) do |outer|
          res = []
          pairs.each do |inner|
            next if outer == inner
            if (outer & inner).any?
              res = outer, inner
              break
            end
          end
          res.any? ? res : nil
        end.compact
        return outer_res.first if outer_res.any?
      end
      return nil, nil
    end

    # Indexed by cluster ID not object
    # DistanceMatrix will not automatically store changes to referenced elements, you must force a write
    def distance_matrix(distance_matrix, new)
      bar = ProgressBar.create(:title => "Outer Loop", total: @clusters.length, format: '%t (%c of %C): |%B|')
      @clusters.values.each.with_index do |outer, index|
        hash = distance_matrix[outer.id]
        iteration_clusters = @clusters.values[(index + 1)..-1]
        iteration_clusters = (iteration_clusters & new) unless new.nil? or new.include?(outer) # Only process the new ones
        new_vals = Parallel.map(iteration_clusters) do |inner|
          next(nil) if hash[inner.id]
          [inner.id, hcd(outer, inner)]
        end.compact.to_h
        hash.merge!(new_vals)
        distance_matrix[outer.id] = hash if hash.any?
        bar.increment
      end
      distance_matrix
    end
  end

end

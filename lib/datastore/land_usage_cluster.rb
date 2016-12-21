require 'yaml'

require_relative '../helpers'
require_relative '../geometric_helpers'

module Datastore

  # Class for storing land usage elements in a tree-like hierarchy
  class LandUsageCluster

    attr_reader :times, :tags, :geographical, :children, :osm_key
    attr_accessor :parent, :pruned, :classifier, :instances, :active, :active_keys

    def initialize(hash = {}) # LU element as a hash, loaded from a summary file
      @times = hash[:times] || []
      @tags = hash[:tags].to_a || []
      @geographical = hash[:latlngs] ? [hash[:latlngs]] : []
      @osm_key = hash[:key] || ''
      @children = []
      @pruned = false
      @active = false
    end

    def merge_with!(cluster)
      raise "You can't merge with yourself" if cluster == self
      @times = flatten_times((self.times + cluster.times).uniq)
      @tags = merge_tags(self.tags, cluster.tags)
      @geographical = merge_latlngs((self.geographical + cluster.geographical).uniq)
      @average_duration = nil
      @mode_starthour = nil
      @area = nil
      self
    end

    def add_child(cluster)
      raise "Adding a cluster to itself" if cluster == self
      @children << cluster
    end

    def average_duration # minutes
      @average_duration ||= times.map { |r| (r.last - r.first) / 60.0 }.mean
    end

    def mode_starthour
      @mode_starthour ||= times.map { |r| r.first.hour }.mode
    end

    def area
      @area ||= @geographical.map { |polygon| GeometricHelpers.location_area(polygon) }.sum
    end

    def recursive_print(indent = 0)
      print '  - ' * indent
      puts "#{pruned ? '[X] ' : ''}<Cluster #{id}>"
      children.each { |c| c.recursive_print(indent + 1) } if children
    end

    def unpruned_count
      return 0 if pruned
      count = 1
      unpruned_children = children.select { |c| !c.pruned }
      count += unpruned_children.map { |c| c.unpruned_count }.sum if unpruned_children.any?
      count
    end

    def max_depth(current = 0)
      return current if pruned
      unpruned_children = children.select { |c| !c.pruned }
      return current unless unpruned_children.any?
      return unpruned_children.map { |c| c.max_depth(current + 1) }.max
    end

    def pruned_leaves
      if !children.any?
        return osm_key if pruned
      else
        return children.map { |c| c.pruned_leaves }.flatten.compact
      end
    end

    # Returns an array of all nodes below (and including) this one
    def nodes_array(unpruned_only = false)
      if pruned and unpruned_only
        return nil
      elsif !children.any?
        return self
      else
        return [self, children.map { |c| c.nodes_array(unpruned_only) }].flatten.compact
      end
    end

    def to_s
      "<Cluster #{id}, children: #{@children.length}, pruned: #{pruned}>"
    end

    def inspect
      to_s
    end

    def id
      osm_key.empty? ? object_id : osm_key
    end

    def to_h
      {
          id: id,
          children: children.select { |c| !c.pruned }.map { |c| c.to_h },
          leaf: !children.any?,
          average_duration: average_duration,
          mode_starthour: mode_starthour,
          area: area,
          descendant_ids: descendant_ids,
          ancestor_ids: ancestor_ids,
          sibling_and_descendant_ids: sibling_and_descendant_ids
      }
    end

    def to_yaml
      to_h.to_yaml
    end

    def d3_format(mask = false)
      key = mask ? "#{@osm_key[0]}_#{(@osm_key[2..-1].to_i ** 27).to_s[0..@osm_key.length - 3]}" : @osm_key
      {
          name: key.length == 1 ? '' : key,
          element_names: 'hi',
          tags: @tags.map { |k, v| "#{k}:#{v.kind_of?(Array) ? v.join(';') : v}" }.join(','),
          times: readable_times.join(', '),
          children: @children.map { |c| c.d3_format(mask) },
          pruned: pruned,
          active: active
      }
    end

    def readable_times
      @times.map { |i| "#{i.first.strftime("(%d/%m)%k:%M")}-#{i.last.strftime("#{'(%d/%m)' unless i.first.day == i.last.day}%k:%M")}" }
    end

    def prune_child(child)
      child.pruned = true
    end

    # array of object_ids from all descendants of this node (not inclusive)
    def descendant_ids
      children.select { |c| !c.pruned }.map { |c| [c.id, c.descendant_ids] }.flatten.uniq
    end

    # array of object_ids from all ancestors of this node (not inclusive)
    def ancestor_ids
      parent.nil? ? [] : [parent.id, parent.ancestor_ids].flatten.uniq
    end

    # array of object_ids from all siblings and their descendants (not including this node)
    def sibling_and_descendant_ids
      return [] unless parent
      siblings = parent.children.select { |c| !c.pruned } - [self]
      siblings.map { |s| [s.id, s.descendant_ids] }.flatten.uniq
    end

    # Depth-first highlighting of 'active' nodes
    def highlight_between(range, node = self)

      node.active_keys = node.children.map do |child|
        highlight_between(range, child)
      end.compact.flatten

      node.times.each do |time|
        log_debug "comparing #{range.inspect} and #{time.inspect}"
        if (range & time)
          node.active = true
          break
        end
      end

      if node.active and node.children.none?
        node.tags.to_a
      else
        nil
      end

    end

    private

    def flatten_times(array)

      while true
        a1, a2 = overlapping_times(array)
        break unless a1 and a2
        array.delete(a1)
        array.delete(a2)
        array << ([a1.first, a2.first].min..[a1.last, a2.last].max)
      end

      array.sort_by { |i| i.first }
    end

    def overlapping_times(array)
      array.each do |a1|
        array.each do |a2|
          next if a1 == a2
          return [a1, a2] if (a1.first <= a2.last) and (a2.first <= a1.last)
        end
      end
      return nil
    end

    def merge_tags(tags1, tags2)
      (tags1 + tags2).uniq
    end

    # Merge 2 arrays of geographical elements. If any 2 shapes intersect, they are merged and the convex hull determined
    def merge_latlngs(array)
      compared = Hash.new { |h, k| h[k] = {} }
      while true
        have_merged = false
        array.each do |outer|
          break if have_merged
          array.each do |inner|
            next if outer == inner or compared[outer][inner] or compared[inner][outer]
            if intersects?(outer, inner)
              outer_xy = outer.map { |ll| {x: ll[:latitude], y: ll[:longitude]} }
              inner_xy = inner.map { |ll| {x: ll[:latitude], y: ll[:longitude]} }
              merged = GeometricHelpers.polygon_from(outer_xy + inner_xy)
              merged.map! { |xy| {latitude: xy[:x], longitude: xy[:y]} }
              array.delete(outer)
              array.delete(inner)
              array << merged
              have_merged = true
              break
            else
              compared[outer][inner] = true
            end
          end
        end
        break unless have_merged
      end
      array
    end

    def intersects?(obj1, obj2)

      # Eliminate the base cases
      if obj1.length == 1 and obj2.length == 1
        if obj1.first == obj2.first
          return true
        else
          return false
        end
      end

      xy1 = obj1.map { |ll| {x: ll[:latitude], y: ll[:longitude]} }
      xy2 = obj2.map { |ll| {x: ll[:latitude], y: ll[:longitude]} }

      # Compare the objects
      if obj1.length == 1
        GeometricHelpers.contains_point?(xy2, xy1.first)
      elsif obj2.length == 1
        GeometricHelpers.contains_point?(xy1, xy2.first)
      else
        return true if (xy1 & xy2).any?
        GeometricHelpers.polygon_overlap(xy1, xy2) > 0.0
      end

    end

  end
end

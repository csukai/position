require_relative 'base'

module Clusterers
  class Thresholding < Base

    attr_reader :visits

    # Thresholding is a trivial visit extraction algorithm that creates visits
    # no larger than radius meters that are longer than time minutes in duration
    def initialize(points, radius, time, tmax = nil)

      visit, max_dist = [points.first], 0
      clusters = []

      points[1..-1].each do |point|

        max_dist = [max_dist, max_distance(visit, point)].max

        # Would adding this point cause it to exceed the maximum radius?
        # or is this point > tmax minutes from the previous?
        if max_dist > radius or (tmax and (time_between(visit.last, point) / 60.0) > tmax)

          # Only create a visit if it is longer than the minimum time threshold
          clusters << visit if (time_between(visit.first, visit.last) / 60.0) > time
          visit, max_dist = [point], 0

        else
          visit << point
        end

      end

      clusters << visit if (time_between(visit.first, visit.last) / 60.0) > time
      @visits = summarise_clusters(clusters)
    end

    private

    # Finds the maximum distance between the given point and all others in the visit
    def max_distance(visit, point)
      return 0 unless visit.any?
      visit.map { |p1| distance_between(p1, point) }.max
    end

  end
end

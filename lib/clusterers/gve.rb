require_relative 'base'

module Clusterers
  class GVE < Base

    attr_reader :visits

    # GVE algorithm, following pseudocode in Thomason/2016/JCSS
    def initialize(points, npoints, alpha, beta, tmax = nil)

      raise "beta must be > npoints" unless beta > npoints

      @npoints, @alpha, @beta, @tmax = npoints, alpha, beta, tmax
      @clusters, @visit, @buffer = [], [points.first], [points.first]

      points[1..-1].each do |point|
        process_point(point)
      end

      # Finish the last visit
      @clusters << @visit if @visit.any? and time_between(@visit.first, @visit.last) > 0
      @visits = summarise_clusters(@clusters)
    end

    private

    def process_point(point)
      @buffer.append(point)
      if @buffer.length > @npoints
        @buffer.shift
      end

      if (@tmax and (time_between(@visit.last, point) / 60.0) > @tmax) or moving_away?(@visit, @buffer)
        log_debug "Visit marked as ended"
        if time_between(@visit.first, @visit.last) > 0
          log_debug "Visit stored"
          @clusters << @visit
        else
          log_debug "Visit not stored: no duration"
        end
        @visit = [point]
        @buffer = [point]
      else
        @visit << point
      end
    end

    def moving_away?(visit, buffer)
      log_debug("#{gradient(visit, buffer)} > #{threshold(@alpha, @beta, buffer.length)}")
      if gradient(visit, buffer) > threshold(@alpha, @beta, buffer.length)
        true
      else
        false
      end
    end

    def gradient(visit, buffer)
      sigma_top_left = buffer.map { |p| Float(time_between(buffer.first, p)) * Float(distance_between(centroid(visit), p)) }.sum
      time_arr = buffer.map { |p| Float(time_between(buffer.first, p)) }
      distance_arr = buffer.map { |p| Float(distance_between(centroid(visit), p)) }
      top = (Float(buffer.length) * sigma_top_left) - (time_arr.sum * distance_arr.sum)
      bottom = (Float(buffer.length) * time_arr.map { |i| i ** 2 }.sum) - (time_arr.sum ** 2)
      top / bottom
    end

    def threshold(alpha, beta, buffer_length)
      -1.0 * Math.log(Float(buffer_length) * (1.0 / Float(beta))) * alpha
    end

  end
end

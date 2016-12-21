require_relative 'base'

module Clusterers
  class STA < Base

    attr_reader :visits

    # STA (extraction) algorithm
    def initialize(points, n_buf, d_thres)

      @n_buf, @d_thres , @n_d = n_buf, d_thres, Integer(n_buf / 2.0)

      # Initialise the variables
      @buffer = points[0...@n_buf]
      @sdist = (0...(@n_buf - 1)).map {|i| distance_between(centroid(@buffer[0..i]), centroid(@buffer[0..i + 1]))}.last(@n_d)
      @previous = centroid(@buffer)
      @sta = []
      @clusters = []

      points[@n_buf..-1].each do |point|
        process_point(point)
      end

      @clusters << @sta if @sta.length > @n_buf
      @visits = summarise_clusters(@clusters)

    end

    private

    def process_point(point)
      @buffer.push(point)
      candidate = @buffer[Integer(@n_buf / 2.0)]
      current = centroid(@buffer)
      @sdist << distance_between(@previous, current)
      if weighted_moving_average(@sdist) < @d_thres
        @sta << candidate
      else
        @clusters << @sta if @sta.length > @n_buf
        @sta = []
        @sta << candidate
      end
      @previous = current
      @sdist.shift
      @buffer.shift
    end

    def weighted_moving_average(sdist)
      t = sdist.length - @n_d
      numerator = (0...@n_d).map { |i| Float(@n_d - i) * (sdist[t + i] + sdist[t - i]) }.inject(:+)
      denominator = Float(@n_d * (@n_d + 1))
      numerator / denominator
    end

  end
end

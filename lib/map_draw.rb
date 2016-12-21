require_relative 'geometric_helpers'
require 'rmagick'
include Magick

class MapDraw

  def initialize(plot_area, input_file, output_file)

    @image = Magick::Image.read(input_file).first
    @output = output_file

    # Calculate conversion constants - NB: We treat latitudes and longitudes the same
    @max_lat, @max_lng, @min_lat, @min_lng = plot_area
    @width, @height = @image.columns, @image.rows
    lng_difference, lat_difference = (@max_lng - @min_lng).abs, (@max_lat - @min_lat).abs
    @conversion_constant_lat, @conversion_constant_lng = @height / lat_difference, @width / lng_difference
  end

  def plot_points(trajectory)
    draw_points(trajectory)
    write_out
  end

  # Same as visits, but for when the shapes are plotted instead of their hulls
  def plot_polygons(polygons, trajectory = [], determine_hulls = false, plot_points = true)
    cm = colour_list(polygons.length)
    polygon_points = polygons.map.with_index { |polygon, index| polygon[:elements].map { |point| point.merge({colour: cm[index]}) } }
    draw_points(trajectory) if trajectory.any?
    draw_points(polygon_points.flatten) if plot_points
    draw_shapes(polygon_points, determine_hulls)
    write_out
  end

  def plot_visits(visits, trajectory = [])
    plot_polygons(visits, trajectory, true)
  end

  private

  ##
  # Plot the convex hulls of sets of points
  # Input format: [[p1,p2],[p3,p4,...],...]. Points must have :colour tag set.
  def draw_shapes(point_arrays, determine_hulls = true)
    gc = Magick::Draw.new
    point_arrays.each do |points|

      if determine_hulls
        shape = GeometricHelpers.polygon_from(points.map { |p| {x: lng_conversion(p[:longitude]), y: lat_conversion(p[:latitude])} }).map { |p| [p[:x], p[:y]] }
      else
        shape = points.map { |p| [lng_conversion(p[:longitude]), lat_conversion(p[:latitude])] }
      end

      gc.stroke_width(1)
      gc.stroke(points.first[:colour])
      gc.fill(points.first[:colour])
      #gc.opacity(0.1)
      gc.polygon(*shape.flatten)

    end
    gc.draw(@image)
  end

  def draw_points(points)
    gc = Magick::Draw.new
    points.each do |point|
      gc.stroke_width(0)
      gc.fill(point[:colour] || '#cccccc')
      lng = lng_conversion(point[:longitude].to_f)
      lat = lat_conversion(point[:latitude].to_f)
      gc.circle(lng, lat, lng + 4, lat + 4)
    end
    gc.draw(@image)
  end

  def write_out
    @image.write(@output)
  end

  # Returns a list of +n+ print-safe colours
  def colour_list(number)
    colours = File.read('assets/hex_colours.csv').split(',')
    if number > colours.length
      (colours * (number / colours.length.to_f).ceil).shuffle.take(number)
    else
      n = (colours.length / Float(number)).floor
      (n - 1).step(colours.length - 1, n).map { |i| colours[i] }.shuffle
    end
  end

  def lat_conversion(lat)
    @height - (((lat - @min_lat) * @conversion_constant_lat)) # -10 )
  end

  def lng_conversion(lng)
    ((lng - @min_lng) * @conversion_constant_lng) #+ 10
  end

end
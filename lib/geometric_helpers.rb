require 'haversine'

class GeometricHelpers

  ##
  # These methods work on geometric points made up of hashes of x/y values: {x: ?, y: ?}
  # Trajectory methods convert given lat/lng points into x/y points
  ##

  ###################################
  ###### X/Y Interface Methods ######
  ###################################

  def self.polygon_area(polygon)
    self.private_polygon_area(polygon)
  end

  def self.polygon_overlap(polygon1, polygon2)
    self.private_polygon_overlap(polygon1, polygon2)
  end

  ################################
  ###### Trajectory Methods ######
  ################################

  def self.distance_between(point1, point2)
    Haversine.distance(point1[:latitude], point1[:longitude], point2[:latitude], point2[:longitude]).to_meters
  end

  def self.location_bounding_box(points, overscan = 0.0)
    lats = points.map { |p| p[:latitude] }
    lngs = points.map { |p| p[:longitude] }
    coodintates = {max_lat: lats.max, max_lng: lngs.max, min_lat: lats.min, min_lng: lngs.min}

    if overscan > 0
      lat_overscan = ((coodintates[:max_lat] - coodintates[:min_lat]).abs * overscan)
      lng_overscan = ((coodintates[:max_lng] - coodintates[:min_lng]).abs * overscan)
      coodintates[:max_lat] += lat_overscan
      coodintates[:max_lng] += lng_overscan
      coodintates[:min_lat] -= lat_overscan
      coodintates[:min_lng] -= lng_overscan
    end

    coodintates
  end

  def self.location_area(points)
    xy_points = map_to_xy_plane(points)
    polygon = polygon_from(xy_points)
    polygon_area(polygon)
  end

  def self.location_radius(points)
    return 0.0 if points.length == 1
    points.product(points).map { |j, k| j == k ? 0 : distance_between(j, k) }.max
  end

  # Determines the centroid of the convex hull of a set of <lat,lng> points
  def self.location_centroid(points)
    points = points.map { |p| {latitude: p[:latitude], longitude: p[:longitude]} }
    if points.uniq.length < 4 or points.map { |i| i[:latitude] }.uniq.length == 1 or points.map { |i| i[:longitude] }.uniq.length == 1
      centroid = location_mean(points.uniq)
    else
      xy_points = straight_to_xy_plane(points)
      centroid_xy = centroid(xy_points)
      centroid = {longitude: centroid_xy[:x], latitude: centroid_xy[:y]}
    end
    if centroid[:longitude].nan? or centroid[:latitude].nan?
      ap points
      ap xy_points if defined?(xy_points)
      ap centroid_xy if defined?(centroid_xy)
      ap centroid
      raise "Could not calculate centroid"
    end
    centroid
  end

  def self.location_mean(points)
    {longitude: points.map { |v| v[:longitude] }.average, latitude: points.map { |v| v[:latitude] }.average}
  end

  def self.location_hull(points)
    straight_from_xy_plane(polygon_from(straight_to_xy_plane(points)))
  end

  # Calculates the Dice's coefficient between the convex hull of a cluster and a given polygon
  def self.dice_overlap(points, polygon)

    # Map to an xy plane of polygons
    zero_lat = (points + polygon).map { |c| c[:latitude] }.min
    zero_lng = (points + polygon).map { |c| c[:longitude] }.min

    xy_points = map_to_xy_plane(points, zero_lat, zero_lng)
    xy_points_hull = polygon_from(xy_points)
    xy_polygon = map_to_xy_plane(polygon, zero_lat, zero_lng)

    # Set the IDs so we can identify each polygon later
    xy_points_hull.each { |p| p[:id] = 1 }
    xy_polygon.each { |p| p[:id] = 2 }

    # Generate evenly spaced samples
    mapped_polygons, _, _ = map_to_grid(xy_points_hull + xy_polygon, 100)
    mapped_polygon_1 = mapped_polygons.select { |p| p[:id] == 1 }
    mapped_polygon_2 = mapped_polygons.select { |p| p[:id] == 2 }
    samples = spaced_samples(100, 100)

    # Calculate the Dice's coefficient
    points_within_1 = points_within(mapped_polygon_1, samples)
    points_within_2 = points_within(mapped_polygon_2, samples)
    (2.0 * (points_within_1 & points_within_2).length) / Float(points_within_1.length + points_within_2.length)
  end

  private

  def self.straight_to_xy_plane(points)
    points.map { |p| {x: p[:longitude], y: p[:latitude]} }
  end

  def self.straight_from_xy_plane(points)
    points.map { |p| {longitude: p[:x], latitude: p[:y]} }
  end

  def self.map_to_xy_plane(points, zero_lat = nil, zero_lng = nil)
    zero_lat ||= points.map { |c| c[:latitude] }.min
    zero_lng ||= points.map { |c| c[:longitude] }.min
    points.map do |point|
      {y: Haversine.distance(point[:latitude], zero_lng, zero_lat, zero_lng).to_meters,
       x: Haversine.distance(zero_lat, point[:longitude], zero_lat, zero_lng).to_meters}
    end
  end

  ##########################################
  ###### Calculate area of x/y points ######
  ##########################################

  # Returns the area of arbitrary shapes - Accurate to approximately 2%
  def self.private_polygon_area(polygon)
    mapped_polygon, x_range, y_range = map_to_grid(polygon, 100)
    samples = spaced_samples(100, 100)
    within = points_within(mapped_polygon, samples)
    (Float(within.length) / Float(samples.length)) * (x_range * y_range)
  end

  # Approximate percentage of polygon1 that is also in polygon2
  def self.private_polygon_overlap(polygon1, polygon2)
    polygon1.each { |p| p[:id] = 1 }
    polygon2.each { |p| p[:id] = 2 }

    # Quick test. If the bounding boxes don't overlap, we're done
    p1xmin, p1xmax = polygon1.map { |p| p[:x] }.instance_eval { [min, max] }
    p2xmin, p2xmax = polygon2.map { |p| p[:x] }.instance_eval { [min, max] }
    p1ymin, p1ymax = polygon1.map { |p| p[:y] }.instance_eval { [min, max] }
    p2ymin, p2ymax = polygon2.map { |p| p[:y] }.instance_eval { [min, max] }
    return 0.0 if (p2xmin > p1xmax) or (p1xmin > p2xmax) or (p2ymin > p1ymax) or (p1ymin > p2ymax)

    mapped_polygons, x_range, y_range = map_to_grid(polygon1 + polygon2, 100)
    mapped_polygon_1 = mapped_polygons.select { |p| p[:id] == 1 }
    mapped_polygon_2 = mapped_polygons.select { |p| p[:id] == 2 }

    samples = spaced_samples(100, 100)
    within_1 = points_within(mapped_polygon_1, samples)
    within_2 = points_within(mapped_polygon_2, samples)

    (within_1 & within_2).length / within_1.length.to_f
  end

  def self.map_to_grid(points, size = 100)
    min_x, max_x, min_y, max_y = bounding_box(points)
    x_ratio, y_ratio = (max_x - min_x) / Float(size), (max_y - min_y) / Float(size)
    mapped_points = points.map do |point|
      x, y = (point[:x] - min_x) / x_ratio, (point[:y] - min_y) / y_ratio
      {x: x.nan? ? 0.0 : x, y: y.nan? ? 0.0 : y, id: point[:id]}
    end
    [mapped_points, max_x - min_x, max_y - min_y]
  end

  ##
  # Produces evenly spaced samples over a given area
  # You are strongly recommended to set ticks to a multiple of (size + 1)
  def self.spaced_samples(size, ticks)
    spacing = size / Float(ticks)
    ticks.times.map do |x_i|
      ticks.times.map do |y_i|
        {x: x_i * spacing, y: y_i * spacing}
      end
    end.flatten
  end

  #################################################
  ###### Calculate convex hull of x/y points ######
  #################################################

  ##
  # Return the convex hull of a set of points
  # Algorithm adapted from http://branch14.org/snippets/convex_hull_in_ruby.html
  def self.polygon_from(points)
    sorted_points = points.sort_by { |p| p[:x] }
    left = sorted_points.shift
    right = sorted_points.pop
    lower, upper = [left], [left]
    lower_hull, upper_hull = [], []
    det_func = determinant_function(left, right)
    until sorted_points.empty?
      point = sorted_points.shift
      (det_func.call(point) < 0 ? lower : upper) << point
    end
    lower << right
    until lower.empty?
      lower_hull << lower.shift
      while (lower_hull.size >= 3) &&
          !convex?(lower_hull.last(3), true)
        last = lower_hull.pop
        lower_hull.pop
        lower_hull << last
      end
    end
    upper << right
    until upper.empty?
      upper_hull << upper.shift
      while (upper_hull.size >= 3) &&
          !convex?(upper_hull.last(3), false)
        last = upper_hull.pop
        upper_hull.pop
        upper_hull << last
      end
    end
    upper_hull.shift
    upper_hull.pop
    (lower_hull + upper_hull.reverse).compact
  end

  def self.determinant_function(p0, p1)
    proc { |p| ((p0[:x] - p1[:x]) * (p[:y] - p1[:y])) -
        ((p[:x] - p1[:x]) * (p0[:y] - p1[:y])) }
  end

  def self.convex?(list_of_three, lower)
    p0, p1, p2 = list_of_three
    (determinant_function(p0, p2).call(p1) > 0) ^ lower
  end

  ##############################################################
  ###### Determines whether a point is in a given polygon ######
  ##############################################################

  ##
  # Methods adapted from: http://jakescruggs.blogspot.co.uk/2009/07/point-inside-polygon-in-ruby.html
  # Returns true if the point is within the polygon (array of {x: .., y: ..} objects)
  def self.contains_point?(polygon, point, bounding_box = nil)
    return false if outside_bounding_box?(polygon, point, bounding_box)
    contains_point = false
    i = -1
    j = polygon.length - 1
    while (i += 1) < polygon.length
      a_point_on_polygon = polygon[i]
      trailing_point_on_polygon = polygon[j]
      if between_ys_of_line_segment?(point, a_point_on_polygon, trailing_point_on_polygon)
        if ray_crosses_line_segment?(point, a_point_on_polygon, trailing_point_on_polygon)
          contains_point = !contains_point
        end
      end
      j = i
    end
    return contains_point
  end

  # Returns all points from a given set within the given polygon
  def self.points_within(polygon, points)
    bounding_box = bounding_box(polygon)
    points.select { |point| contains_point?(polygon, point, bounding_box) }
  end

  def self.between_ys_of_line_segment?(point, a_point_on_polygon, trailing_point)
    (a_point_on_polygon[:y] <= point[:y] && point[:y] < trailing_point[:y]) ||
        (trailing_point[:y] <= point[:y] && point[:y] < a_point_on_polygon[:y])
  end

  def self.ray_crosses_line_segment?(point, a_point_on_polygon, trailing_point)
    (point[:x] < (trailing_point[:x] - a_point_on_polygon[:x]) *
        (point[:y] - a_point_on_polygon[:y]) /
        (trailing_point[:y] - a_point_on_polygon[:y]) + a_point_on_polygon[:x])
  end

  # Quick check to see if the point has a chance of being within the polygon
  def self.outside_bounding_box?(polygon, point, bounding_box = nil)
    min_x, max_x, min_y, max_y = (bounding_box or bounding_box(polygon))
    point[:x] < min_x || point[:x] > max_x || point[:y] < min_y || point[:y] > max_y
  end

  # Returns [min_x, max_x, min_y, max_y]
  def self.bounding_box(polygon)
    polygon.map { |p| p[:x] }.instance_eval { [min, max] } +
        polygon.map { |p| p[:y] }.instance_eval { [min, max] }
  end

  ########################################################
  ###### Calculates the centroid of a set of points ######
  ########################################################

  ##
  # Adapted from: https://github.com/geokit/geokit/blob/master/lib/geokit/polygon.rb
  def self.centroid(points)

    polygon = polygon_from(points)
    polygon << polygon.first
    centroid_x, centroid_y, signed_area = 0.0, 0.0, 0.0

    # Iterate over each element in the list but the last item as it's calculated by the i+1 logic
    polygon[0...-1].each_index do |i|
      x0 = polygon[i][:x]
      y0 = polygon[i][:y]
      x1 = polygon[i + 1][:x]
      y1 = polygon[i + 1][:y]
      a = (x0 * y1) - (x1 * y0)
      signed_area += a
      centroid_x += (x0 + x1) * a
      centroid_y += (y0 + y1) * a
    end

    signed_area *= 0.5
    centroid_x /= (6.0 * signed_area)
    centroid_y /= (6.0 * signed_area)

    {x: centroid_x, y: centroid_y}
  end

end
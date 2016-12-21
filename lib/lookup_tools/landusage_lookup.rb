module LookupTools
  class LandusageLookup
    def initialize(file_name)
      @lookup = YAML.load_file(file_name)
      log_info "Lookup file loaded (#{file_name.split('/').last})"
    end

    def [](key)
      @lookup[key]
    end

    ##
    # If dealing with large numbers of points, this method is far better to use than radius_of
    # It ends the first time it encounters points further apart than +radius+ metres, and doesn't store the n x n comparison
    def radius_is_greater_than?(key, radius)
      return @lookup[key][:"greater_than_#{radius}"] if @lookup[key].key?(:"greater_than_#{radius}")
      points = coordinates_for(key, 30)
      # If infinite recursion occurred, there may not be any points. Treat as if it's too large.
      return true if points.none?
      points.each do |p1|
        points.each do |p2|
          if Haversine.distance(p1[:latitude], p1[:longitude], p2[:latitude], p2[:longitude]).to_meters > radius
            @lookup[key][:"greater_than_#{radius}"] = true
            return true
          end
        end
      end
      @lookup[key][:"greater_than_#{radius}"] = false
      false
    end

    def radius_of(key)
      @lookup[key][:radius] ||= GeometricHelpers.location_radius(coordinates_for(key))
    end

    # break_on_depth is the maximum recursive depth allowed, prevents infinite recursion caused by mistakes in the data
    def coordinates_for(key, break_on_depth = nil, current_depth = 0)
      return @lookup[key][:coordinates] if @lookup[key][:coordinates] and @lookup[key][:coordinates].any?
      if break_on_depth and current_depth > break_on_depth
          []
      else
        @lookup[key][:coordinates] = lookup_coordinates_for(key, break_on_depth, current_depth)
      end
    end

    private

    def lookup_coordinates_for(key, break_on_depth, current_depth = 0)
      elem = @lookup[key]
      if key[0] == 'n'
        [{latitude: elem[:lat], longitude: elem[:lon]}]
      else
        # OSM isn't perfect. There exists at least one relation without any members.
        return [] if elem[:members].nil?
        elem[:members].map { |e| coordinates_for(e, break_on_depth, current_depth + 1) }.flatten
      end
    end

  end
end
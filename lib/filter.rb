require_relative 'geometric_helpers'

class Filter
  def initialize(trajectory, lookup, maxradius, delta, n)
    @points, @lookup, @maxradius, @delta, @n = trajectory, lookup, maxradius, delta, n
  end

  # Styled to conform to pseudocode in TOIS paper
  def process(output_file)
    buffer, output_array = [@points.shift], []
    index, counter = nil, 0

    # Build the initial buffer
    while @points.any?

      # If index has not been set, then we are in the first half
      if index.nil? and time_between(buffer.first, @points.first) > @delta

        # If the next point is greater than delta seconds from the first, this half is full
        index = buffer.length - 1

        # If index has been set, then we are in the second half
      elsif !index.nil? and time_between(buffer[index], @points.first) > @delta
        break # Exit the loop as adding the next point would exceed delta
      else
        buffer << @points.shift
      end
    end

    log_info "Initial buffer filled, filtering commencing"

    # Process the current buffer, increment index and maintain the new buffer
    while @points.any?
      log_debug "buffer: #{buffer.length}, index: #{index}, counter: #{counter}"

      filtered = filter(buffer, index)
      if output_file
        output_file.puts([filtered].to_yaml[4..-1]) # Perform the actual filtering
      else
        output_array << filtered
      end

      counter += 1
      index += 1
      log_info "Filtering: completed point #{counter}" if (counter % 100) == 0

      # If the point for consideration is not in the buffer, then add it now
      if index == buffer.length then
        buffer.append(@points.shift)
      end

      # Remove any point from the first part that is not within delta seconds of buffer[index]
      while time_between(buffer.first, buffer[index]) > @delta
        buffer.shift
        index -= 1
      end

      # Add points until doing so would exceed delta seconds from buffer[index]
      while @points.any? and time_between(buffer[index], @points.first) <= @delta
        buffer.append(@points.shift)
      end
    end
    output_array
  end

  def element_weights

    # Override the filter method
    def filter(buffer, index)
      elements = hash_tree(1)
      buffer.each do |point|
        point[:data].each do |element|
          elements[element] << {latitude: point[:latitude], longitude: point[:longitude], accuracy: point[:accuracy], timestamp: point[:timestamp]}
        end
      end

      scored_elements = elements.map do |_, points|
        score = points.map do |point|
          (1.0 / point[:accuracy]) * (1 - (time_between(point, buffer[index]) / Float(@delta)))
        end.sum
        score * Float(points.length)
      end
      scored_elements = scored_elements.select { |i| !i.nan? }
      max = scored_elements.max
      scored_elements.map { |i| i / Float(max) }
    end

    process(nil).flatten.select { |i| !i.nan? }.sort

  end

  private

  def time_between(p1, p2) # MINUTES
    (p1[:timestamp] - p2[:timestamp]).abs / 60.0
  end

  def filter(buffer, index)
    elements = hash_tree(1)
    buffer.each do |point|
      point[:data].each do |element|
        next if @maxradius and @lookup.radius_is_greater_than?(element, @maxradius)
        pwd = {latitude: point[:latitude], longitude: point[:longitude], accuracy: point[:accuracy], timestamp: point[:timestamp]}
        elements[element] << pwd
      end
    end

    return point_with_data(buffer[index], elements.keys) if elements.length <= @n

    begin
      partial = elements.map do |element, points|
        score = points.map do |point|
          log_info "(1.0 / #{point[:accuracy]}) * (1 - (#{time_between(point, buffer[index])} / #{Float(@delta)}))"
          (1.0 / point[:accuracy]) * (1 - (time_between(point, buffer[index]) / Float(@delta)))
        end.sum
        [element, score * Float(points.length)]
      end
      scored_elements = partial.sort_by(&:last).reverse
    rescue Exception => e
      ap elements
      ap partial
      ap scored_elements
      raise e
    end

    # Select the best n elements (using closest if scores are the same)
    lowest_acceptable_score = scored_elements[@n - 1].last
    selection = scored_elements.select { |e| e.last > lowest_acceptable_score }.map(&:first) || []
    with_lowest_score = scored_elements.select { |e| e.last == lowest_acceptable_score }.map(&:first).sort_by do |element|
      begin
        centroid = GeometricHelpers.location_centroid(@lookup.coordinates_for(element))
        Haversine.distance(buffer[index][:latitude], buffer[index][:longitude], centroid[:latitude], centroid[:longitude]).to_meters
      rescue Exception => e
        ap buffer[index]
        ap centroid
        ap @lookup.coordinates_for(element)
        raise e
      end
    end.take(@n - selection.length)

    point_with_data(buffer[index], selection + with_lowest_score)
  end

  def point_with_data(point, elements)
    point = point.dup
    point[:data] = elements
    point
  end
end
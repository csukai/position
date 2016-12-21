# Reads a trajectory YAML file one point at a time
class PartialReader

  LOAD_LIMIT = 100

  def initialize(trajectory_file)
    @file = File.open(trajectory_file, 'r')
    @current_point_string = ''
    @eof = false
    @loaded_points = []
    log_info "PartialReader initialised for #{trajectory_file.split('/').last}"
  end

  def shift
    load_if_needed
    @loaded_points.shift
  end

  def first
    load_if_needed
    @loaded_points.first
  end

  def any?
    load_if_needed
    @loaded_points.any?
  end

  private

  def load_if_needed
    load_next(LOAD_LIMIT) unless @loaded_points.any?
  end

  def load_next(n)
    return [] if @eof
    premature_break = false

    @file.each_line do |line|
      next if line.start_with?('---')

      # If it's a new point, process the previous one
      if line[0] == '-'
        @loaded_points << load_string(@current_point_string) unless @current_point_string.empty?
        premature_break = true
        break if @loaded_points.length >= n
        @current_point_string = ''
      end

      # Add the current line to the point
      @current_point_string += line
    end

    # Add the last point if EOF
    unless premature_break
      @loaded_points << load_string(@current_point_string)
      @eof = true
    end
  end

  def load_string(point)
    YAML.load("---\n#{point}").first
  end

end
require 'colorize'
require 'awesome_print'
require 'ostruct'
require 'optionparser'
require 'yaml'

#######################################################
# Load the config file
#######################################################

begin
  $CONFIG = YAML.load(File.read(File.expand_path('../../config.yml', __FILE__)))
rescue
  $CONFIG = {}
  log_warn "Couldn't load config.yml file, some functionality may not work"
end

#######################################################
# ParamReader provides a wrapper class for OptionParser
#######################################################

class ParamReader

  # Uses OptionParser to extract parameters from ARGV and convert them to an OpenStruct
  def self.parse
    param_obj = OpenStruct.new
    parser = OptionParser.new do |options|
      options.banner = 'Usage: bin/<script> [options]'
      options.on('-d', '--debug', 'Enable debug logging to STDOUT') { |d| $debug = d }
      yield options, param_obj
      options.on('--guard_string STRING', String, 'String to write out on completion') { |s| param_obj.guard_string = s }
      options.on('-h', '--help', 'Display this screen') { puts options; exit }
    end
    parser.parse!
    enforce_requirements(parser, param_obj)
    param_obj
  end

  ##
  # Scans the description text for expected options for '[REQUIRED]' and enforces
  # the requirement by raising an exception unless a method with the same name as
  # the parameter exists in +param_obj+ and is not nil.
  def self.enforce_requirements(parser, param_obj)
    required = parser.to_a.select { |p| p.include? '[REQUIRED]' }.map { |p| p.scan(/\-\-([^\s]*)/).flatten.first }
    required.each { |p| raise(OptionParser::MissingArgument, p) if param_obj[p].nil? }
  end

end

#######################################################
# Logger provides basic message logging with timestamps
#######################################################

def log(type, messages)
  messages.each do |message|
    puts log_string(type, message)
  end
end

def log_info(*messages)
  log(:info, messages)
end

def log_warn(*messages)
  log(:warn, messages)
end

def log_error(*messages)
  log(:error, messages)
end

def log_debug(*messages)
  return unless $debug
  log(:debug, messages)
end

def log_string(type, message)
  "#{Time.now} [#{Process.pid}] #{log_colourise(type, type.to_s.upcase)}: #{log_colourise(type, message.to_s)}"
end

def log_colourise(type, message)
  case type
    when :warn
      message.to_s.yellow
    when :error
      message.to_s.red
    when :debug
      message.to_s.blue
    when :status
      message.to_s.green
    else
      message.to_s
  end
end

#######################################################
# Add a couple of useful methods for arrays
#######################################################

class Array
  def mode
    freq = inject(Hash.new(0)) { |h, v| h[v] += 1; h }
    sort_by { |v| freq[v] }.last
  end

  def mean
    return nil unless any?
    sum / Float(length)
  end

  def average
    mean
  end

  def sum
    inject(:+)
  end

  def index_of_max
    each_with_index.max[1]
  end

  def index_of_min
    each_with_index.min[1]
  end

  def append(val)
    self << val
  end
end

#######################################################
# Determine the value in a string
#######################################################

class String
  def to_useful
    ((float = Float(self)) && (float % 1.0 == 0) ? float.to_i : float) rescue self
  end
end

#######################################################
# Calculate range intersection
#######################################################

class Range
  def &(other)
    return nil if (self.last < other.first or other.last < self.first)
    [self.first, other.first].max..[self.last, other.last].min
  end

  def duration
    self.last - self.first
  end
end


#######################################################
# Constructor for a fixed-depth recursive hash
#######################################################

def hash_tree(max = 100, depth = 1)
  Hash.new { |h, k| h[k] = depth >= max ? [] : hash_tree(max, depth + 1) }
end


#######################################################
# Recursively convert hashes to symbol-indexed hashes
#######################################################

class Object
  def deep_clean
    return self.reduce({}) do |memo, (k, v)|
      memo.tap { |m| m[k.kind_of?(String) ? k.to_s.gsub(':', '_').to_sym : k] = v.deep_clean }
    end if self.is_a? Hash

    return self.reduce([]) do |memo, v|
      memo << v.deep_clean; memo
    end if self.is_a? Array

    return self.to_i if self.is_a?(String) and self.to_i.to_s == self

    self
  end
end
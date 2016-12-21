require 'java'

require_relative '../predictors/jar/weka.jar'

java_import 'java.io.StringReader'
java_import 'weka.core.converters.ArffLoader'

module Datastore
  class InstanceSet

    attr_reader :test_array, :train_array, :class_values

    # Takes an array of hashes: [{ key_1: val1, key_2: val2, class: class_val }, ...]
    def initialize(array, attributes, override_class_vals = nil)
      @array, @attributes = array, attributes
      @class_values = override_class_vals || @array.map { |i| i[:class] }.uniq.sort # Do not sort if using override!
    end

    def test_train_split
      midpoint = @array.length / 2
      @test_array, @train_array = @array[0..midpoint], @array[midpoint + 1..-1]
      [weka_instances(@test_array), weka_instances(@train_array)]
    end

    def cross_validation_sets(k)
      instances_per_slice = (@array.length / k.to_f).ceil
      return @array.each_slice(instances_per_slice).to_a, @attributes
    end

    def weka_instances(data = @array)
      string_reader = StringReader.new(to_arff(data))
      arff_reader = ArffLoader::ArffReader.new(string_reader)
      arff_instances = arff_reader.getData
      arff_instances.setClassIndex(@attributes.keys.find_index(:class))
      arff_instances
    end

    private

    def to_arff(data = @array)
      output = []
      output << "@RELATION relation"
      output += attributes_for(data)
      output << "\n@DATA"
      output << data.map { |i| @attributes.keys.map { |k| i[k] }.join(',') }
      output.flatten.join("\n")
    end

    # Determine the attributes sets for these instances
    def attributes_for(data)
      @attributes.map do |key, type|
        if key == :class
          values = @class_values
        else
          values = data.map { |a| a[key] }.uniq.sort
        end
        "@ATTRIBUTE #{key} #{type == :nominal ? "{#{values.join(',')}}" : 'NUMERIC'}"
      end
    end

  end
end
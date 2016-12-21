require_relative 'base'
require_relative 'jar/HMM.jar'

java_import('weka.classifiers.bayes.HMM') { |_, name| "WEKA_#{name}" }
java_import('java.io.PrintStream')
java_import('java.io.ByteArrayOutputStream')
java_import('java.lang.System')
java_import('weka.core.Instances')
java_import('weka.core.DenseInstance')
java_import('weka.core.Attribute')

module Predictors
  class HMM < Base

    ##
    # Classifiers are passed normal instances, not relational ones, but HMMs require relations
    # We convert them here before they are used for evaluation
    def initialize(instances, order)
      @classifier = WEKA_HMM.new
      raise unless order and order >= 1
      super(convert_instances_to_relation(instances, order))
    end

    def evaluate
      suppress_java_output
      super
      reinstate_java_output
    end

    private

    def suppress_java_output
      $sys_out_stream = System.out
      my_output_stream = ByteArrayOutputStream.new
      System.setOut(PrintStream.new(my_output_stream))
    end

    def reinstate_java_output
      System.setOut($sys_out_stream)
    end

    def convert_instances_to_relation(instances, order)

      # Create a new instance set
      new_instances = Instances.new(instances)
      new_instances.delete

      # Generate the specific format required for a relational attribute
      class_values = new_instances.classAttribute.enumerateValues.to_a
      relational_attributes = [Attribute.new('LocationID', class_values)]
      relational_instances = Instances.new('Relational', java.util.ArrayList.new(relational_attributes), 0)
      new_instances.insertAttributeAt(Attribute.new('LocationSequences', relational_instances, 0), 0)

      # Add the old instances back to the new instance set
      instances.each_cons(order) do |instance_sequence|
        class_instance = instance_sequence.pop
        instance_values = []

        # List the previous instance's locations as the relational values
        relational_data = Instances.new(new_instances.attribute(0).relation(), 0)
        instance_sequence.each { |instance| relational_data.add(DenseInstance.new(1.0, [Float(instance.classValue)].to_java(:double))) }
        instance_values << new_instances.attribute(0).addRelation(relational_data)

        # Add the new instance, that contains the relation and the old values, to the new instance set
        new_instances.add(DenseInstance.new(1.0, (instance_values + class_instance.toDoubleArray.to_a).to_java(:double))) #
      end

      new_instances
    end

  end
end
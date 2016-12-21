require 'java'
require_relative 'jar/weka.jar'

java_import 'weka.classifiers.Evaluation'
java_import('java.util.Random') { |_, name| "J#{name}" }
java_import('weka.core.UnsupportedAttributeTypeException')

module Predictors
  class Base

    def initialize(instances)
      raise 'Need to set @classifier before calling super' unless @classifier
      # raise '10 instances are needed at a minimum' unless instances.length > 9
      @instances = instances
      @classifier_override_prediction = false
      @evaluator = nil
      @classifier.setSeed(rand(2147483646).to_java(:int))
    end

    def evaluate()
      @evaluator = Evaluation.new(@instances)

      if @instances.numClasses() == 1
        log_warn "Skipping evaluation because of unary class"
        @evaluator = OpenStruct.new()
        @evaluator.predictions = [OpenStruct.new({actual: :unary, predicted: :unary, distribution: [1.0]})] * @instances.numInstances
        @evaluator.numInstances = @instances.numInstances
        @evaluator.pctCorrect = 100.0
        @evaluator.pctIncorrect = 0.0
        @evaluator.pctUnclassified = 0.0
      else
        @evaluator.crossValidateModel(@classifier, @instances, 10, JRandom.new(rand))
        raise "Prediction impossible" if @instances.length < 15 and @evaluator.pctCorrect == 0.0
      end
    end

    def evaluation_statistics
      evaluate unless @evaluator
      predictions = @evaluator.predictions.map { |p| {actual: p.actual, predicted: p.predicted, confidence: p.distribution.max, result: p.predicted == p.actual ? :correct : :incorrect} }
      {instances: @evaluator.numInstances, correct: @evaluator.pctCorrect, incorrect: @evaluator.pctIncorrect, unclassified: @evaluator.pctUnclassified, predictions: predictions}
    end

    def distributionForInstance(instance)
      begin
        @classifier.distributionForInstance(instance)
      rescue
        log_warn "Weka failed to return a distribution for instance."
        Array.new(@instances.attribute('class').numValues, 0.0)
      end
    end

    # Catch all other requests and pass them on to the classifier
    def method_missing(method_sym, *arguments)
      raise unless @classifier
      @classifier.send(method_sym, *arguments)
    end

    def classifyInstance(instance)
      @classifier_override_prediction || @classifier.classifyInstance(instance)
    end

    def train
      begin
        @classifier.buildClassifier(@instances)
      rescue UnsupportedAttributeTypeException
        @classifier_override_prediction = 0.0
      rescue Exception => e
        return if @instances.none?
        raise e
      end
    end

  end
end
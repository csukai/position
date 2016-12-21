require_relative 'base'

java_import('weka.classifiers.bayes.NaiveBayes') { |_, name| "Weka#{name}" }

module Predictors
  class NaiveBayes < Base

    def initialize(instances, _ = true)
      @classifier = WekaNaiveBayes.new
      @instances = instances
      @classifier_override_prediction = false
    end

  end
end
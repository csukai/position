require_relative 'base'

java_import('weka.classifiers.functions.Logistic') { |_, name| "Weka#{name}" }

module Predictors
  class Logistic < Base

    def initialize(instances, _ = true)
      @classifier = WekaLogistic.new
      @instances = instances
      @classifier_override_prediction = false
    end

  end
end
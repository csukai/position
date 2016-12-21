require_relative 'base'
require_relative 'jar/libsvm-mute.jar'
require_relative 'jar/libsvm-wrapper.jar'

java_import('weka.classifiers.functions.LibSVM')
java_import('weka.core.SelectedTag')

module Predictors
  class SVM < Base

    def initialize(instances, calculate_probabilities = false)
      @classifier = LibSVM.new
      super(instances)

      # When using SVC/SVR, make sure to sanity check results
      @classifier.setProbabilityEstimates(true) if calculate_probabilities
    end

  end
end
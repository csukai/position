require_relative 'base'

java_import('weka.classifiers.trees.J48') { |_, name| "Weka#{name}" }

module Predictors
  class J48 < Base

    def initialize(instances, _ = true)
      @classifier = WekaJ48.new
      super(instances)
    end

  end
end
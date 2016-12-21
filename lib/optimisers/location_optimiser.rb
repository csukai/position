require_relative 'base'

# Use the Simulated Annealing optimiser to optimise visit extraction and clustering parameters
module Optimisers
  class LocationOptimiser < Base

    def initialize(kmax, ve, vc, trajectory, increments, parameter_validator, outer_evaluator, start_state = nil)

      # Load the clusterers
      require_relative "../clusterers/#{ve.downcase}"
      require_relative "../clusterers/#{vc.downcase}"

      # Identify required parameters
      # TODO: There is probably a better way that does not depend on method signatures remaining static...
      ve_params = Clusterers.const_get(ve).instance_method(:initialize).parameters.map(&:last)[1..-1]
      vc_params = Clusterers.const_get(vc).instance_method(:initialize).parameters.map(&:last)[1..-1]

      # Define a function to generate neighbour states and select one
      neighbour_function = lambda do |state|
        state = YAML.load(state.to_yaml)
        valid_neighbours = state.keys.map do |key|
          candidate_pos, candidate_neg = state.dup, state.dup
          candidate_pos[key] += increments[key]
          candidate_neg[key] -= increments[key]
          [candidate_pos, candidate_neg]
        end.flatten.uniq.select { |s| parameter_validator.call(s) }
        raise unless valid_neighbours.any?
        valid_neighbours.sample
      end

      # Define a function to evaluate a given set of parameters (state)
      # Returns a score and summary information for later storage (can be anything)
      inner_evaluator = lambda do |state|

        # Perform clustering
        ve_clusterer = Clusterers.const_get(ve).new(trajectory, *ve_params.map { |p| state[p] })
        vc_clusterer = Clusterers.const_get(vc).new(ve_clusterer.visits, *vc_params.map { |p| state[p] })

        # Hand over to the outer evaluator to give the locations a score
        outer_evaluator.call(vc_clusterer.locations)
      end

      super(kmax, neighbour_function, inner_evaluator)

      # Construct a start state
      if start_state
        @start_state = start_state
        raise("Invalid start state") unless parameter_validator.call(@start_state)
      else
        @start_state = start_state || increments.select { |k, _| (vc_params + ve_params).include?(k) }
        begin
          @start_state = (vc_params + ve_params).map { |k| [k, (increments[k] * rand(10)).round(1)] }.to_h
          log_debug "Start state selected: #{@start_state.inspect}"
        end until parameter_validator.call(@start_state)
      end

    end

    def search
      super(@start_state)
    end

  end
end
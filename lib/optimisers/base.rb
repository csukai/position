# Uses the Simulated Annealing algorithm to optimise for some criteria
module Optimisers
  class Base

    ##
    # +block+ is an minimising evaluator lambda, which *must* return 0 for optimal parameters
    def initialize(kmax, neigbour_generator, evaluator)
      @neigbour_generator = neigbour_generator
      @evaluator = evaluator
      @kmax = kmax
    end

    def search(start_parameters)

      state = start_parameters
      cost, summary = @evaluator.call(state)

      results = @kmax.times.map do |k|

        break if cost == 0

        candidate = @neigbour_generator.call(state)
        candidate_cost, candidate_summary = @evaluator.call(candidate)

        cost_before = cost

        if !candidate_cost.nan? and (candidate_cost < cost) or (pf = probability_function(cost, candidate_cost, temperature(k / Float(@kmax)))) > (r = rand)
          state, cost, summary = candidate, candidate_cost, candidate_summary
        end

        log_debug "candidate: #{candidate_cost}, current: #{cost_before} | pf: #{pf}, r: #{r}"
        log_debug "taken?: #{candidate_cost < cost_before or pf > r}"

        {state: state, cost: cost, summary: summary}

      end

      results
    end

    private

    def probability_function(current, new, temperature)
      raise("You shouldn't be asking this") if new < current
      Math.exp((-1.0 * (current - new).abs) / Float(temperature))
    end

    # Returns the temperature for the fraction of time budget expended
    def temperature(r)
      0.985 ** (r * 500)
    end

  end
end
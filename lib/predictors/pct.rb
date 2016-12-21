require_relative '../datastore/instance_set'
require_relative 'svm'
require_relative 'j48'
require_relative 'logistic'
require_relative 'naive_bayes'

##
# Predictive Context Tree - a Context tree that is also a prediction model.
##

module Predictors
  class PCT

    def initialize(file, instance_set, follow_threshold, model)
      data = YAML.load_file(file)
      @lookup_hash = {}
      @instance_set = instance_set
      @follow_threshold = follow_threshold
      @model = model

      # Handle pruned trees - always load the full tree, but mark only the nodes in the pruned tree as valid
      @root = load_tree(data[:tree])
      @valid_nodes = @lookup_hash.keys
      @root = load_tree(data[:unpruned_tree]) if data[:unpruned_tree]
    end

    def find_node(id)
      @lookup_hash[id]
    end

    def nodes_list
      @lookup_hash.keys
    end

    def to_s(node = @root, indent = 0)
      s = "#{'  - ' * indent} <node #{node.id}>\n"
      s + node.children.map { |c| to_s(c, indent + 1) }.join if node.children
    end

    ##
    # Use the trained model to predict a given instance.
    #
    # Params:
    #   - `leaf_only`: mandatory leaf node prediction (if false or unspecified, any node can be predicted)
    #   - `multilabel`: allows prediction of more than one (non related) node when true
    def classify_instance(instance, params = {})
      raise unless @attributes
      instance = instance.dup
      instance[:class] = '?'
      instance = Datastore::InstanceSet.new([instance], @attributes, ['yes', 'no']).weka_instances.get(0)
      recursively_classify(instance, @root, params)
    end

    # Cross-validate the PCT and output the statistics
    def evaluation_statistics(leaf_only, multilabel)

      slices, @attributes = @instance_set.cross_validation_sets(10)
      overall_results = Hash.new { |h, k| h[k] = 0 }

      slices.map.with_index do |slice, index|
        test, train = slice, slices.select.with_index { |_, ind| ind != index }.flatten
        log_debug "TEST: #{test.length}, TRAIN: #{train.length}"

        # Train the tree
        @root.children.each { |c| recursively_construct_model(c, train) }

        # Classify the test instances
        # NOTE: single classes are symbols, multiple are '-' separated strings
        # NOTE: classify_instance always returns an array
        # classify_instance returns a hash of id: confidence
        comparisons = if multilabel
                        test.map do |test_instance|
                          predicted = classify_instance(test_instance, leaf_only: leaf_only, multilabel: true)
                          actual = test_instance[:class].split('-').map { |i| i.to_sym }.sort
                          [predicted, actual]
                        end
                      else
                        test.map do |test_instance|
                          predicted = classify_instance(test_instance, leaf_only: leaf_only, multilabel: false)
                          actual = test_instance[:class]
                          [predicted, [actual]]
                        end
                      end

        results = comparisons.map do |predicted, actual|
          predicted_nodes = predicted.keys.sort_by { |i| i.to_s }
          all_descendants = predicted_nodes.map { |pred| find_node(pred).descendant_ids }.flatten.uniq
          prediction_proportion = all_descendants.length / Float(@lookup_hash.length - 1)

          result = if predicted_nodes == actual
                     :correct
                   elsif context_correct?(predicted_nodes, actual)
                     :context_correct
                   elsif (predicted_nodes & actual).any?
                     :overlap
                   elsif context_overlap?(predicted_nodes, actual)
                     :context_overlap
                   else
                     :incorrect
                   end

          log_debug "Result: #{result}, confidence: #{predicted.values.join(',')}"

          {result: result, coverage: prediction_proportion, confidence: predicted.values.mean}
        end

        results_only = results.map { |r| r[:result] }
        [:correct, :context_correct, :overlap, :context_overlap, :incorrect].each do |result|
          overall_results[result] += results_only.count(result)
        end

        results
      end.compact

      overall_results
    end

    private

    # Load the tree from a hash object
    def load_tree(tree_hash)
      tree_hash[:children].map! { |c| load_tree(c) }
      node = OpenStruct.new(tree_hash)
      @lookup_hash[node.id] = node
      node
    end

    ###############################
    # Classifier Training
    ###############################

    # Construct a hierarchical classification model out of the context tree by training one classifier per node
    def recursively_construct_model(node, instances)
      weka_instances = Datastore::InstanceSet.new(instances_for(node, instances), @attributes, ['yes', 'no']).weka_instances
      node.instances = weka_instances
      node.classifier = Predictors.const_get(@model).new(weka_instances)
      node.classifier_confidence = Predictors.const_get(@model).new(weka_instances, true)
      node.classifier.train
      node.classifier_confidence.train
      node.children.each { |c| recursively_construct_model(c, instances) }
    end

    ##
    # Select appropriate instances for a given node and set the class variable to be yes/no
    # See preamble for details of which nodes are yes/no/ignored
    def instances_for(node, instances)
      instances.map do |instance|
        instance = instance.dup

        if instance[:class].kind_of?(String)
          class_array = instance[:class].split('-').map(&:to_sym)
        else
          class_array = instance[:class].kind_of?(Array) ? instance[:class] : [instance[:class]]
        end

        instance[:class] = if (class_array & [node.id]).any?
                             :yes
                           elsif (node.descendant_ids & class_array).any?
                             :yes
                           elsif (node.ancestor_ids & class_array).any?
                             :no
                           elsif (node.sibling_and_descendant_ids & class_array).any?
                             :no
                           else
                             nil
                           end
        instance
      end.select { |i| !i[:class].nil? }
    end

    ###############################
    # Instance Classification
    ###############################

    # Classify the given instance recursively to find the point it belongs in the tree
    # lowest_confidence is the lowest confidence encountered so far while traversing this prediction
    def recursively_classify(instance, node, params, lowest_confidence = 1.0)

      valid_children = node.children.select { |c| @valid_nodes.include?(c.id) }
      return {node.id => lowest_confidence} unless valid_children.any?

      # Calculate the probability of a 'yes' from each child
      responses = valid_children.map do |child|
        test_set = child.instances.dup
        test_set.add(instance)

        # Sanity check the response from the SVM/SVR classifiers
        response = child.classifier.distributionForInstance(instance)[0] # 0 is yes, 1 is no
        confidence = child.classifier_confidence.distributionForInstance(instance)[0]

        res = if response == 1 and confidence >= 0.5
                confidence
              elsif response == 0 and confidence <= 0.5
                confidence
              else
                log_debug "Res: #{response}, Con: #{confidence} - Selected #{response}"
                response
              end

        log_debug "Comparing against #{child.id}: #{res}"
        res
      end


      selected = select_children(responses.each_with_index.to_a, params)
      log_debug "Selected children to explore: #{selected.map { |s| valid_children[s.last].id }.join(',')}"
      return {node.id => lowest_confidence} unless selected.any?
      selected.map { |s| recursively_classify(instance, valid_children[s.last], params, [s.first, lowest_confidence].min) }.flatten.compact.uniq.inject(&:merge)
    end

    # Decides which child/children to persue recursively for classification
    def select_children(responses_with_index, params)
      responses_with_index = responses_with_index.sort_by { |i| i.first }.reverse
      greater_than_even = responses_with_index.select { |r| r.first >= @follow_threshold }
      best_score = responses_with_index.first.first
      top_ranked = responses_with_index.select { |i| i.first == best_score }

      selected = if params[:leaf_only] # If leaf_only is enabled, we have to choose something even if none are > follow_threshold
                   greater_than_even.any? ? greater_than_even : top_ranked
                 else
                   greater_than_even
                 end

      # If multilabel is allowed, return them all, otherwise take the first
      params[:multilabel] ? selected : [selected.first].compact
    end

    ###############################
    # Evaluation
    ###############################

    def context_correct?(predicted, actual)

      # remove anything that matches exactly
      correct = (predicted & actual)
      predicted_minus_correct = predicted - correct
      actual_minus_correct = actual - correct

      # is what's left contextual?
      actual_ancestors = actual_minus_correct.map { |a| log_debug a; (find_node(a)).ancestor_ids }.flatten
      predicted_minus_correct.each { |p| return false unless actual_ancestors.include?(p) }
      predicted_descendants = predicted_minus_correct.map { |p| find_node(p).descendant_ids }.flatten
      actual_minus_correct.each { |a| return false unless predicted_descendants.include?(a) }

      true
    end

    def context_overlap?(predicted, actual)
      raise('This prediction should have been marked as Overlap') if (predicted & actual).any?
      actual_ancestors = actual.map { |a| (find_node(a)).ancestor_ids }.flatten
      (predicted & actual_ancestors).any?
    end

  end
end
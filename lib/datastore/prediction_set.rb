require_relative 'instance_set'

# Instance set for next location prediction problems
module Datastore
  class PredictionSet < InstanceSet

    attr_reader :interactions

    def initialize(summarised)
      interactions = summarised.map { |key, hash| hash[:times].map { |times| OpenStruct.new({time: times, cluster_id: key}) } }.flatten.sort_by { |i| i.time.first }
      interactions = detect_and_process_overlaps(interactions)
      @interactions = interactions
      instances_array = interactions.each_cons(2).to_a.map do |current_interaction, next_interaction|
        start_time = current_interaction.time.first
        {
            dayofyear: start_time.yday,
            dayofweek: start_time.wday,
            hourofday: start_time.hour,
            minuteofhour: start_time.min,
            duration: (current_interaction.time.last - start_time).to_i / 60,
            cluster_id: current_interaction.cluster_id,
            class: next_interaction.cluster_id
        }
      end

      super(instances_array, {dayofyear: :numeric, dayofweek: :nominal, hourofday: :numeric, minuteofhour: :numeric, duration: :numeric, cluster_id: :nominal, class: :nominal})
    end

    def detect_and_process_overlaps(interactions)
      return interactions unless interactions.each_cons(2).map { |i1, i2| !(i1.time & i2.time).nil? }.include?(true)

      merged = []
      current_time = interactions[0].time
      current_set = [interactions[0]]
      index = 1
      until interactions[index].nil? do
        if (current_time & interactions[index].time).nil?
          # finalise current_set
          merged << OpenStruct.new({time: (current_set.map { |i| i.time.first }.min..current_set.map { |i| i.time.last }.max), cluster_id: current_set.map(&:cluster_id).uniq.sort.join('-')})
          current_time = interactions[index].time
          current_set = [interactions[index]]
        else
          current_set << interactions[index]
        end
        index += 1
      end

      merged

    end

  end
end
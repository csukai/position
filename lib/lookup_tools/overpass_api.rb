require 'rest-client'
require 'uri'
require 'json'
require 'ostruct'

require_relative '../helpers'

module LookupTools
  class OverpassAPI

    API_ADDRESS = $CONFIG[:overpass_api][:server]
    API_PORT = $CONFIG[:overpass_api][:port]

    TAG_STRIP_ALL = /source.*|wikipedia|note|name.*|alt.*|created.*|fixme.*|todo.*|website|phone|layer|url/
    KEY_STRIP_ALL = /id|type/

    # Requests and stores the land usage information for the provided point
    def initialize(point)
      log_debug "OverpassAPI instantiated with point: #{point.inspect}"
      @point, query, count = point, overpass_inclusive_ql(point), 0

      begin

        @data = JSON.parse(overpass_query(query)).deep_clean
        count = 0

      rescue => e

        if count >= 20
          log_warn "Exception received from Overpass API: #{e.message}. Giving up."
          raise e
        else
          log_warn "Exception received from Overpass API: #{e.message}. Retrying (in up to 5 minutes)..."
          count += 1
          sleep(rand * 5 * 60)
          retry
        end

      end
    end

    # Returns a location-less summary of the elements (ignoring nodes)
    def summary_list
      return @summary_list unless @summary_list.nil?
      neighbourhood_summary = @data[:elements].select { |e| e[:tags] and e[:tags].keys.select { |k| k !~ TAG_STRIP_ALL }.any? }.map { |e| element_key(e) }
      log_warn "No data to return for point: #{@point.inspect}" unless neighbourhood_summary.any?
      log_debug "Lookup complete, summary items: #{neighbourhood_summary.length}"
      @summary_list = neighbourhood_summary
    end

    # Returns a hash of types storing all details of elements encountered
    def full_details
      return @full_details unless @full_details.nil?
      @full_details = @data[:elements].each_with_object({}) do |e, o|
        e = e.dup
        e[:tags] = e[:tags].map { |k, v| [k.to_s.downcase, v.to_s.downcase] }.to_h if e[:tags]
        e[:tags].each { |k, _| e[:tags].delete(k) if k.to_s =~ TAG_STRIP_ALL } if e[:tags]
        o[element_key(e)] = e
        e.each { |k, _| e.delete(k) if k.to_s =~ KEY_STRIP_ALL }
        e.delete(:tags) if e[:tags] and e[:tags].none?
        e[:members].map! { |m| :"#{m[:type][0]}_#{m[:ref]}" } if e[:members]
        if e[:nodes]
          e[:members] = e[:nodes].map { |n| :"n_#{n}" }
          e.delete(:nodes)
        end
      end
    end

    private

    # Determines the element's key
    def element_key(element)
      :"#{element[:type][0]}_#{element[:id]}"
    end

    # Generates a query in OverpassQL for extracting features
    def overpass_inclusive_ql(point)
      query = <<-EOF.gsub(/\s\s+/, '')
          [out:json][maxsize:1073741824][timeout:86400];

          is_in(#{point[:latitude].to_s('F')},#{point[:longitude].to_s('F')})->.current_area;

          (
            node(around:#{point[:accuracy].to_s},#{point[:latitude].to_s('F')},#{point[:longitude].to_s('F')});
            way(around:#{point[:accuracy].to_s},#{point[:latitude].to_s('F')},#{point[:longitude].to_s('F')});
            <;
          )->.partial;

          (
            node.partial["admin_level"!~".*"];
            way.partial["admin_level"!~".*"];
            rel.partial["admin_level"!~".*"]['boundary'!='administrative']['boundary'!='ceremonial'];
          )->.partial_filtered;

          .partial_filtered is_in->.partial_areas;

          (
            .partial_filtered;
            way(pivot.current_area)["admin_level"!~".*"];
            rel(pivot.current_area)["admin_level"!~".*"]['boundary'!='administrative']['boundary'!='ceremonial'];
            way(pivot.partial_areas)["admin_level"!~".*"];
            rel(pivot.partial_areas)["admin_level"!~".*"]['boundary'!='administrative']['boundary'!='ceremonial'];
          )->.unioned;

          (
            .unioned;
            .unioned >>;
          )->.unioned_recursed;

          .unioned_recursed out;
      EOF
      query.gsub('<', '%3C').gsub('>', '%3E').gsub(' ', '%20').gsub('"', '%22')
    end

    def overpass_query(text)
      log_debug "http://#{API_ADDRESS}:#{API_PORT}/api/interpreter?data=#{text}"
      response = RestClient::Request.execute(method: :get, url: "http://#{API_ADDRESS}:#{API_PORT}/api/interpreter?data=#{text}", timeout: 87400)
      log_debug "Received Response: #{response.length}"
      response.body
    end

  end
end



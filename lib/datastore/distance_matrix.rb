module Datastore
  class DistanceMatrix

    include Enumerable
    require 'fileutils'
    require 'parallel'

    # Indexed by ID

    def initialize(clusters)
      if clusters.length > 10000
        log_warn "Entering disk-based storage mode"
        @memory_mode = false
        @results_dir = "/tmp/#{Time.now.to_i}#{('a'..'z').to_a.sample(4).join}"
        system "mkdir -p #{@results_dir}"
        @files = {} # id => file_path
      else
        @memory_mode = true
        @store = Hash.new { |h, k| h[k] = {} }
      end
    end

    def [](key)
      if @memory_mode
        # Required to prevent checking whether a value exists from automatically creating it
        # Also prevents automatic write-back to be in line with disk-based storage
        @store.include?(key) ? @store[key] : {}
      else
        @files[key] ? load_file(@files[key]) : {}
      end
    end

    def []=(key, value)
      if @memory_mode
        @store[key] = value
      else
        @files[key] = file_path(key) unless @files[key]
        write_file(@files[key], value)
      end
    end

    def delete(keys)
      keys = [keys] unless keys.kind_of?(Array)
      if @memory_mode
        keys.each do |key|
          @store.delete(key)
          @store.each { |_, v| v.delete(key) }
        end
      else
        keys.each do |key|
          if @files[key]
            delete_file(@files[key])
            @files.delete(key)
          end
        end

        Parallel.each(@files.values) do |path|
          contents = load_file(path)
          keys.each { |key| contents.delete(key) }
          log_info "Writing #{path}"
          write_file(path, contents)
        end
      end
    end

    def each(&block)
      if @memory_mode
        @store.each(&block)
      else
        @files.each { |key, path| yield(key, load_file(path)) }
      end
    end

    def clean_up
      FileUtils.rm_rf(@results_dir) unless @memory_mode
    end

    private

    def load_file(path)
      Marshal.load(File.read(path))
    end

    def write_file(path, data)
      File.write(path, Marshal.dump(data))
    end

    def delete_file(path)
      log_info "Deleting #{path}"
      File.delete(path)
    end

    def file_path(key)
      "#{@results_dir}/#{key}.dat"
    end

  end
end
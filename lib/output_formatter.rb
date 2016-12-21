class OutputFormatter

  attr_reader :loaded_results, :unique_values

  ##
  # to_extract is a hash of new_key => file_key or lambda
  # If a lambda is provided, it will be executed on the file once loaded, otherwise the file is assumed to contain an array or hash and the key used
  def initialize(regexes, to_extract)
    @files = regexes.map { |r| Dir[r.sub('~', '/Users/ali')] }.flatten
    @unique_values = Hash.new { |h, k| h[k] = {} }
    errors, nils = false, false

    @loaded_results = @files.map do |file|
      log_debug file
      parameters = file.split('/').last.split(/~|--/).map { |component| component.split('-') }
      parameters = parameters.map { |k, v| [k.to_sym, v.to_useful] }.to_h
      parameters.each { |k, v| @unique_values[k][v] = true }
      loaded = YAML.load(File.read(file))
      parameters[:filepath] = file
      to_extract.each do |k, v|
        begin
          parameters[k] = v.kind_of?(Proc) ? v.call(loaded) : loaded[v]
          @unique_values[k][parameters[k]] = true
          if parameters[k].nil?
            log_warn "Parameter #{k} for file #{file} produced nil result" if $debug
            nils = true
          end
        rescue Exception => e
          log_debug "Unable to extract parameter #{k} for file #{file}"
          errors = true
        end
      end
      parameters
    end

    log_warn 'Some parameters contained nil values. Run with -d to see details.' if nils
    log_warn 'There were errors extracting some parameters. Usually this means that there are parameters in to_extract that aren\'t present in all input files. Run with -d to see details.' if errors
    @unique_values.each { |k, v| next if v.keys.include?(true); @unique_values[k] = v.keys.sort }
  end

  def graph(x, y, query)
    y = [y] unless y.kind_of?(Array)
    data = "# #{x} #{y.join(' ')} (#{query.to_s})\n"
    @unique_values[x].each do |x_val|
      data += "#{x_val} #{y.map { |yv| query_for(query.merge({x => x_val})).map { |r| r[yv] }.average }.join(' ')}\n"
    end
    data
  end

  def split_graph(x, y, split, query)
    split_vals = @unique_values[split]
    data = "# #{x} #{split_vals.join(' ')} (#{query.to_s})\n"
    @unique_values[x].each do |x_val|
      data += "#{x_val} #{split_vals.map { |sv| graph_val(query.merge({x => x_val, split => sv}), y) }.join(' ')}\n"
    end
    data
  end


  def surface(x, y, z, query)
    data = "# #{x} #{y} #{z} (#{query.to_s})\n"
    @unique_values[x].each do |x_val|
      @unique_values[y].each do |y_val|
        data += "#{x_val} #{y_val} #{query_for(query.merge({x => x_val, y => y_val})).map { |r| r[z] }.average}\n"
      end
      data += "\n"
    end
    data
  end

  # The lambda must return an array of headings followed by an array of table rows (followed by any other values for the latex_table signature)
  def table_from_lambda(lambda)
    latex_table(*lambda.call(self))
  end

  # Can now take lambdas as well as expected key: values
  def query_for(query)
    lambdas, minus_lambdas = query.partition { |q| q.last.kind_of?(Proc) }.map { |a| a.to_h }
    stage_1 = @loaded_results.select { |r| minus_lambdas.keys.map { |k| r[k] } == minus_lambdas.values }
    return stage_1 unless lambdas.any?
    stage_1.select { |r| !lambdas.map { |key, lambda| lambda.call(r[key]) }.include?(false) }
  end

  private

  def graph_val(query, y)
    q = query_for(query).map { |r| r[y] }
    q.any? ? q.average : '?'
  end

  TABLE_LINE_END = "\\\\\\hline\n"

  ##
  # Constructs a LaTeX table from an array of headings and data
  def latex_table(headings, data, merge_first = false)
    data.map! { |r| r.map { |i| i.to_s.gsub('_', '\_') } }
    table_string = "\\begin{tabular}{#{headings.map { |_, _| 'l' }.join('|')}}\n"
    table_string += headings.map { |v| "\\textbf{#{v}}" }.join(' & ') + TABLE_LINE_END

    if merge_first # Merge the first rows for the same value using \multirow
      limited_line_end = "\\\\\\cline{2-#{data.first.length}}\n"
      partitions = data.group_by(&:first)
      partitions.each do |key, partition|
        table_string += "\\multirow{#{partition.length}}{*}{\\textbf{#{key.length < 4 ? key.upcase : key.capitalize}~~~}} & #{partition.first[1..-1].join(' & ')}" + limited_line_end
        partition[1..-1].each_with_index { |row, index| table_string += "& #{row[1..-1].join(' & ') } #{index == partition.length - 2 ? TABLE_LINE_END : limited_line_end}" }
      end
    else
      data.each { |row| table_string += row.join(' & ') + TABLE_LINE_END }
    end
    table_string + "\\end{tabular}\n"
  end

end
module QualityObserverFixture
  # The uncached path is intentional: this fixture is the pressure baseline, never product source.
  def self.templates
    source_template = <<~'SOURCE'
      require "json"
      module Polyrun; module Quality; module ObserveHook
        module_function
        def install
          root = ENV.delete("POLYRUN_OBSERVE_ROOT")
          output = ENV.delete("POLYRUN_OBSERVE_OUTPUT")
          limit = Integer(ENV.delete("POLYRUN_OBSERVE_LIMIT") || "10000")
          ENV["RUBYOPT"] = ENV.delete("POLYRUN_OBSERVE_RUBYOPT")
          return unless root && output
          root = File.realpath(root) + "/"
          calls = {}; paths = {}; owners = {}; entries = 0; truncated = false; process = Process.pid
          trace = TracePoint.new(:call) do |event|
            next unless Process.pid == process
            next unless File.file?(event.path)
            path = File.realpath(event.path)
            next unless path.start_with?(root)
            path = path.delete_prefix(root)
            key = [path, event.defined_class.to_s, event.method_id.to_s]
            if calls.key?(key)
              calls[key] += 1
            elsif calls.size < limit
              calls[key] = 1
            else
              truncated = true
            end
          end
          at_exit do
            trace.disable
            if Process.pid == process
              rows = calls.map { |(path, owner, name), count| {"path" => path, "owner" => owner, "method" => name.to_s, "subject" => "#{owner}##{name}", "count" => count} }
              File.write(output, JSON.generate("calls" => rows, "truncated" => truncated, "provenance" => "observed"))
            end
          end
          trace.enable
        end
      end; end; end
      Polyrun::Quality::ObserveHook.install
    SOURCE

    cache_original = <<~SOURCE.lines.map(&:strip).join("\n")
      next unless File.file?(event.path)
      path = File.realpath(event.path)
      next unless path.start_with?(root)
      path = path.delete_prefix(root)
    SOURCE
    source_template = source_template.lines.map(&:strip).join("\n") + "\n"
    cache_fetch = <<~SOURCE.lines.map(&:strip).join("\n")
      path = paths.fetch(event.path) do |source|
        resolved = File.file?(source) ? File.realpath(source) : nil
        relative = resolved&.start_with?(root) ? resolved.delete_prefix(root) : nil
        paths[source] = relative if paths.size < limit
        relative
      end
      next unless path
    SOURCE
    cache_direct = <<~SOURCE.lines.map(&:strip).join("\n")
      source = event.path
      path = paths[source]
      if path.nil?
        resolved = File.file?(source) ? File.realpath(source) : nil
        path = resolved&.start_with?(root) ? resolved.delete_prefix(root) : false
        paths[source] = path if paths.size < limit
      end
      next unless path
    SOURCE
    original_count = <<~SOURCE.lines.map(&:strip).join("\n")
      key = [path, event.defined_class.to_s, event.method_id.to_s]
      if calls.key?(key)
      calls[key] += 1
      elsif calls.size < limit
      calls[key] = 1
      else
      truncated = true
      end
    SOURCE
    nested_count = <<~SOURCE.lines.map(&:strip).join("\n")
      owner = event.defined_class
      name = event.method_id
      methods = calls.dig(path, owner)
      if methods&.key?(name)
      methods[name] += 1
      elsif entries < limit
      methods ||= ((calls[path] ||= {})[owner] ||= {})
      methods[name] = 1
      entries += 1
      else
      truncated = true
      end
    SOURCE
    flat_rows = 'rows = calls.map { |(path, owner, name), count| {"path" => path, "owner" => owner, "method" => name.to_s, "subject" => "#{owner}##{name}", "count" => count} }'
    nested_rows = 'rows = calls.flat_map { |path, owners| owners.flat_map { |owner, methods| methods.map { |name, count| {"path" => path, "owner" => owner.to_s, "method" => name.to_s, "subject" => "#{owner}##{name}", "count" => count} } } }'
    {source_template: source_template, cache_original: cache_original, cache_fetch: cache_fetch, cache_direct: cache_direct, original_count: original_count, nested_count: nested_count, flat_rows: flat_rows, nested_rows: nested_rows}
  end
end

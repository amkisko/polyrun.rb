require "json"

module Polyrun
  module Quality
    module ObserveHook
      class Recorder
        def initialize(root, output, limit)
          @root = File.realpath(root) + "/"
          @output = output
          @limit = limit
          @calls = {}
          @paths = {}
          @owners = {}
          @entries = 0
          @truncated = false
          @process = Process.pid
        end

        def record(event)
          path = relative_path(event.path)
          return unless path

          owner = event.defined_class
          name = event.method_id
          methods = @calls.dig(path, owner)
          count = methods && methods[name]
          if count
            methods[name] = count + 1
          elsif @entries < @limit
            identity = owner_identity(event)
            return unless identity

            @owners[owner] = identity
            methods ||= ((@calls[path] ||= {})[owner] ||= {})
            methods[name] = 1
            @entries += 1
          else
            @truncated = true
          end
        end

        def write
          return unless Process.pid == @process

          rows = @calls.flat_map do |path, owners|
            owners.flat_map do |owner, methods|
              name, separator = @owners.fetch(owner)
              methods.map do |method, count|
                {"path" => path, "owner" => name, "method" => method.to_s, "subject" => "#{name}#{separator}#{method}", "count" => count}
              end
            end
          end
          File.write(@output, JSON.generate("calls" => rows, "truncated" => @truncated, "provenance" => "observed"))
        end

        private

        def relative_path(source)
          path = @paths[source]
          if path.nil?
            resolved = File.file?(source) ? File.realpath(source) : nil
            path = resolved&.start_with?(@root) ? resolved.delete_prefix(@root) : false
            @paths[source] = path if @paths.size < @limit
          end
          path
        rescue Errno::ENOENT
          false
        end

        def owner_identity(event)
          owner = event.defined_class
          name = owner.name
          separator = "#"
          if owner.singleton_class? && event.self.is_a?(Module)
            name = event.self.name
            separator = "."
          end
          [name, separator] if name.is_a?(String) && !name.empty?
        end
      end

      module_function

      def install
        root = ENV.delete("POLYRUN_OBSERVE_ROOT")
        output = ENV.delete("POLYRUN_OBSERVE_OUTPUT")
        limit = Integer(ENV.delete("POLYRUN_OBSERVE_LIMIT") || "10000")
        ENV["RUBYOPT"] = ENV.delete("POLYRUN_OBSERVE_RUBYOPT")
        return unless root && output

        recorder = Recorder.new(root, output, limit)
        trace = TracePoint.new(:call) { |event| recorder.record(event) }
        at_exit do
          trace.disable
          recorder.write
        end
        trace.enable
      end
    end
  end
end

Polyrun::Quality::ObserveHook.install

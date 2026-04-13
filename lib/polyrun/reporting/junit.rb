require "cgi"
require "json"

module Polyrun
  module Reporting
    # JUnit XML for CI (replaces rspec_junit_formatter) — stdlib only.
    #
    # Input JSON may be:
    # - **RSpec JSON** — output of +rspec --format json --out rspec.json+ (+examples+ array).
    # - **Polyrun canonical** — +{ "name" => "...", "testcases" => [ ... ] }+ (see +emit_xml+).
    #
    # Each testcase hash supports: +classname+, +name+, +time+, +status+ (+passed+, +failed+, +pending+/+skipped+),
    # and optional +failure+ => +{ "message" => "...", "body" => "..." }+.
    module Junit
      module_function

      def write_from_json_file(json_path, output_path:)
        data = JSON.parse(File.read(json_path))
        write_from_hash(data, output_path: output_path)
      end

      # Merge several RSpec JSON outputs (parallel shards) by concatenating +examples+.
      def merge_rspec_json_files(paths, output_path:)
        merged = {"examples" => []}
        paths.each do |p|
          data = JSON.parse(File.read(p))
          merged["examples"].concat(data["examples"] || [])
        end
        merged["summary"] = {"summary_line" => "merged #{paths.size} RSpec JSON file(s)"}
        write_from_hash(merged, output_path: output_path)
      end

      def write_from_hash(data, output_path:)
        doc = parse_input(data)
        xml = emit_xml(doc)
        File.write(output_path, xml)
        output_path
      end

      def parse_input(data)
        raise Polyrun::Error, "JUnit input must be a Hash" unless data.is_a?(Hash)

        if data["examples"].is_a?(Array)
          from_rspec_json(data)
        elsif data["testcases"].is_a?(Array)
          from_polyrun_hash(data)
        else
          raise Polyrun::Error,
            'JUnit input: expected top-level "examples" (RSpec JSON) or "testcases" (Polyrun schema)'
        end
      end

      def from_rspec_json(data)
        cases = []
        data["examples"].each do |ex|
          next unless ex.is_a?(Hash)

          status = (ex["status"] || "unknown").to_s
          file = ex["file_path"].to_s.sub(%r{\A\./}, "")
          tc = {
            "classname" => file.empty? ? "rspec" : file,
            "name" => (ex["full_description"] || ex["description"] || ex["id"]).to_s,
            "time" => (ex["run_time"] || ex["time"] || 0).to_f,
            "status" => status
          }
          if status == "failed"
            e = ex["exception"]
            tc["failure"] = if e.is_a?(Hash)
              {
                "message" => e["message"].to_s,
                "body" => Array(e["backtrace"]).join("\n")
              }
            else
              {"message" => "failed", "body" => ex.inspect}
            end
          end
          cases << tc
        end

        name = (data.dig("summary", "summary_line") || data["name"] || "RSpec").to_s
        from_polyrun_hash("name" => name, "hostname" => hostname, "testcases" => cases)
      end

      def from_polyrun_hash(data)
        {
          "name" => (data["name"] || data["testsuite_name"] || "tests").to_s,
          "hostname" => (data["hostname"] || hostname).to_s,
          "testcases" => Array(data["testcases"])
        }
      end

      def hostname
        require "socket"
        Socket.gethostname
      rescue
        "localhost"
      end

      # +doc+ is +{ "name", "hostname", "testcases" => [ ... ] }+
      def emit_xml(doc)
        cases = doc["testcases"] || []
        total_time = cases.sum { |c| (c["time"] || c[:time] || 0).to_f }
        failures = cases.count { |c| status_of(c) == "failed" }
        errors = cases.count { |c| status_of(c) == "error" }
        skipped = cases.count { |c| %w[pending skipped].include?(status_of(c)) }
        tests = cases.size

        lines = []
        lines << %(<?xml version="1.0" encoding="UTF-8"?>)
        lines << %(<testsuites name="#{esc(doc["name"])}">)
        lines << %(<testsuite name="#{esc(doc["name"])}" tests="#{tests}" failures="#{failures}" errors="#{errors}" skipped="#{skipped}" time="#{format_float(total_time)}" hostname="#{esc(doc["hostname"])}">)

        cases.each do |c|
          c = c.transform_keys(&:to_s)
          classname = c["classname"].to_s
          name = c["name"].to_s
          time = (c["time"] || 0).to_f
          lines << %(<testcase classname="#{esc(classname)}" name="#{esc(name)}" file="#{esc(c["file"] || classname)}" line="#{esc(c["line"] || "")}" time="#{format_float(time)}">)
          case status_of(c)
          when "failed", "error"
            f = c["failure"] || {}
            fm = f["message"] || f[:message] || status_of(c)
            fb = f["body"] || f[:body] || ""
            tag = (status_of(c) == "error") ? "error" : "failure"
            lines << %(<#{tag} message="#{esc(fm)}">#{esc(fb)}</#{tag}>)
          when "pending", "skipped"
            lines << %(<skipped/>)
          end
          lines << %(</testcase>)
        end

        lines << %(</testsuite>)
        lines << %(</testsuites>)
        lines.join("\n") + "\n"
      end

      def status_of(c)
        s = (c["status"] || c[:status] || "passed").to_s
        return "skipped" if s == "pending"

        s
      end

      def format_float(x)
        format("%.6f", x.to_f)
      end

      def esc(s)
        CGI.escapeHTML(s.to_s)
      end
    end
  end
end

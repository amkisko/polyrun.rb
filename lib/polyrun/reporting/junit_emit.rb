module Polyrun
  module Reporting
    module Junit
      module_function

      # +doc+ is +{ "name", "hostname", "testcases" => [ ... ] }+
      def emit_xml(doc)
        cases = doc["testcases"] || []
        lines = []
        lines << junit_xml_header(doc, cases)
        cases.each do |c|
          lines << junit_xml_testcase_line(c)
        end
        lines << %(</testsuite>)
        lines << %(</testsuites>)
        lines.join("\n") + "\n"
      end

      def junit_xml_header(doc, cases)
        total_time = cases.sum { |c| (c["time"] || c[:time] || 0).to_f }
        failures = cases.count { |c| status_of(c) == "failed" }
        errors = cases.count { |c| status_of(c) == "error" }
        skipped = cases.count { |c| %w[pending skipped].include?(status_of(c)) }
        tests = cases.size
        lines = []
        lines << %(<?xml version="1.0" encoding="UTF-8"?>)
        lines << %(<testsuites name="#{esc(doc["name"])}">)
        lines << %(<testsuite name="#{esc(doc["name"])}" tests="#{tests}" failures="#{failures}" errors="#{errors}" skipped="#{skipped}" time="#{format_float(total_time)}" hostname="#{esc(doc["hostname"])}">)
        lines.join("\n")
      end

      def junit_xml_testcase_line(c)
        c = c.transform_keys(&:to_s)
        classname = c["classname"].to_s
        name = c["name"].to_s
        time = (c["time"] || 0).to_f
        lines = []
        lines << %(<testcase classname="#{esc(classname)}" name="#{esc(name)}" file="#{esc(c["file"] || classname)}" line="#{esc(c["line"] || "")}" time="#{format_float(time)}">)
        case status_of(c)
        when "failed", "error"
          lines << junit_xml_failure_body(c)
        when "pending", "skipped"
          lines << %(<skipped/>)
        end
        lines << %(</testcase>)
        lines.join("\n")
      end

      def junit_xml_failure_body(c)
        f = c["failure"] || {}
        fm = f["message"] || f[:message] || status_of(c)
        fb = f["body"] || f[:body] || ""
        tag = (status_of(c) == "error") ? "error" : "failure"
        %(<#{tag} message="#{esc(fm)}">#{esc(fb)}</#{tag}>)
      end
    end
  end
end

module Polyrun
  module Database
    module UrlBuilder
      module_function

      def template_prepare_env_fill_connections!(dh, primary_template, out)
        Array(dh["connections"] || dh[:connections]).each do |c|
          nm = (c["name"] || c[:name]).to_s
          key = (c["env_key"] || c[:env_key]).to_s.strip
          key = "DATABASE_URL_#{nm.upcase.tr("-", "_")}" if key.empty? && !nm.empty?
          next if key.empty?

          tname = (c["template_db"] || c[:template_db]).to_s
          tname = primary_template if tname.empty?
          out[key] = url_for_database_name(dh, tname)
        end
        out
      end
    end
  end
end

require "uri"

module Polyrun
  module Database
    module UrlBuilder
      # String construction for +DATABASE_URL+ values.
      module ConnectionUrlBuilders
        module_function

        def build_sqlite_url(database)
          "sqlite3:#{database}"
        end

        def build_url_authority(scheme, host, port, user, password, database)
          if password && !password.to_s.empty?
            u = URI.encode_www_form_component(user.to_s)
            p = URI.encode_www_form_component(password.to_s)
            "#{scheme}://#{u}:#{p}@#{host}:#{port}/#{database}"
          elsif !user.to_s.empty?
            u = URI.encode_www_form_component(user.to_s)
            "#{scheme}://#{u}@#{host}:#{port}/#{database}"
          else
            "#{scheme}://#{host}:#{port}/#{database}"
          end
        end

        def build_mongodb_url(host, port, user, password, database)
          if user.to_s.empty?
            return "mongodb://#{host}:#{port}/#{database}"
          end

          u = URI.encode_www_form_component(user.to_s)
          if password && !password.to_s.empty?
            p = URI.encode_www_form_component(password.to_s)
            "mongodb://#{u}:#{p}@#{host}:#{port}/#{database}"
          else
            "mongodb://#{u}@#{host}:#{port}/#{database}"
          end
        end
      end
    end
  end
end

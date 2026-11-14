require_relative "workspace"

module Polyrun
  module Graph
    class Transaction
      def initialize(root, directory, settings: {})
        @workspace = Workspace.new(root, settings: settings)
        relative = File.realpath(directory).delete_prefix("#{@workspace.root}/")
        @directory = @workspace.path(relative)
        @journal = "#{relative}/transaction.json"
      end

      def recover!
        return false unless File.file?(@workspace.path(@journal))

        journal = @workspace.read_json(@journal)
        return false unless %w[prepared writing restoring].include?(journal["state"])

        save(journal.merge("state" => "restoring"))
        journal.fetch("files").reverse_each do |relative, hashes|
          source = @workspace.path(relative)
          backup = @workspace.path("backups/#{relative}", base: @directory)
          unless File.file?(source) && File.file?(backup) && Digest::SHA256.file(backup).hexdigest == hashes["before"]
            raise Error.new("RECOVERY_REQUIRED", "source recovery needs a valid original: #{relative}")
          end
          restore_source(source, backup, hashes, relative)
        end
        save(journal.merge("state" => "restored"))
        true
      end

      def commit(replacements)
        files = replacements.to_h do |relative, before, after|
          backup = @workspace.path("backups/#{relative}", base: @directory)
          FileUtils.mkdir_p(File.dirname(backup))
          File.binwrite(backup, before)
          [relative, {"before" => Digest::SHA256.hexdigest(before), "after" => Digest::SHA256.hexdigest(after)}]
        end
        journal = {"state" => "prepared", "files" => files}
        save(journal)
        save(journal.merge("state" => "writing"))
        replacements.each do |relative, before, after|
          source = @workspace.path(relative)
          raise Error.new("STALE_SNAPSHOT", "source changed during apply") unless File.binread(source) == before

          write_source(source, after)
        end
        save(journal.merge("state" => "applied"))
        true
      rescue Exception # rubocop:disable Lint/RescueException -- rollback also covers cooperative cancellation
        recover!
        raise
      end

      private

      def restore_source(source, backup, hashes, relative)
        current = Digest::SHA256.file(source).hexdigest
        raise Error.new("RECOVERY_REQUIRED", "source changed outside graph apply: #{relative}") unless [hashes["before"], hashes["after"]].include?(current)

        write_source(source, File.binread(backup)) unless current == hashes["before"]
      end

      def save(journal)
        @workspace.write_json(@journal, journal)
      end

      def write_source(path, bytes)
        mode = File.stat(path).mode & 0o777
        Tempfile.create("polyrun-apply", File.dirname(path)) do |file|
          file.chmod(mode)
          file.binmode
          file.write(bytes)
          file.flush
          file.fsync
          File.rename(file.path, path)
        end
      end
    end
  end
end

require "open3"
require "tempfile"
require "fileutils"

module Android
  class KeystoreValidator
    ValidationError = Class.new(StandardError)

    Result = Struct.new(
      :keystore_type,
      :keystore_entries,
      :entry_type,
      :alias,
      :certificate_subject,
      :certificate_common_name,
      :certificate_issuer,
      :signature_algorithm,
      :valid_from,
      :valid_until,
      :fingerprints,
      keyword_init: true
    )

    def initialize(keystore_data:, keystore_password:, key_alias:, key_password:, keytool_path: "keytool")
      @keystore_data = keystore_data
      @keystore_password = keystore_password
      @key_alias = key_alias
      @key_password = key_password
      @keytool_path = keytool_path
    end

    def validate!
      ensure_inputs!

      Dir.mktmpdir("keystore") do |dir|
        keystore_path = File.join(dir, "upload.keystore")
        File.binwrite(keystore_path, @keystore_data)

        # 1. First, list content to verify keystore password and get available aliases.
        #    Passwords are NEVER placed on keytool's argv (which is world-readable
        #    via /proc/<pid>/cmdline). Instead we hand keytool 0600 tempfiles via
        #    its `-storepass:file` / `-keypass:file` indirection.
        keystore_output = run_keytool(
          %W[-list -v -keystore #{keystore_path}],
          "keystore password",
          passwords: { "-storepass" => @keystore_password }
        )

        # 2. Then verify the specific alias and key password
        begin
          alias_output = run_keytool(
            %W[-list -v -alias #{@key_alias} -keystore #{keystore_path}],
            "alias credentials",
            passwords: { "-storepass" => @keystore_password, "-keypass" => @key_password }
          )
        rescue ValidationError => e
          # If we reached here, the keystore password is correct (step 1 succeeded),
          # so the failure is either the alias being wrong or the key password being wrong.

          available_aliases = keystore_output.scan(/Alias name:\s*(.+)$/i).flatten.map(&:strip)

          if available_aliases.exclude?(@key_alias)
            hint = available_aliases.any? ? "Available aliases: #{available_aliases.join(', ')}" : "No aliases found."
            raise ValidationError, "Alias '#{@key_alias}' not found. #{hint}"
          else
             # Alias exists, so it must be the key password failure
             raise ValidationError, "Invalid key password for alias '#{@key_alias}'."
          end
        end

        build_result(keystore_output, alias_output)
      ensure
        FileUtils.rm_f(keystore_path) if defined?(keystore_path) && File.exist?(keystore_path)
      end
    end

    private

    def ensure_inputs!
      raise ValidationError, "Keystore file is missing" if @keystore_data.blank?
      raise ValidationError, "Keystore password is missing" if @keystore_password.to_s.strip.empty?
      raise ValidationError, "Key alias is missing" if @key_alias.to_s.strip.empty?
      raise ValidationError, "Key password is missing" if @key_password.to_s.strip.empty?
    end

    # Runs keytool with the given argv. Any passwords are passed via keytool's
    # `<option>:file <path>` indirection, where <path> is a 0600 tempfile that
    # only this process and root can read. This keeps the secrets entirely off
    # the process argv (and thus out of /proc/<pid>/cmdline and `ps` output).
    # The tempfiles are unlinked in an ensure block.
    def run_keytool(args, context, passwords: {})
      password_files = []
      full_args = args.dup

      passwords.each do |option, value|
        file = write_password_file(value)
        password_files << file
        # e.g. ["-storepass:file", "/tmp/.../pw"] — value lives in the file only.
        full_args.concat([ "#{option}:file", file.path ])
      end

      stdout, stderr, status = Open3.capture3(@keytool_path, *full_args)
      return stdout if status.success?

      combined_output = [ stderr, stdout ].map(&:presence).compact.join("\n").strip

      # Clean up common Java error noise for user display
      user_message = if combined_output.include?("keystore password was incorrect") || combined_output.include?("UnrecoverableKeyException")
        "Incorrect password."
      elsif combined_output.include?("Alias <") && combined_output.include?("> does not exist")
        "Alias not found."
      else
        # Fallback to generic but logged full error
        "Verification failed."
      end

      # Log the full nasty Java stack trace for debugging
      Rails.logger.warn("[KeystoreValidator] Java Error: #{combined_output}")

      raise ValidationError, user_message
    rescue Errno::ENOENT
      raise ValidationError, "System error: Java keytool not found."
    ensure
      password_files&.each do |file|
        file.close unless file.closed?
        file.unlink
      rescue StandardError
        # Best-effort cleanup; never mask the original result/error.
      end
    end

    # Writes a password to a 0600 tempfile readable only by this process owner,
    # for consumption via keytool's `<option>:file` indirection. keytool reads
    # the first line of the file as the password.
    def write_password_file(value)
      file = Tempfile.new("keystore-pass")
      File.chmod(0o600, file.path)
      file.write(value.to_s)
      file.flush
      file.close
      file
    end

    def build_result(keystore_output, alias_output)
      valid_from, valid_until = parse_validity(alias_output)

      Result.new(
        keystore_type: match_value(keystore_output, "Keystore type"),
        keystore_entries: parse_entry_count(keystore_output),
        entry_type: match_value(alias_output, "Entry type"),
        alias: match_value(alias_output, "Alias name"),
        certificate_subject: match_value(alias_output, "Owner"),
        certificate_common_name: extract_common_name(match_value(alias_output, "Owner")),
        certificate_issuer: match_value(alias_output, "Issuer"),
        signature_algorithm: match_value(alias_output, "Signature algorithm name"),
        valid_from: valid_from,
        valid_until: valid_until,
        fingerprints: {
          sha1: match_value(alias_output, "SHA1"),
          sha256: match_value(alias_output, "SHA256")
        }
      )
    end

    def parse_entry_count(output)
      return nil unless output
      if output =~ /Your keystore contains\s+(\d+)\s+entr/i
        Regexp.last_match(1).to_i
      end
    end

    def match_value(output, label)
      return nil if output.blank?
      regex = /#{Regexp.escape(label)}:\s*(.+)$/i
      match = output.match(regex)
      match ? match[1].strip : nil
    end

    def extract_common_name(subject)
      return nil if subject.blank?
      match = subject.match(/CN=([^,]+)/i)
      match ? match[1].strip : nil
    end

    def parse_validity(output)
      return [ nil, nil ] if output.blank?
      regex = /Valid from:\s*(.+?)\s+until:\s*(.+)$/i
      match = output.match(regex)
      return [ nil, nil ] unless match

      [ parse_time(match[1]), parse_time(match[2]) ]
    end

    def parse_time(value)
      return nil if value.blank?
      if defined?(Time.zone) && Time.zone
        Time.zone.parse(value) rescue Time.parse(value)
      else
        Time.parse(value)
      end
    rescue ArgumentError
      nil
    end
  end
end

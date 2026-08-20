require "rails_helper"

RSpec.describe Android::KeystoreValidator do
  let(:keystore_data) { "keystore-binary" }
  let(:validator) do
    described_class.new(
      keystore_data: keystore_data,
      keystore_password: "PWSTORE-7Q3X",
      key_alias: "release",
      key_password: "PWKEY-9Z2K"
    )
  end

  let(:keystore_output) do
    <<~OUTPUT
      Keystore type: PKCS12
      Your keystore contains 1 entry
      Entry type: PrivateKeyEntry
    OUTPUT
  end

  let(:alias_output) do
    <<~OUTPUT
      Alias name: release
      Owner: CN=Demo App, OU=Mobile, O=Example Corp, L=City, ST=State, C=US
      Issuer: CN=Demo App, OU=Mobile, O=Example Corp, L=City, ST=State, C=US
      Signature algorithm name: SHA256withRSA
      Valid from: Wed May 01 12:00:00 UTC 2024 until: Fri May 01 12:00:00 UTC 2030
      SHA1: AA:BB:CC
      SHA256: DD:EE:FF
    OUTPUT
  end

  # Records every set of argv passed to keytool, plus a snapshot (content + file
  # mode) of any `<option>:file <path>` password file *at the moment of the call*
  # — before the validator unlinks it in its ensure block.
  let(:keytool_invocations) { [] }

  before do
    allow(FileUtils).to receive(:rm_f).and_call_original

    success = instance_double(Process::Status, success?: true)
    outputs = [
      [ keystore_output, "", success ],
      [ alias_output, "", success ]
    ]

    allow(Open3).to receive(:capture3) do |*args|
      file_snapshots = {}
      args.each_with_index do |arg, i|
        next unless arg.to_s.end_with?(":file")
        path = args[i + 1]
        file_snapshots[arg] = {
          path:    path,
          content: File.read(path),
          mode:    File.stat(path).mode & 0o777
        }
      end
      keytool_invocations << { args: args, files: file_snapshots }
      outputs.shift || [ "", "", success ]
    end
  end

  it "returns parsed metadata when validation succeeds" do
    result = validator.validate!

    expect(result.keystore_type).to eq("PKCS12")
    expect(result.keystore_entries).to eq(1)
    expect(result.alias).to eq("release")
    expect(result.certificate_common_name).to eq("Demo App")
    expect(result.signature_algorithm).to eq("SHA256withRSA")
    expect(result.fingerprints[:sha1]).to eq("AA:BB:CC")
    expect(result.valid_until).to be_a(Time)
  end

  it "raises a validation error when keytool fails" do
    allow(Open3).to receive(:capture3).and_return(
      [ "", "keytool error", instance_double(Process::Status, success?: false) ]
    )

    expect { validator.validate! }.to raise_error(Android::KeystoreValidator::ValidationError)
  end

  describe "password handling (M-8: passwords must stay off argv)" do
    it "never passes the raw passwords on keytool's argv" do
      validator.validate!

      all_args = keytool_invocations.flat_map { |inv| inv[:args] }.map(&:to_s)
      expect(all_args).not_to include("PWSTORE-7Q3X")
      expect(all_args).not_to include("PWKEY-9Z2K")
      # And it must not embed the secret inside any combined token either.
      expect(all_args.any? { |a| a.include?("PWSTORE-7Q3X") }).to be(false)
      expect(all_args.any? { |a| a.include?("PWKEY-9Z2K") }).to be(false)
    end

    it "passes passwords via keytool's `:file` indirection backed by a 0600 tempfile" do
      validator.validate!

      all_args = keytool_invocations.flat_map { |inv| inv[:args] }.map(&:to_s)
      expect(all_args).to include("-storepass:file")
      expect(all_args).to include("-keypass:file")

      # Gather every password-file snapshot taken across both keytool calls.
      snapshots = keytool_invocations.flat_map { |inv| inv[:files].values }

      storepass = snapshots.find { |s| s[:content] == "PWSTORE-7Q3X" }
      keypass   = snapshots.find { |s| s[:content] == "PWKEY-9Z2K" }

      expect(storepass).not_to be_nil
      expect(keypass).not_to be_nil
      # Owner read/write only — not readable by other local users.
      expect(storepass[:mode]).to eq(0o600)
      expect(keypass[:mode]).to eq(0o600)
    end

    it "unlinks the password tempfiles after the keytool call" do
      validator.validate!

      paths = keytool_invocations.flat_map { |inv| inv[:files].values.map { |f| f[:path] } }
      expect(paths).not_to be_empty
      paths.each { |path| expect(File.exist?(path)).to be(false) }
    end
  end
end

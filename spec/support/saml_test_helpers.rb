module SamlTestHelpers
  # Generates a throwaway self-signed certificate for SSO spec fixtures.
  # Cached per-thread so the same cert is reused within an example.
  def self.valid_test_cert
    Thread.current[:valid_saml_test_cert] ||= generate
  end

  def self.generate
    require "openssl"
    key = OpenSSL::PKey::RSA.new(2048)
    name = OpenSSL::X509::Name.parse("/CN=test.mysigner.example/O=Test/C=US")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = name
    cert.issuer = name
    cert.public_key = key.public_key
    cert.not_before = Time.current - 1.day
    cert.not_after = Time.current + 365.days
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    cert.to_pem
  end
end

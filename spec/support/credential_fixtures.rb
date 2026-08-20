# frozen_string_literal: true

require "openssl"

module SpecCredentialFixtures
  module_function

  def pem(label: "PRIVATE KEY", body: "FAKE")
    [ "-----BEGIN #{label}-----", body, "-----END #{label}-----", "" ].join("\n")
  end

  def ec_private_key
    OpenSSL::PKey::EC.generate("prime256v1").to_pem
  end
end

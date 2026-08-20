class ApplicationMailer < ActionMailer::Base
  default from: "MySigner <no-reply@mysigner.dev>"
  layout "mailer"
  helper :mailer
end

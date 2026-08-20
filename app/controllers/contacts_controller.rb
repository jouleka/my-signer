class ContactsController < ApplicationController
  # The submitted email flows directly into ContactMailer's `reply_to:`
  # header. Mail gem strips CR/LF so this isn't a header-injection
  # surface, but a hostile string still re-routes operator replies to
  # an attacker-controlled inbox. URI::MailTo::EMAIL_REGEXP is RFC
  # 5321/5322-compatible enough for our rejection check (we're not
  # trying to validate every legal address — just reject the obviously
  # weaponized ones).
  EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP

  def create
    # Honeypot spam protection
    if params.dig(:contact, :website).present?
      respond_to do |format|
        format.turbo_stream { render_success_stream }
        format.html { redirect_to unauthenticated_root_path(anchor: "contact"), flash: { contact_notice: "Thanks for reaching out! We'll get back to you soon." } }
      end
      return
    end

    name = params.dig(:contact, :name)
    email = params.dig(:contact, :email)
    category = params.dig(:contact, :category)
    message = params.dig(:contact, :message)

    if name.blank? || email.blank? || category.blank? || message.blank?
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("contact-form-messages", partial: "contacts/alert", locals: { message: "Please fill in all required fields." })
        end
        format.html { redirect_to unauthenticated_root_path(anchor: "contact"), flash: { contact_alert: "Please fill in all required fields." } }
      end
      return
    end

    unless email.to_s.match?(EMAIL_FORMAT)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("contact-form-messages", partial: "contacts/alert", locals: { message: "Please enter a valid email address." })
        end
        format.html { redirect_to unauthenticated_root_path(anchor: "contact"), flash: { contact_alert: "Please enter a valid email address." } }
      end
      return
    end

    ContactMailer.new_message(
      name: name,
      email: email,
      category: category,
      message: message
    ).deliver_later

    respond_to do |format|
      format.turbo_stream { render_success_stream }
      format.html { redirect_to unauthenticated_root_path(anchor: "contact"), flash: { contact_notice: "Thanks for reaching out! We'll get back to you soon." } }
    end
  end

  private

  def render_success_stream
    render turbo_stream: [
      turbo_stream.update("contact-form-messages", partial: "contacts/notice", locals: { message: "Thanks for reaching out! We'll get back to you soon." }),
      turbo_stream.replace("contact-form", partial: "contacts/form")
    ]
  end
end

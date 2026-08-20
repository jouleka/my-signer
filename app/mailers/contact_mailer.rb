class ContactMailer < ApplicationMailer
  def new_message(name:, email:, category:, message:)
    @name = name
    @email = email
    @category = category
    @message = message

    mail(
      to: contact_email,
      reply_to: email,
      subject: "[MySigner Contact] #{category_label(category)} from #{name}"
    )
  end

  private

  def contact_email
    Rails.application.credentials.dig(:contact_email) || "support@mysigner.local"
  end

  def category_label(category)
    {
      "bug" => "Bug Report",
      "feature" => "Feature Request",
      "question" => "Question",
      "feedback" => "Feedback",
      "other" => "Other"
    }[category] || category.to_s.titleize
  end
end

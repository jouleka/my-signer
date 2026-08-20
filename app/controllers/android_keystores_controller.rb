class AndroidKeystoresController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org
  before_action :set_keystore, only: [ :show, :update, :destroy, :download, :activate ]

  def index
    authorize @organization, :show?
    @keystores = @organization.android_keystores.includes(:android_app).order(created_at: :desc)
  end

  def new
    authorize @organization, :manage_credentials?
    @keystore = @organization.android_keystores.new
    load_form_collections
  end

  def create
    authorize @organization, :manage_credentials?
    @keystore = @organization.android_keystores.new(permitted_attrs.except(:keystore_file))

    file = permitted_attrs[:keystore_file]
    if file.present?
      @keystore.keystore_file = file.read
    end

    requested_active = ActiveModel::Type::Boolean.new.cast(permitted_attrs[:active])
    @keystore.active = false if requested_active

    begin
      if @keystore.save
        @keystore.activate_exclusively! if requested_active
        redirect_to organization_android_keystores_path(@organization), notice: "Keystore uploaded successfully"
      else
        # If save failed, validation errors should be populated on the object
        if @keystore.errors[:base].present?
          Rails.logger.warn("Keystore validation error: #{@keystore.errors[:base].join(', ')}")
        end

        load_form_collections
        flash.now[:alert] = "Unable to save keystore"
        render :new, status: :unprocessable_content
      end
    rescue ActiveRecord::RecordNotUnique
      load_form_collections
      flash.now[:alert] = "This keystore has already been uploaded for this organization."
      @keystore.errors.add(:keystore_file, "has already been uploaded")
      render :new, status: :unprocessable_content
    end
  end

  def show
    authorize @organization, :show?
    load_form_collections
  end

  def update
    authorize @organization, :manage_credentials?

    if @keystore.update(update_params)
      redirect_to organization_android_keystore_path(@organization, @keystore), notice: "Keystore updated"
    else
      load_form_collections
      flash.now[:alert] = "Unable to update keystore"
      render :show, status: :unprocessable_content
    end
  end

  def destroy
    authorize @organization, :manage_credentials?
    @keystore.destroy
    redirect_to organization_android_keystores_path(@organization), notice: "Keystore deleted"
  end

  def download
    authorize @organization, :manage_credentials?
    data = @keystore.keystore_file
    if data.blank?
      redirect_to organization_android_keystores_path(@organization), alert: "Keystore file not available"
      return
    end

    send_data data,
              filename: download_filename(@keystore),
              type: "application/octet-stream",
              disposition: "attachment"
  end

  def activate
    authorize @organization, :manage_credentials?

    begin
      @keystore.activate_exclusively!
      redirect_back fallback_location: organization_android_keystores_path(@organization), notice: "Keystore activated successfully"
    rescue => e
      redirect_back fallback_location: organization_android_keystores_path(@organization), alert: "Failed to activate keystore: #{ErrorMessageSanitizer.sanitize(e)}"
    end
  end

  def validate
    authorize @organization, :manage_credentials?
    attrs = params.require(:android_keystore).permit(:keystore_file, :keystore_password, :key_alias, :key_password)
    file = attrs[:keystore_file]

    if file.blank?
      render json: { error: "Keystore file is required" }, status: :unprocessable_content
      return
    end

    data = file.read
    result = Android::KeystoreValidator.new(
      keystore_data: data,
      keystore_password: attrs[:keystore_password],
      key_alias: attrs[:key_alias],
      key_password: attrs[:key_password]
    ).validate!

    render json: {
      valid: true,
      alias: result.alias,
      certificate_subject: result.certificate_subject,
      certificate_issuer: result.certificate_issuer,
      valid_from: result.valid_from&.iso8601,
      valid_until: result.valid_until&.iso8601,
      fingerprints: result.fingerprints
    }
  rescue Android::KeystoreValidator::ValidationError => e
    Rails.logger.error("Keystore Validation API Failed: #{e.message}")
    render json: { valid: false, error: ErrorMessageSanitizer.sanitize(e) }, status: :unprocessable_content
  end

  private

  def set_org
    # Scoped to caller's orgs so non-member access 404s like a missing id —
    # closes the org-id enumeration oracle. See
    # OrganizationsController#set_organization for full rationale.
    @organization = current_user.organizations.find(params[:organization_id])
  end

  def set_keystore
    @keystore = @organization.android_keystores.find(params[:id])
  end

  def load_form_collections
    @android_apps = @organization.android_apps.order(:name)
  end

  def permitted_attrs
    params.require(:android_keystore).permit(:name, :android_app_id, :keystore_file, :keystore_password, :key_alias, :key_password, :active)
  end

  def update_params
    params.require(:android_keystore).permit(:name, :android_app_id)
  end

  def download_filename(keystore)
    base = keystore.name.parameterize.presence || "keystore"
    pkg = keystore.android_app&.package_name
    suffix = pkg ? "-#{pkg}" : ""
    "#{base}#{suffix}.jks"
  end
end

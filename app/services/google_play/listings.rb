module GooglePlay
  class Listings
    def initialize(client)
      @client = client
    end

    # Fetch all locale listings for a package
    # @param package_name [String] Android package name
    # @return [Array<Hash>] Array of listing data per locale
    def list(package_name)
      edit = @client.create_edit(package_name)
      response = @client.list_app_listings(package_name, edit.id)
      listings = response.listings || []
      @client.delete_edit(package_name, edit.id)
      listings.map { |l| listing_to_hash(l) }
    rescue StandardError => e
      begin
        @client.delete_edit(package_name, edit.id) if edit
      rescue StandardError
        nil
      end
      raise e
    end

    # Fetch a single locale listing
    # @param package_name [String] Android package name
    # @param locale [String] Locale code (e.g., "en-US")
    # @return [Hash] Listing data
    def get(package_name, locale)
      edit = @client.create_edit(package_name)
      listing = @client.get_app_listing(package_name, edit.id, locale)
      @client.delete_edit(package_name, edit.id)
      listing_to_hash(listing)
    rescue StandardError => e
      begin
        @client.delete_edit(package_name, edit.id) if edit
      rescue StandardError
        nil
      end
      raise e
    end

    # Update a listing for a specific locale
    # @param package_name [String] Android package name
    # @param locale [String] Locale code (e.g., "en-US")
    # @param title [String, nil] App title (max 30 chars)
    # @param short_description [String, nil] Short description (max 80 chars)
    # @param full_description [String, nil] Full description (max 4000 chars)
    # @return [Hash] Updated listing data
    def update(package_name, locale:, title: nil, short_description: nil, full_description: nil)
      edit = @client.create_edit(package_name)

      listing = Google::Apis::AndroidpublisherV3::Listing.new
      listing.language = locale
      listing.title = title if title
      listing.short_description = short_description if short_description
      listing.full_description = full_description if full_description

      result = @client.update_app_listing(package_name, edit.id, locale, listing)
      @client.commit_edit(package_name, edit.id)
      listing_to_hash(result)
    rescue StandardError => e
      begin
        @client.delete_edit(package_name, edit.id) if edit
      rescue StandardError
        nil
      end
      raise e
    end

    private

    def listing_to_hash(listing)
      {
        language: listing.language,
        title: listing.title,
        short_description: listing.short_description,
        full_description: listing.full_description
      }
    end
  end
end

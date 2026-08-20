namespace :aso do
  # Phase C backfill tooling for the keyword-rank tracker migration.
  #
  # Run order for a production deploy:
  #   1. Deploy code with migration 20260420203634 (TightenKeywordRankingsFk) +
  #      20260420203635 (DropTrackedKeywordsFromStoreListings) NOT YET applied.
  #   2. rake aso:backfill_tracked_keywords DRY_RUN=1  # confirm counts
  #   3. rake aso:backfill_tracked_keywords
  #   4. rake aso:backfill_keyword_rankings_fk DRY_RUN=1
  #   5. rake aso:backfill_keyword_rankings_fk
  #   6. rails db:migrate   # now safe to drop the legacy columns
  #
  # Both tasks:
  #   - Are idempotent (find_or_create_by + partial-unique index guards).
  #   - Are safe to re-run after the schema migrations (they no-op with a
  #     clear message when the legacy columns are gone).
  #   - Emit a stats hash to stdout. Non-zero mismatches in production should
  #     block the destructive migrations until investigated.

  COUNTRY_FROM_LOCALE = ->(locale) {
    return nil if locale.blank?
    parts = locale.to_s.split("-", 2)
    return nil unless parts.length == 2
    country = parts[1].upcase
    country.match?(/\A[A-Z]{2}\z/) ? country : nil
  }

  # MUST match Aso::KeywordNormalizer.call on both sides of every comparison.
  # The canonical form is NFC + downcase + strip + whitespace-collapse — an
  # un-normalized raw value will miss existing records (whitespace variance
  # or Unicode NFD) and either silently fail to link or crash on the unique
  # index `(apple_app_id, keyword)`.
  NORMALIZE_KEYWORD = ->(kw) { Aso::KeywordNormalizer.call(kw) }

  desc "Phase C backfill: copy legacy store_listings.tracked_keywords (jsonb) into TrackedKeyword + TrackedKeywordCountry. DRY_RUN=1 reports without writing."
  task backfill_tracked_keywords: :environment do
    dry = ENV["DRY_RUN"] == "1"
    conn = ActiveRecord::Base.connection

    unless conn.column_exists?(:store_listings, :tracked_keywords)
      puts "[aso:backfill_tracked_keywords] store_listings.tracked_keywords is already gone — nothing to backfill."
      next
    end

    supported = Aso::Countries::SUPPORTED.to_set
    stats = Hash.new(0)

    rows = conn.select_all(<<~SQL).to_a
      SELECT id, listable_type, listable_id, locale, tracked_keywords
      FROM store_listings
      WHERE tracked_keywords IS NOT NULL
        AND tracked_keywords <> '[]'::jsonb
    SQL

    rows.each do |row|
      stats[:listings_scanned] += 1

      if row["listable_type"] != "AppleApp"
        stats[:skipped_non_apple] += 1
        next
      end

      country = COUNTRY_FROM_LOCALE.call(row["locale"])
      unless country && supported.include?(country)
        stats[:skipped_unsupported_country] += 1
        next
      end

      raw = row["tracked_keywords"]
      keywords = (raw.is_a?(Array) ? raw : (JSON.parse(raw || "[]") rescue []))
                   .map { |k| NORMALIZE_KEYWORD.call(k) }
                   .reject(&:blank?)
                   .uniq
      next if keywords.empty?
      stats[:listings_with_keywords] += 1

      keywords.each do |kw|
        stats[:keywords_considered] += 1
        next if dry

        ActiveRecord::Base.transaction(requires_new: true) do
          # kw is already normalized; pass it through so the lookup matches
          # the value the model will store after `before_validation` runs.
          tk = TrackedKeyword.find_or_create_by!(apple_app_id: row["listable_id"], keyword: kw)
          stats[:tracked_keywords_created] += 1 if tk.previously_new_record?
          tkc = TrackedKeywordCountry.find_or_create_by!(tracked_keyword: tk, country: country)
          stats[:tracked_keyword_countries_created] += 1 if tkc.previously_new_record?
        end
      end
    end

    puts "[aso:backfill_tracked_keywords]#{' DRY-RUN' if dry} #{stats.sort.to_h.inspect}"
  end

  desc "Phase C backfill: populate keyword_rankings.tracked_keyword_country_id from legacy (listable_id, locale, keyword). DRY_RUN=1 reports without updating."
  task backfill_keyword_rankings_fk: :environment do
    dry = ENV["DRY_RUN"] == "1"
    conn = ActiveRecord::Base.connection

    missing = %i[listable_type listable_id locale].reject { |c| conn.column_exists?(:keyword_rankings, c) }
    if missing.any?
      puts "[aso:backfill_keyword_rankings_fk] keyword_rankings.#{missing.join(',')} already dropped — nothing to backfill."
      next
    end

    supported = Aso::Countries::SUPPORTED.to_set

    # Build (apple_app_id, keyword, country) → tkc_id lookup once.
    lookup = {}
    TrackedKeywordCountry.joins(:tracked_keyword).pluck(
      "tracked_keyword_countries.id",
      "tracked_keyword_countries.country",
      "tracked_keywords.apple_app_id",
      "tracked_keywords.keyword"
    ).each do |tkc_id, country, app_id, keyword|
      lookup[[ app_id, keyword, country ]] = tkc_id
    end

    stats = Hash.new(0)

    KeywordRanking.where(tracked_keyword_country_id: nil).in_batches(of: 1_000) do |batch|
      updates = []

      batch.pluck(:id, :listable_type, :listable_id, :locale, :keyword).each do |id, lt, lid, loc, kw|
        stats[:rows_scanned] += 1

        if lt != "AppleApp"
          stats[:skipped_non_apple] += 1
          next
        end

        country = COUNTRY_FROM_LOCALE.call(loc)
        unless country && supported.include?(country)
          stats[:skipped_bad_locale] += 1
          next
        end

        # The lookup was built from TrackedKeyword.keyword (stored normalized
        # by the model's before_validation callback). Legacy keyword_rankings
        # rows predate that normalization, so the raw `kw` must be pushed
        # through the same normalizer or the lookup silently misses.
        tkc_id = lookup[[ lid, NORMALIZE_KEYWORD.call(kw), country ]]
        if tkc_id
          stats[:matched] += 1
          updates << [ id, tkc_id ]
        else
          stats[:not_matched] += 1
        end
      end

      next if dry || updates.empty?

      values_sql = updates.map { |id, tkc_id| "(#{id.to_i}, #{tkc_id.to_i})" }.join(",")
      conn.execute(<<~SQL)
        UPDATE keyword_rankings kr
        SET tracked_keyword_country_id = v.tkc_id
        FROM (VALUES #{values_sql}) AS v(id, tkc_id)
        WHERE kr.id = v.id
      SQL
      stats[:rows_updated] += updates.length
    end

    puts "[aso:backfill_keyword_rankings_fk]#{' DRY-RUN' if dry} #{stats.sort.to_h.inspect}"
    if stats[:not_matched].to_i > 0
      warn "[aso:backfill_keyword_rankings_fk] #{stats[:not_matched]} ranking rows did not match any TrackedKeywordCountry — investigate before running the destructive migration."
    end
  end
end

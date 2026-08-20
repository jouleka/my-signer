require "rails_helper"
require Rails.root.join("db/migrate/20260307100000_add_plan_tier_to_users")

RSpec.describe AddPlanTierToUsers do
  let(:connection) { ActiveRecord::Base.connection }
  let(:schema_name) { "plan_tier_migration_spec_#{SecureRandom.hex(6)}" }

  around do |example|
    original_search_path = connection.schema_search_path

    connection.execute("CREATE SCHEMA #{schema_name}")
    connection.execute(<<~SQL)
      CREATE TABLE #{schema_name}.users (
        id bigserial PRIMARY KEY,
        email character varying NOT NULL,
        encrypted_password character varying NOT NULL,
        created_at timestamp NOT NULL,
        updated_at timestamp NOT NULL
      )
    SQL
    connection.schema_search_path = "#{schema_name},public"

    example.run
  ensure
    connection.schema_search_path = original_search_path
    connection.execute("DROP SCHEMA IF EXISTS #{schema_name} CASCADE")
  end

  it "backfills existing users to the free plan when the migration runs" do
    now = Time.current
    connection.execute(
      User.send(
        :sanitize_sql_array,
        [
          "INSERT INTO #{schema_name}.users (email, encrypted_password, created_at, updated_at) VALUES (?, ?, ?, ?)",
          "legacy-user@example.com",
          "legacy-digest",
          now,
          now
        ]
      )
    )

    described_class.new.migrate(:up)

    plan_tier = connection.select_value("SELECT plan_tier FROM #{schema_name}.users WHERE email = 'legacy-user@example.com'")

    expect(plan_tier.to_i).to eq(0)
  end

  it "adds a non-null free default for future inserts" do
    described_class.new.migrate(:up)

    now = Time.current
    connection.execute(
      User.send(
        :sanitize_sql_array,
        [
          "INSERT INTO #{schema_name}.users (email, encrypted_password, created_at, updated_at) VALUES (?, ?, ?, ?)",
          "new-user@example.com",
          "new-digest",
          now,
          now
        ]
      )
    )

    plan_tier = connection.select_value("SELECT plan_tier FROM #{schema_name}.users WHERE email = 'new-user@example.com'")
    nullable = connection.select_value(<<~SQL.squish)
      SELECT is_nullable
      FROM information_schema.columns
      WHERE table_schema = '#{schema_name}'
        AND table_name = 'users'
        AND column_name = 'plan_tier'
    SQL

    expect(plan_tier.to_i).to eq(0)
    expect(nullable).to eq("NO")
  end
end

namespace :screenshots do
  desc "Migrate scene images from binary DB columns to ActiveStorage"
  task migrate_to_active_storage: :environment do
    scenes = ScreenshotScene.where.not(source_image_data: nil)
    total = scenes.count
    migrated = 0
    skipped = 0

    puts "Found #{total} scenes with binary image data to migrate..."

    scenes.find_each do |scene|
      if scene.source_image.attached?
        skipped += 1
        next
      end

      content_type = scene.source_image_content_type || "image/png"
      filename = scene.source_image_filename || "screenshot_#{scene.id}.png"

      scene.source_image.attach(
        io: StringIO.new(scene.source_image_data),
        filename: filename,
        content_type: content_type
      )

      # Clear binary column to free DB space
      scene.update_column(:source_image_data, nil)

      migrated += 1
      print "\rMigrated #{migrated}/#{total}..." if migrated % 10 == 0
    end

    puts "\nDone! Migrated: #{migrated}, Skipped (already attached): #{skipped}"
  end
end

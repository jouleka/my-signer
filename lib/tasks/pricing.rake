namespace :pricing do
  desc "Assign a plan tier to a user by email. Usage: rake pricing:assign_plan[email,tier]"
  task :assign_plan, [ :email, :tier ] => :environment do |_, args|
    email = args[:email].to_s.strip.downcase
    tier = args[:tier].to_s.strip

    if email.blank? || tier.blank?
      abort "Usage: rake pricing:assign_plan[email,tier]"
    end

    unless User.plan_tiers.key?(tier)
      abort "Invalid tier '#{tier}'. Valid tiers: #{User.plan_tiers.keys.join(', ')}"
    end

    user = User.find_by(email: email)
    abort "User not found for #{email}" unless user

    user.update!(plan_tier: tier)
    puts "Assigned #{tier} plan to #{user.email}"
  end

  desc "Audit owners and organizations that exceed their current pricing limits"
  task audit_over_limit: :environment do
    report = Pricing::Audit.call

    if report[:owners].empty? && report[:organizations].empty?
      puts "No users or organizations are currently over their pricing limits."
      next
    end

    unless report[:owners].empty?
      puts "Owners over limit:"
      report[:owners].each do |violation|
        puts "- #{violation[:user].email}: #{violation[:current]}/#{violation[:limit]} owned organizations on #{violation[:tier]}"
      end
    end

    unless report[:organizations].empty?
      puts "Organizations over limit:"
      report[:organizations].each do |violation|
        org = violation[:organization]
        puts "- Org ##{org.id} #{org.name.inspect} (owner: #{org.owner.email}) #{violation[:type]} #{violation[:current]}/#{violation[:limit]} on #{violation[:tier]}"
      end
    end
  end
end

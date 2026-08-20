ActiveSupport::Notifications.subscribe(/rack_attack/) do |event, start, finish, id, payload|
    req = payload[:request]
    Rails.logger.info(
      "[rack-attack] event=#{event} matched=#{req.env['rack.attack.matched']} "\
      "ip=#{req.ip} path=#{req.path} data=#{req.env['rack.attack.match_data'].inspect}"
    )
end

c = User.find_or_create_by!(email: "uxfour@example.com") { it.name = "Новаяч"; it.password = "ux-pass-1234"; it.password_confirmation = "ux-pass-1234"; it.save! }
c.update!(name: "Новаяч", email_confirmed_at: Time.current) if c.email_confirmed_at.nil?
puts "fresh=#{c.id}"

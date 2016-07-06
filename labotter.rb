require 'bundler'
Bundler.require

require 'json'

ActiveRecord::Base.establish_connection(
	adapter: 'sqlite3',
	database: 'labotter.sqlite3'
)

class User < ActiveRecord::Base
	has_many :labostats

	def laboin!
		return false if self.inlabo == true
		ActiveRecord::Base.transaction do
			self.labostats.create!(
				:laboin => DateTime.now.strftime('%s') 
			)
			self.inlabo = true
			self.save
		end
	end	   

	def laborida!
		return false if self.inlabo == false
		last_inlabo = self.labostats.find_by(laborida: nil)
		ActiveRecord::Base.transaction do
			last_inlabo.laborida = DateTime.now.strftime('%s')
			last_inlabo.save
			self.inlabo = false
			self.save
		end
	end

end

class Labostat < ActiveRecord::Base
	belongs_to :user
end

user = User.create(screen_name: 'tester')
user.laboin!
user.laborida!
p user

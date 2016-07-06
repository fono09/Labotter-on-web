require 'bundler'
Bundler.require

require 'json'

ActiveRecord::Base.establish_connection(
	adapter: 'sqlite3',
	database: 'labotter.sqlite3'
)

class User < ActiveRecord::Base
	has_many :labostats

	def laboin
		return false if self.inlabo == true
		ActiveRecord::Base.transaction do
			self.labostats.create!(
				:laboin => DateTime.now.strftime('%s') 
			)
			self.inlabo = true
			self.save
		end
	end	   

	def laborida
		return false if self.inlabo == false
		p self.labostats
	end

end

class Labostat < ActiveRecord::Base
	belongs_to :user
end

user = User.new(screen_name: 'tester')
user.save
user.laboin
user.laborida

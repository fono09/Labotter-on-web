require 'bundler'
Bundler.require

require 'json'

ActiveRecord::Base.establish_connection(
	adapter: 'sqlite3',
	database: 'labotter.sqlite3'
)

class User < ActiveRecord::Base
	has_many :labstats

	def laboin
		return false if self.inlabo == true
		ActiveReocrd::Base.transaction do
			self.labstats.create!(
				:laboin => DateTime.now.strftime('%s') 
			)
			self.inlabo = true
			self.save
		end
	end	   

	def laborida
		return false if self.inlabo == false
	end

end

class Labstats < ActiveRecord::Base
	belongs_to :user
end

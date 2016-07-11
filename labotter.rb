require 'bundler'
Bundler.require

require 'json'
SETTINGS = JSON.restore(File.open('settings.json'))

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
				:laboin => Time.now.to_i
			)
			self.inlabo = true
			self.save
		end
	end	   

	def laborida!
		return false if self.inlabo == false
		last_laboin = self.get_last_labostat
		ActiveRecord::Base.transaction do
			last_laboin.laborida = Time.now.to_i
			last_laboin.save
			self.inlabo = false
			self.save
		end
	end

	def get_last_labostat
		last_laboin = self.labostats.find_by(laborida: nil)
		last_laboin = self.labostats.last unless last_laboin
		return last_laboin
	end

	def get_sum_seconds(sec)
		sum = self.labostats.where(laboin: (Time.now.to_i - sec)..Time.now.to_i).inject(0){|sum, n| 
			sum += n.laborida.to_i - n.laboin.to_i
		}
		return sum
	end

end

class Labostat < ActiveRecord::Base
	belongs_to :user

	def laboin
		return Time.at(super)
	end

	def laborida
		return Time.at(super)
	end
end

class UserAgent < TwitterOAuth::Client
	attr_reader :ar_user

	def initialize(user)
		raise TypeError.new('user must be class User') unless user.is_a?(User)

		@ar_user = user
		unless SETTINGS['twitter']['use_local_access_token'] == true then
			super(
				:consumer_key => SETTINGS['twitter']['consumer_key'],
				:consumer_secret => SETTINGS['twitter']['consumer_secret'],
				:token => user.access_token,
				:secret => user.access_token_secret,
			)
		else
			super(
				:consumer_key => SETTINGS['twitter']['consumer_key'],
				:consumer_secret => SETTINGS['twitter']['consumer_secret'],
				:token => SETTINGS['twitter']['access_token'],
				:secret => SETTINGS['twitter']['access_token_secret'],
			)
		end
	end

	def laboin!
		ar_user.laboin!
		self.update('.@' + self.ar_user.screen_name + 'が' + self.ar_user.get_last_labostat.laboin.strftime('%H時%M分%S秒') + 'にらぼいんしました。 #labotter')
	end

	def laborida!
		ar_user.laborida!
		self.update('.@' + self.ar_user.screen_name + 'が' + self.ar_user.get_last_labostat.laborida.strftime('%H時%M分%S秒') + 'にらぼりだしました。 #labotter')
	end

	def last_an_week
		self.update('.@' + self.ar_user.screen_name + 'は過去7日間で' + (self.ar_user.get_sum_seconds(Time.now.to_i - 60*60*24*7)/3600).to_s + '時間らぼにいました')
	end

end

exit

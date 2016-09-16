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

	def load_csv(lines)
		lines.shift #一行目はラベルなので破棄
		labotter_time_fmt = '"%Y-%m-%d %H:%M:%S"'
		ActiveRecord::Base.transaction do
			while line = lines.shift do
				data = line.split(',')

				laboin = Time.strptime(data[1], labotter_time_fmt).to_i
				laborida = Time.strptime(data[2], labotter_time_fmt).to_i

				arel_table = self.labostats.arel_table

				if (duplicate_labostat = self.labostats.where(arel_table[:laboin].gt(laboin)).where(arel_table[:laborida].lt(laborida))).present? then

					puts 'range * + + *'
					p duplicate_labostat

					duplicate_labostat.update(laboin: laboin, laborida:laborida)

				elsif (duplicate_labostat = self.labostats.where(arel_table[:laboin].lt(laboin)).where(arel_table[:laborida].gt(laborida))).present? then

					puts 'range + * * +'
					p duplicate_labostat

				elsif (duplicate_labostat = self.labostats.where(laborida: laboin..laborida)).present? then

					puts 'range + * + *'
					p duplicate_labostat

					duplicate_labostat.update(laborida: laborida)

				elsif (duplicate_labostat = self.labostats.where(laboin: laboin..laborida)).present? then

					puts 'range * + * +'
					p duplicate_labostat
					
					duplicate_labostat.update(laboin: laboin)

				else
					self.labostats.create!(
						:laboin => Time.strptime(data[1], labotter_time_fmt).to_i,
						:laborida => Time.strptime(data[2], labotter_time_fmt).to_i
					)
				end
			end
		end
		return true
	end

end

class Labostat < ActiveRecord::Base
	belongs_to :user

	def laboin
		return Time.at(super)
	end

	def laborida
		return Time.at(super) unless super == nil
		return nil
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
		return false unless ar_user.laboin!
		self.update('.@' + self.ar_user.screen_name + 'が' + self.ar_user.get_last_labostat.laboin.strftime('%H時%M分%S秒') + 'にらぼいんしました。 #labotter')
	end

	def laborida!
		return false unless ar_user.laborida!
		self.update('.@' + self.ar_user.screen_name + 'が' + self.ar_user.get_last_labostat.laborida.strftime('%H時%M分%S秒') + 'にらぼりだしました。 #labotter')
	end

	def tweet_labostat
		buff = '.@' + self.ar_user.screen_name + 'は、' + Time.now.strftime('%H時%M分%S秒') + '現在、らぼに'
		buff += ar_user.inlabo ? 'います' : 'いません'
		buff += '。'
		self.update(buff)
	end

	def tweet_last_an_week
		self.update('.@' + self.ar_user.screen_name + 'は過去7日間で' + (self.ar_user.get_sum_seconds(Time.now.to_i - 60*60*24*7)/3600).to_s + '時間らぼにいました')
	end

end

set base_url: "https://fono.jp/labotter"

use Rack::Session::Cookie,
	:key => 'labotter.session',
	:path => '/labotter',
	:secret => 'super secret'


before do
	 @twitter_client = TwitterOAuth::Client.new(
		:consumer_key => SETTINGS['twitter']['consumer_key'],
		:consumer_secret => SETTINGS['twitter']['consumer_secret']
	)

	headers 'Access-Control-Allow-Origin' => '*'
end

after do
	ActiveRecord::Base.connection.close
end

helpers do
	def logged_in?
		logger.info("session[:authorized]")
		logger.info(session[:authorized])
		begin 
			user = User.find(session[:authorized])
		rescue
			redirect to("#{settings.base_url}/request_token")
		end
		return user
	end
end
	

get '/' do
	"らぼったー on Webはらぼの入退室記録をつけるやつです。<br>らぼったーを使う<a href=\"#{settings.base_url}/ui\">認証</a>"
end

get '/ui' do
	user = logged_in?
	File.read(File.join('public', 'index.html'))
end

get '/request_token' do
	callback = "#{settings.base_url}/access_token"
	request_token = @twitter_client.request_token(:oauth_callback => callback)
	session[:request_token] = request_token.token
	session[:request_token_secret] = request_token.secret
	redirect request_token.authorize_url
end

get '/access_token' do
	user = ""
	begin 
		access_token = @twitter_client.authorize(session[:request_token], session[:request_token_secret], :oauth_verifier => params[:oauth_verifier])
		logger.info(access_token)
		user = User.find_by(:twitter_id => access_token.params[:user_id])
		if user.nil? then
			user = User.create(
				:twitter_id => access_token.params[:user_id],
				:access_token => access_token.token,
				:access_token_secret => access_token.secret,
				:screen_name => access_token.params[:screen_name]
			)
		end
	rescue
		logger.info $@
		halt 404, "Login with twitter Failed"
	end
	session.delete(:request_token)
	session.delete(:request_token_secret)
	session[:authorized] = user.id
	redirect to "#{settings.base_url}\\"
end

get '/labostats' do
	user = logged_in?
	last_labostat = user.get_last_labostat
	return user.get_last_labostat.to_json
end

post '/labostats/share' do
	user = logged_in?
	ua = UserAgent.new(user)
	return ua.tweet_labostat.to_json
end

post '/labostats' do
	user = logged_in?
	ua = UserAgent.new(user)
	stat = ua.laboin!
	return { success: stat }.to_json
end

post '/labostats/csv' do
	user = logged_in?
	halt 400 unless params[:csv] 

	fh = params[:csv][:tempfile].open
	lines = fh.readlines
	fh.close

	if user.load_csv(lines) then
		halt 200
	else
		halt 500
	end
end

put '/labostats' do
	user = logged_in?
	ua = UserAgent.new(user)
	stat = ua.laborida!
	return { success: stat }.to_json
end

delete '/labostats' do
	"まだ工事中"
end


options '*' do
	200
end

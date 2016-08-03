# This is Neocities' Rainbows! config file. We are using this in production to run all our web apps.
# It works really well for us and has been heavily load tested, so I wanted to share it with the community.
#
# In my opinion, this is the best way to deploy a ruby web application. Unlike EventMachine based solutions,
# it uses real ruby threads, which allows it to take advantage of the internal non-blocking IO pattern 
# in MRI.
#
# Contrary to popular belief, MRI doesn't block execution to wait on IO when you are using threads, even
# with the GIL. The requests are done concurrently for anything that is based on the IO class. This 
# includes things like Net::HTTP and even `system commands`. Grep the MRI Ruby source code for
# "rb_thread_blocking_region" if you'd like to explore how this works.
#
# This approach will likely be a little slower than EventMachine-based servers (like Thin), but I think this
# will provide better throughput for modern web applications (which almost always deal with a lot of slower IO).
# You can use existing ruby software and don't have to use special EventMachine code to make IO not
# block.
#
# The one potential caveat to this approach is that your code must be thread safe. But this problem is rare
# in practice, and when in doubt, you can always wrap the action in a Mutex lock.
# If you see a thread safety problem/bug, make sure to let the author know about it so it can get fixed!
#
# There are other benefits to using Rainbows! that aren't just related to concurrency:
#
# * It listens to unix signals, and can add/remove/restart workers with zero downtime! Neocities.org
#   has never gone offline since we launched the site several months ago.
#
# * It provides mechanisms for logging and pid files, which we use to feed our process monitor.
#
# * When we restart, the master process starts one copy of the worker application, and then forks it to 
#   create the rest of the workers. This is -much- faster than the Mongrel/Thin approach, which has to start
#   one worker at a time (the dreaded "rolling restart").
#
# If you haven't looked at Rainbows! yet, and you're using MRI, I strongly recommend taking a look:
# http://rainbows.rubyforge.org
#
# ALTERNATIVES
#
# If you're using Heroku, check out Zbatery. Same as Rainbows!, but without the fork: http://zbatery.bogomip.org
#
# If you're using JRuby, check out: http://www.engineyard.com/blog/2011/taking-stock-jruby-web-servers
#
# If you're using Rubinius, check out Puma: https://github.com/evanphx/puma
#
# If you have a completely insane amount of traffic (hint: you probably don't), want to use 
# EventMachine and are okay with using custom EM libraries for IO, check out Sinatra::Synchrony:
# http://kyledrake.net/sinatra-synchrony
#
# If this is too much and/or you don't care, check out Puma. Puma is basically Zbatery with ThreadPool, and it
# works on MRI, JRuby, and Rubinius. Ultimately I'd like to see Puma be the default web server of choice,
# and perhaps even have it replace Webrick as the ruby web server in the standard library.

Rainbows! do
  # Set the app name so we can re-use this file easily.
  name = 'labotter'

  # This enables the Rainbows! Thread Pool, which is best for YARV (1.9.x)
  use :ThreadPool

  # This is set in nginx for us, so we don't set it here.
  client_max_body_size nil 

  # This is the number of worker processes there will be. You can remove/add using signals during runtime.
  # One per core isn't a bad rule of thumb, but there is still the GIL so I usually add a few more.
  worker_processes 6

  # This variable is different based on what concurrency strategy you use, but for ThreadPool it sets the
  # number of threads in the pool. Don't set this too high or else you'll starve your app. 32 works well for us.
  worker_connections 32

  # How long to hold the request open until timing out.
  timeout 30

  # Listen on a socket, and set a high backlog to avoid "resource unavailable" errors under heavy load.
  # It has been suggested that you should lower the backlog if you are using an HTTP load balancer.
  # Sockets are a little more efficient than TCP/IP, generally 5-10% faster. You may need to tweak sysctl,
  # the default settings on many unix machines don't allow the app to have enough open files to queue a lot
  # of traffic up.
  listen "unix:/var/run/#{name}.sock", :backlog => 2048
  #listen 81

  pid "/var/run/#{name}.pid"
  stderr_path "/var/log/#{name}.log"
  stdout_path "/var/log/#{name}.log"

  ### 
  # Hardcore performance tweaks, described here: https://github.com/blog/517-unicorn
  ### 

  # This loads the app in master, and then forks workers. Kill with USR2 and it will do a graceful restart
  # using the block proceeding.
  preload_app true

  before_fork do |server, worker|
    ##  
    # When sent a USR2, Rainbows! will suffix its pidfile with .oldbin and
    # immediately start loading up a new version of itself (loaded with a new
    # version of our app). When this new Rainbows! is completely loaded
    # it will begin spawning workers. The first worker spawned will check to
    # see if an .oldbin pidfile exists. If so, this means we've just booted up
    # a new Rainbows! and need to tell the old one that it can now die. To do so
    # we send it a QUIT.
    #   
    # Using this method we get 0 downtime deploys.

    old_pid = "/var/run/neocities/#{name}.pid.oldbin"
    if File.exists?(old_pid) && server.pid != old_pid
      begin
        Process.kill("QUIT", File.read(old_pid).to_i)
      rescue Errno::ENOENT, Errno::ESRCH
        # someone else did our job for us
      end 
    end 
  end 
end

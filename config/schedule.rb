# 
# schedule.rb
# Home Curious
#
# Created by Donovan on 11/29/2014
# Copyright (c) Donovan. All rights reserved.

# # DEV MODE

# set :output, "/Volumes/Work/zParseCloud/Smith/Ruby/homecurious.log"

# every 1.day, :at => '04:03 am' do
#   command "ruby /Volumes/Work/zParseCloud/Smith/Ruby/homecurious01.rb"
# end

# LIVE MODE

env :PATH, '/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:/root/.rbenv/shims'

set :output, "/var/www/homecurious.log"

# tail -n 200 homecurious.log
# cat /dev/null > homecurious.log
# ls -lh homecurious.log
# crontab -r
# crontab -l
# whenever --update-crontab store
# every 1.day, :at => '21:56 pm' do
#   command "ruby /var/www/homecurious10.rb"
# end

every 6.hours do
  command "ruby /var/www/homecurious10.rb"
end

# # LIVE MODE - MONTHLY JOBS

# env :PATH, '/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:/root/.rbenv/shims'

# set :output, "/var/www/homecurious.log"

# every 1.month, :at => '00:01 am' do
#   command "ruby /var/www/homecurious01.rb"
# end
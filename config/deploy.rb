require 'mina/bundler'
require 'mina/rails'
require 'mina/git'
require 'mina/rbenv'
require 'mina/slack/tasks'

set :repository, 'git@github.com:peatio/peatio_beijing.git'
set :user, 'deploy'
set :deploy_to, '/home/deploy/peatio'
set :branch, ENV['branch'] || 'master'
set :without_admin, false

case ENV['to']
when 'demo'
  set :domain, 'demo.peat.io'
when 'peatio-daemon'
  set :domain, 'peatio-daemon'
when 'peatio-web-01'
  set :domain, 'peatio-web-01'
  set :without_admin, true
when 'peatio-admin'
  set :domain, 'peatio-admin'
else
  set :domain, 'stg.peat.io'
end

set :unicorn_pid, lambda { "#{deploy_to}/#{shared_path}/tmp/pids/unicorn.pid" }

set :shared_paths, [
  'config/database.yml',
  'config/application.yml',
  'config/currencies.yml',
  'config/markets.yml',
  'config/amqp.yml',
  'config/deposit_channels.yml',
  'config/withdraw_channels.yml',
  'config/unicorn.rb',
  'tmp',
  'log'
]

set :unicorn_pid, lambda { "#{deploy_to}/#{shared_path}/tmp/pids/unicorn.pid" }

task :environment do
  invoke :'rbenv:load'
end

task setup: :environment do
  queue! %[mkdir -p "#{deploy_to}/shared/log"]
  queue! %[chmod g+rx,u+rwx "#{deploy_to}/shared/log"]

  queue! %[mkdir -p "#{deploy_to}/shared/config"]
  queue! %[chmod g+rx,u+rwx "#{deploy_to}/shared/config"]

  queue! %[mkdir -p "#{deploy_to}/shared/tmp"]
  queue! %[chmod g+rx,u+rwx "#{deploy_to}/shared/tmp"]

  queue! %[touch "#{deploy_to}/shared/config/database.yml"]
  queue! %[touch "#{deploy_to}/shared/config/currencies.yml"]
  queue! %[touch "#{deploy_to}/shared/config/application.yml"]
  queue! %[touch "#{deploy_to}/shared/config/markets.yml"]
  queue! %[touch "#{deploy_to}/shared/config/amqp.yml"]
  queue! %[touch "#{deploy_to}/shared/config/deposit_channels.yml"]
  queue! %[touch "#{deploy_to}/shared/config/withdraw_channels.yml"]
  queue! %[touch "#{deploy_to}/shared/config/unicorn.rb"]
end

desc "Deploys the current version to the server."
task deploy: :environment do
  deploy do
    invoke :'git:clone'
    invoke :'deploy:link_shared_paths'
    invoke :'bundle:install'
    invoke :'rails:db_migrate'
    invoke :'rails:assets_precompile'

    to :launch do
      invoke :del_admin if without_admin
      invoke :'unicorn:restart'
    end
  end
end

namespace :unicorn do
  desc "Start Unicorn"
  task start: :environment do
    queue 'echo "-----> Start Unicorn"'
    queue! %{
      cd #{deploy_to}/#{current_path}
      bundle exec unicorn_rails -E production -c config/unicorn.rb -D
    }
  end

  desc "Stop Unicorn"
  task stop: :environment do
    queue 'echo "-----> Stop Unicorn"'
    queue! %{
      test -s "#{unicorn_pid}" && kill -QUIT `cat "#{unicorn_pid}"` && echo "Stop Ok" && exit 0
      echo >&2 "Not running"
    }
  end

  desc "Restart Unicorn"
  task restart: :environment do
    invoke :'unicorn:stop'
    invoke :'unicorn:start'
  end
end

namespace :daemons do
  desc "Start Daemons"
  task start: :environment do
    queue "cd #{deploy_to}/current && RAILS_ENV=production bundle exec ./bin/rake daemons:start && echo Daemons START DONE!!!"
  end

  desc "Stop Daemons"
  task stop: :environment do
    queue "cd #{deploy_to}/current && RAILS_ENV=production bundle exec ./bin/rake daemons:stop && echo Daemons STOP DONE!!!"
  end

  desc "Query Daemons"
  task status: :environment do
    queue "cd #{deploy_to}/current && RAILS_ENV=production bundle exec ./bin/rake daemons:status"
  end
end

desc "Generate liability proof"
task 'solvency:liability_proof' do
  queue "cd #{deploy_to}/current && RAILS_ENV=production bundle exec rake solvency:liability_proof"
end

desc 'delete admin'
task :del_admin do
  queue! "rm -rf #{deploy_to}/current/app/controllers/admin"
  queue! "rm -rf #{deploy_to}/current/app/views/admin"
  queue! "rm -rf #{deploy_to}/current/app/models/worker"

  [
    'amqp_daemon.rb',
    'coin_deposits.rb',
    'coin_deposits_ctl',
    'deposit_coin_address_ctl',
    'global_state.rb',
    'global_state_ctl',
    'hot_wallets.rb',
    'hot_wallets_ctl',
    'matching_ctl',
    'notification_ctl',
    'pusher_ctl',
    'trade_executor_ctl',
    'withdraw_audit_ctl',
    'withdraw_coin_ctl'
  ].each do |filename|
    queue! "rm -rf #{deploy_to}/current/lib/daemons/#{filename}"
  end

  queue! "sed -i '/draw\ :admin/d' #{deploy_to}/current/config/routes.rb"
end

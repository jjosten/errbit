# Deploy Config
# =============
#
# Copy this file to config/deploy.rb and customize it as needed.
# Then run `cap deploy:setup` to set up your server and finally
# `cap deploy` whenever you would like to deploy Errbit. Refer
# to the Readme for more information.

config = YAML.load_file('config/config.yml')['deployment'] || {}

require 'bundler/capistrano'
require "rvm/capistrano"
load 'deploy/assets'

set :application, "errbit"
set :repository,  config['repository']

role :web, config['hosts']['web']
role :app, config['hosts']['app']
role :db,  config['hosts']['db'], :primary => true

set :user, config['user']
set :use_sudo, false
# if config.has_key?('ssh_key')
#   set :ssh_options,      { :forward_agent => true, :keys => [ config['ssh_key'] ] }
# else
#   set :ssh_options,      { :forward_agent => true }
# end
# default_run_options[:pty] = true

set :deploy_to, config['deploy_to']
set :deploy_via, :remote_cache
set :copy_cache, true
set :copy_exclude, [".git"]
set :copy_compression, :bz2

set :scm, :git
set :scm_verbose, true
set :branch, config['branch'] || 'master'

set :bundle_flags, '--deployment --binstubs '
set :bundle_cmd,  "cd #{release_path} && bundle"

# set :scm, :none
set :scm_verbose, true
set :branch, config['branch'] || 'master'

before 'deploy:assets:symlink', 'errbit:symlink_configs'
# if unicorn is started through something like runit (the tool which restarts the process when it's stopped)
# after 'deploy:restart', 'unicorn:stop'

namespace :deploy do
  task :start do ; end
  task :stop do ; end
  task :restart, :roles => :app, :except => { :no_release => true } do
    run "#{try_sudo} touch #{File.join(current_path,'tmp','restart.txt')}"
  end
end

namespace :errbit do
  task :setup_configs do
    shared_configs = File.join(shared_path,'config')
    run "mkdir -p #{shared_configs}"
    run "if [ ! -f #{shared_configs}/config.yml ]; then cp #{latest_release}/config/config.example.yml #{shared_configs}/config.yml; fi"
    run "if [ ! -f #{shared_configs}/mongoid.yml ]; then cp #{latest_release}/config/mongoid.example.yml #{shared_configs}/mongoid.yml; fi"

    # Generate unique secret token
    run %Q{if [ ! -f #{shared_configs}/secret_token.rb ]; then
      cd #{current_release};
      echo "Errbit::Application.config.secret_token = '$(bundle exec rake secret)'" > #{shared_configs}/secret_token.rb;
    fi}.compact
  end

  task :symlink_configs do
    errbit.setup_configs
    shared_configs = File.join(shared_path,'config')
    release_configs = File.join(release_path,'config')
    run("ln -nfs #{shared_configs}/config.yml #{release_configs}/config.yml")
    run("ln -nfs #{shared_configs}/mongoid.yml #{release_configs}/mongoid.yml")
    run("ln -nfs #{shared_configs}/secret_token.rb #{release_configs}/initializers/__secret_token.rb")
  end
end

namespace :db do
  desc "Create the indexes defined on your mongoid models"
  task :create_mongoid_indexes do
    run "cd #{current_path} && bundle exec rake db:mongoid:create_indexes"
  end
end

set :unicorn_binary, 'bin/unicorn'
set :unicorn_pid, "#{shared_path}/pids/unicorn.pid"

namespace :unicorn do
  desc 'Starts unicorn'
  task :start, roles: :app, except: { no_release: true } do
    run "cd #{current_path} && #{unicorn_binary} -c #{shared_path}/config/unicorn.rb -E #{rails_env} -D"
  end
  desc 'Stops unicorn'
  task :stop, roles: :app, except: { no_release: true } do
    run " kill `cat #{unicorn_pid}`"
  end
  desc 'Stops unicorn gracefully (QUIT)'
  task :graceful_stop, roles: :app, except: { no_release: true } do
    run " kill -s QUIT `cat #{unicorn_pid}`"
  end
  desc 'Reloads unicorn sending USR2'
  task :reload, roles: :app, except: { no_release: true } do
    run " kill -s USR2 `cat #{unicorn_pid}`"
  end
  desc 'Restarts unicorn by stop an start'
  task :restart, roles: :app, except: { no_release: true } do
    stop
    start
  end
end


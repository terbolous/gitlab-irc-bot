#!/usr/bin/env ruby
require 'rubygems'
require 'bundler/setup'

require 'sinatra/base'
require 'cinch'
require 'json'
require 'yaml'
require 'digest/sha2'

$config = YAML.load_file('config.yml')
channels = ($config['travis'].values + $config['gitlab'].values).map { |c| c['channel'] }

class App < Sinatra::Application
  class << self
    attr_accessor :ircbot
  end
  @@ircbot = nil

  configure do
    set :bind, '0.0.0.0'
    set :port, $config['sinatra']['port']
    disable :traps
  end

  post '/gitlab-ci' do
    data = JSON.parse request.body.read

    project_name = data['project_name']
    if $config['gitlab'].include? project_name
      build_status = format_status data['build_status']

      sha = data['sha'][0..7]
      branch = data['ref']
      user = data['push_data']['user_name']
      message = data['push_data']['commits'][0]['message'].lines.first

      commit_count = data['push_data']['total_commits_count']
      commit_count_str = (commit_count > 1) ? "(#{commit_count} commits) " : ""

      ch = $config['gitlab'][project_name]['channel']

      App.ircbot.Channel(ch).send("#{project_name} (#{branch}) build #{build_status} - #{user} #{commit_count_str}#{sha}: #{message}")
    end
    200
  end

  post '/travis-ci' do
    data = JSON.parse params[:payload]

    if travis_valid_request?
      owner = data['repository']['owner_name']
      project_name = data['repository']['name']
      build_status = format_status data['status'], data['status_message']

      sha = data['commit'][0..7]
      branch = data['branch']
      user = data['author_name']
      message = data['message'].lines.first

      ch = $config['travis'][repo_slug]['channel']

      App.ircbot.Channel(ch).send("#{owner} / #{project_name} (#{branch}) build #{build_status} - #{user} #{sha}: #{message}")
    end
    200
  end

  def format_travis_status(status, status_message)
    c = :red
    if status == 0
      c = :green
    elsif status_message == "Pending"
      c = :yellow
    end

    Cinch::Formatting.format(c, status_message)
  end

  def format_status(str)
    if str == "failed"
      colour = :red
    elsif str == "success"
      colour = :green
    else
      colour = :yellow
    end

    Cinch::Formatting.format(colour, str)
  end

  def travis_valid_request?
    slug = repo_slug
    if $config['travis'].include? slug
      token = $config['travis'][slug]['token']
      digest = Digest::SHA2.new.update("#{slug}#{token}")
      return digest.to_s == authorization
    end
    false
  end

  def authorization
    env['HTTP_AUTHORIZATION']
  end

  def repo_slug
    env['HTTP_TRAVIS_REPO_SLUG']
  end
end

bot = Cinch::Bot.new do
  configure do |c|
    c.load! $config['irc']
    c.channels = channels
  end
end
bot.loggers.first.level = :info

App.ircbot = bot

t_bot = Thread.new {
  bot.start
}
t_app = Thread.new {
  App.start!
}

trap_block = proc {
  App.quit!
  Thread.new {
    bot.quit
  }
}
Signal.trap("SIGINT", &trap_block)
Signal.trap("SIGTERM", &trap_block)

t_bot.join

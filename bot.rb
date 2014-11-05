#!/usr/bin/env ruby
require 'rubygems'
require 'bundler/setup'

require 'sinatra/base'
require 'cinch'
require 'json'

class App < Sinatra::Application
  class << self
    attr_accessor :ircbot
  end
  @@ircbot = nil

  configure do
    set :bind, '0.0.0.0'
    disable :traps
  end

  post '/gitlab-ci' do
    data = JSON.parse request.body.read
    logger.info data

    project_name = data['project_name']
    build_status = format_status data['build_status']

    sha = data['sha'][0..7]
    user = data['push_data']['user_name']
    message = data['push_data']['commits'][0]['message'].lines.first

    App.ircbot.channels[0].send("#{project_name} build #{build_status} - #{user} #{sha}: #{message}")
    200
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
end

bot = Cinch::Bot.new do
  configure do |c|
    c.server   = "irc.elvum.net"
    c.port     = 6697
    c.channels = ["#notrr"]
    c.nick     = "git"
    c.ssl.use  = true
  end
end

App.ircbot = bot

t_bot = Thread.new {
  bot.start
}
t_app = Thread.new {
  App.start!
}

Signal.trap("SIGINT") {
  App.quit!
  Thread.new {
    bot.quit
  }
}

t_bot.join

#!/usr/bin/env ruby

require 'em-irc'
require 'logger'
require 'pp'
require 'data_mapper'



DataMapper::Logger.new($stdout, :debug)
DataMapper.setup(:default, (ENV["DATABASE_URL"]|| 'sqlite://'+File.expand_path('../git.db',__FILE__)))
DataMapper::Model.raise_on_save_failure=true

class Sentence
  include DataMapper::Resource

  property :id, Serial
  property :author, Text
  property :text, Text
  property :count, Integer
  property :context, String
end

class Friend
  include DataMapper::Resource

  property :id, Serial
  property :name, Text
end


DataMapper.finalize
DataMapper.auto_upgrade!



$channel="#zweitbot"
$mynick="godrintest"


$known_sentences=[]

def sentenceValid?(s)
  if s.length<10
    false
  elsif $known_sentences.member?(s)
    false
  elsif s.match(/2[0-9]{3}-[0-9].*/)
    false
  elsif s.match(/#{$mynick}/)
    false
  else
    true
  end
end


Sentence.all.each{|s|
  if not sentenceValid?(s.text)
    s.destroy
  else
    $known_sentences<<s.text
  end
}



class BotState


  attr_accessor :justLoggedIn, :friends

  def initialize
    @justLoggedIn=true
    @friends=[]

    EM.add_timer(20,proc {
      @justLoggedIn=false
    })

  end
end


client = EventMachine::IRC::Client.new do
  host 'irc.chaostal.de'
  port '6667'

  @bot=nil

  def say(what)
    message($channel,what)
  end

  on(:connect) do
    nick($mynick)
    puts "connected - nick #{$mynick}"

    @bot=BotState.new
  end

  on(:nick) do  |a,b,c|
    puts "nick"
    pp a,b,c
    join($channel)
  end

  on(:join) do |who,channel,names|  # called after joining a channel
    puts "on join"
    if who==$mynick
      pp who,channel,names
      message(channel, "howdy all")
      #  send_data("hi again test")
      #
      #EM.add_timer(20,proc {
      #  say Time.now.to_s 
      #})
      EM.add_timer(3,proc {
	message( "@godrin","fluester")
      })

      cleanupCount=proc {
	Sentence.all.each{|s|s.count=(s.count||1)-1
	  s.save
      }
      EM.add_timer(90,cleanupCount)
      }
      cleanupCount.call

      saySth=proc {
	s=Sentence.all({:count.lt=>3}).sample
	if s
	  someNick=Friend.all.sample
	  text=s.text.gsub("<<SOMENICK>>",someNick.name)
	  say(text) if s
	  s.count||=0
	  s.count+=1
	  s.save
	end
	EM.add_timer(Random.rand(30)+1,saySth)
      }
      EM.add_timer(7,saySth)
    else
      if Friend.first :name=>who
	say "Hey "+who+" - wir kennen uns schon :-)"
      end
    end
  end

  on(:message) do |source, target, message|  # called when being messaged
    puts "message: <#{source}> -> <#{target}>: #{message}"

    return if source==$mynick

    case message
    when /#{$mynick}/i
      say("Was geht ?")
    when /wetter/i
      say("Das Wetter nervt echt !")
    when /heute/i
      say("Man was ist hier heute los ???")
    when /(hi|hallo|na)/i 
      if @bot.justLoggedIn
	Friend.create :name=>source unless Friend.first :name=>source
	#@bot.friends<<source
	#say("Ja, Du bist mein Freund #{source}")
      end
    else
      words=message.split(" ").select{|w|w[0..0]=~/[A-Z]/}
      if words.length>0
	say("Was soll das mit #{words.shuffle[0]} ?")
      end
    end

    message.gsub!($mynick,"<<SOMENICK>>")

    Sentence.create :author=>source, :text=>message unless Sentence.first :text=>message if sentenceValid?(message)
  end

  # callback for all messages sent from IRC server
  on(:parsed) do |hash|
    puts "parsed: #{hash[:prefix]} #{hash[:command]} #{hash[:params].join(' ')}"
  end

end

client.run!  # start EventMachine loop

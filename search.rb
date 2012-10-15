#!/usr/bin/env ruby

require 'rubygems'
require 'sinatra/async'
require 'thin'
require 'json'

require 'em-synchrony'
require 'em-synchrony/em-http'

require 'cgi'
require 'time'
require 'hmac-sha2'
require 'hmac-sha1'
require 'base64'
require 'nokogiri'
require 'yajl'

require 'titleize'
Dir[File.dirname(__FILE__) + '/lib/*.rb'].each {|file| require file }

require 'pry'

class Search < Sinatra::Base
  register Sinatra::Async
  
  aget '/search/:keyword' do |keyword|
    Fiber.new do
      EM.synchrony do
        callback = params.delete('callback') # jsonp
        out = Output::JSONP.new(keyword)
        body out
        
        [Amazon,Hulu,Itunes,Netflix].each do |klass|
          Fiber.new do
            m = klass.new
            titles = m.query(keyword.gsub("'",""))
            if titles
              out.stream callback, klass.to_s => titles
            else
              out.stream callback, klass.to_s => [{:title => "Search Failed", :failed => true}]
            end
          end.resume
        end
      end
    end.resume
  end
end

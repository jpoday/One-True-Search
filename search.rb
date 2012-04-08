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
require 'base64'
require 'nokogiri'

require 'yajl'
#require File.expand_path(File.dirname(__FILE__) + '/lib/mwhich')

require 'pry'

class Search < Sinatra::Base
  register Sinatra::Async

  class JSONP
    include EventMachine::Deferrable

    def initialize
      @counter = 0
    end
    
    def stream(callback,object)
      if @counter == 0
        # json p plus hack to remove braces to enable single object
        @block.call "#{callback}({#{object.to_json.gsub("{","").gsub("}","")}"
      else
        @block.call ",#{object.to_json.gsub("{","").gsub("}","")}"
      end
      @counter += 1
      if @counter == 4
        @block.call "})"
        self.succeed
      end
    end

    def each(&block)
      @block = block
    end
  end

  class Amazon
    def initialize
      @endpoint_url = "http://webservices.amazon.com/onca/xml"
      @aws_access_key_id = ENV['AWS_ACCESS_KEY_ID']
      @aws_secret_access_key = ENV['AWS_SECRET_ACCESS_KEY']
      @aws_associate_tag = ENV['AWS_ASSOCIATE_TAG']
    end
    
    def query(search)
      params = {
        "Operation" => "ItemSearch",
        "Service" => "AWSECommerceService",
        "AWSAccessKeyId" => @aws_access_key_id,
        "SearchIndex" => "UnboxVideo",
        "Keywords" => CGI::escape(search),
        "Timestamp" => Time.now.utc.iso8601, #'2010-11-29T06:53:00Z' # Time.now.iso8601
        "Version" => '2011-08-01',
        "AssociateTag" => @aws_associate_tag
      }
      sorted_params = params.sort_by{|x,y| x}.map{|x,y| "#{x}=#{CGI::escape(y)}"}.join('&')
      signature = sign("GET\nwebservices.amazon.com\n/onca/xml\n#{sorted_params}").strip
      url = "#{@endpoint_url}?#{sorted_params}&Signature=#{CGI::escape(signature)}"
      amazon = EM::HttpRequest.new(url).get(:timeout => 10)
      return nil if amazon.response_header.status != 200

      titles = []
      results = Nokogiri::XML(amazon.response)
      results.css("Item").each do |result|
        titles << "#{result.css('ProductGroup').inner_html}: #{result.css('Title').inner_html}"
      end
      titles
    end
    
    protected
      def sign(string)
        hmac = HMAC::SHA256.new(@aws_secret_access_key)
        hmac.update(string)
        Base64.encode64(hmac.digest).chomp
      end
  end
  
  class Hulu
    def initialize
      @endpoint_url = "http://m.hulu.com"
      @ignore_media = ['film_trailer','clip']
    end
    
    def query(search)
      url = "#{@endpoint_url}/search?dp_identifier=hulu&query=#{CGI::escape(search)}&items_per_page=10&page=1"
      hulu = EM::HttpRequest.new(url).get(:timeout => 10)
      return nil if hulu.response_header.status != 200
        
      titles = []
      results = Nokogiri::XML(hulu.response)
      results.xpath("//video").each do |result|
        next if @ignore_media.include?result.css('video-type').inner_html
        append = ""
        if (ishulu = result.css('is-hulu'))
          append = " - Not on hulu!" if ishulu.inner_html == "0"
        end
        titles << "#{result.css('video-type').inner_html}: #{result.css('title').inner_html}#{append}"
      end
      titles
    end
  end
  
  class Itunes
    def initialize
      @endpoint = "http://ax.phobos.apple.com.edgesuite.net/WebObjects/MZStoreServices.woa/wa/wsSearch"
    end
    
    def query(search)
      url = "#{@endpoint}?term=#{CGI::escape(search)}"
      multi = EventMachine::MultiRequest.new
      multi.add :tv,    EM::HttpRequest.new("#{url}&media=tvShow").get(:timeout => 10)
      multi.add :movie, EM::HttpRequest.new("#{url}&media=movie").get(:timeout => 10)
      return nil if multi.requests[:tv].response_header.status != 200 || multi.requests[:movie].response_header.status != 200
           
      titles = []
      results = Yajl::Parser.parse(multi.requests[:tv].response)['results'] | Yajl::Parser.parse(multi.requests[:movie].response)['results']
      results.each do |result|
        titles << "#{result['kind']}: #{result['trackName']} ($#{result['trackPrice']})"
      end
      titles
    end
  end
  
  class Netflix
    def initialize
      @endpoint = "http://odata.netflix.com/v1/Catalog/"
      @format = "json"
    end
    
    def query(search)
      filter = "Name eq '#{search}'"
      url = "#{@endpoint}Titles?$filter=#{CGI::escape(filter)}&$format=#{@format}"
      
      netflix = EM::HttpRequest.new(url).get(:timeout => 10)
      return nil if netflix.response_header.status != 200
      
      titles = []
      results = Yajl::Parser.parse(netflix.response)
      results['d']['results'].each do |result|
        titles << "#{result['Type']}: #{result['Name']}#{result['Instant']['Available'] ? ' - Watch now!' : ''}"
      end
      titles
    end
  end
  
  aget '/search/:keyword' do |keyword|
    Fiber.new do
      EM.synchrony do
        callback = params.delete('callback') # jsonp
        out = JSONP.new
        body out

        [Amazon,Hulu,Itunes,Netflix].each do |klass|
          Fiber.new do
            m = klass.new
            titles = m.query(keyword)
            if titles
              out.stream callback, klass.to_s => ["#{titles}"]
            else
              puts "#{klass.to_s} query failed"
              out.stream callback, "#{klass.to_s} query failed"
            end
          end.resume
        end
      end
    end.resume
  end
end

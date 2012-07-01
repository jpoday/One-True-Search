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

require 'titleize'
#require File.expand_path(File.dirname(__FILE__) + '/lib/mwhich')
require File.expand_path(File.dirname(__FILE__) + '/lib/integer_to_word')

require 'pry'


class Search < Sinatra::Base
  register Sinatra::Async

  class JSONP
    include EventMachine::Deferrable

    def initialize(keyword)
      @counter = 0
      @all_results = Array.new
      @keyword = keyword.downcase.gsub(/[^a-z0-9 ]/,' ').gsub(/(\d+)/) {|num| num.to_i.to_word }
    end
    
    def stream(callback,object)
      if @counter == 0
        # json p plus hack to remove braces to enable single object
        @block.call "#{callback}({#{object.to_json.to_s[1..-2]}"
      else
        @block.call ",#{object.to_json.to_s[1..-2]}"
      end
      @counter += 1
      object.each_pair do |service,results|
        results.each do |result|
          if result[:title].downcase.gsub(/[^a-z0-9 ]/,' ').gsub(/(\d+)/) {|num| num.to_i.to_word }==@keyword
            result[:service] = service[8..-1]
            @all_results << result
          end
        end
      end
      if @counter == 4
        desc = @all_results.select{|r| r[:service]=="Itunes"}[0][:desc]
        image = @all_results.select{|r| r[:service]=="Amazon"}[0][:lg_image]
        top_amazon = @all_results.select{|r| r[:service]=="Amazon"}.min{|a,b| a[:price] <=> b[:price]}
        top_hulu = @all_results.select{|r| r[:service]=="Hulu"}.first
        top_itunes = @all_results.select{|r| r[:service]=="Itunes"}.min{|a,b| a[:price] <=> b[:price]}
        top_netflix = @all_results.select{|r| r[:service]=="Netflix"}.first
        amazon = {:price => top_amazon[:price], :link => top_amazon[:link]} if top_amazon
        hulu = {:video_id => top_hulu[:video_id]} if top_hulu
        itunes = {:price => top_itunes[:price], :link => top_itunes[:link]} if top_itunes
        netflix = {:link => top_netflix[:link], :instant => top_netflix[:instant]} if top_netflix
        top_result = {"TopResult" => {:desc => desc, :title => @keyword.titleize, :image => image, 
                      :amazon => amazon, :hulu => hulu, :itunes => itunes, :netflix => netflix}}
        @block.call ",#{top_result.to_json.to_s[1..-1]})"
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
        "Timestamp" => Time.now.utc.iso8601,
        "Version" => '2011-08-01',
        "AssociateTag" => @aws_associate_tag
      }
      sorted_params = params.sort_by{|x,y| x}.map{|x,y| "#{x}=#{CGI::escape(y)}"}.join('&')
      signature = sign("GET\nwebservices.amazon.com\n/onca/xml\n#{sorted_params}").strip
      url = "#{@endpoint_url}?#{sorted_params}&Signature=#{CGI::escape(signature)}"
      amazon = EM::HttpRequest.new(url).get(:timeout => 10)
      return nil if amazon.response_header.status != 200

      ids = []
      results = Nokogiri::XML(amazon.response)
      
      results.css("Item").each do |result|
        ids << result.css('ASIN').inner_html
      end
      params = {
        "Service" => "AWSECommerceService",
        "AWSAccessKeyId" => @aws_access_key_id,
        "Operation" => "ItemLookup",
        "ItemId" => "#{ids.join(',')}",
        "IdType" => "ASIN",
        "ResponseGroup" => "EditorialReview,ItemAttributes,Images,Offers",
        "Condition" => "New",
        "MerchantID" => "Amazon",
        "Timestamp" => Time.now.utc.iso8601,
        "Version" => '2011-08-01',
        "AssociateTag" => @aws_associate_tag
      }
      sorted_params = params.sort_by{|x,y| x}.map{|x,y| "#{x}=#{CGI::escape(y)}"}.join('&')
      signature = sign("GET\nwebservices.amazon.com\n/onca/xml\n#{sorted_params}").strip
      url = "#{@endpoint_url}?#{sorted_params}&Signature=#{CGI::escape(signature)}"
      amazon = EM::HttpRequest.new(url).get(:timeout => 10)
      return nil if amazon.response_header.status != 200
      
      titles = Array.new
      results = Nokogiri::XML(amazon.response)
      #file_contents = File.read(File.expand_path(File.dirname(__FILE__) + '/examples/prestige-amazon_batch_response_example.xml'))
      #results = Nokogiri::XML(file_contents)
      results.css("Item").each_with_index do |result,i|
        titles << {:title => "#{result.css('Title').inner_html}", 
                   :price => "#{result.css('FormattedPrice').first.inner_html}", 
                   :type => "#{result.css('ProductGroup').inner_html}", 
                   :image => "#{result.css('TinyImage/URL').inner_html}",
                   :lg_image => "#{result.css('LargeImage/URL').first.inner_html}",
                   :link => "#{result.css('DetailPageURL').first.inner_html}"}
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
      #file_contents = File.read(File.expand_path(File.dirname(__FILE__) + '/examples/prestige-hulu.xml'))
      #results = Nokogiri::XML(file_contents)
      
      results.xpath("//video").each do |result|
        next if @ignore_media.include?result.css('video-type').inner_html
        append = ""
        if (ishulu = result.css('is-hulu'))
          append = " - Not on hulu!" if ishulu.inner_html == "0"
        end
        titles << {:title => "#{result.css('title').inner_html}", 
                   :type => "#{result.css('media-type').inner_html} #{result.css('video-type').inner_html}", 
                   :image => "#{result.css('thumbnail-url').inner_html}", 
                   :details => "#{result.css('show/name').inner_html}, Season #{result.css('season-number').inner_html} Episode #{result.css('episode-number').inner_html}",
                   :video_id => "#{result.css('id').first.inner_html}"}
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
      #file_contents = File.read(File.expand_path(File.dirname(__FILE__) + '/examples/prestige-itunes-movie.json'))
      #results = eval(file_contents)

      results.each do |result|
        if result['kind'] == "tv-episode"
          type = "TV episode"
          details = "#{result['collectionName']} Episode #{result['trackNumber']}"
        elsif result['kind'] == "feature-movie"
          type = "Movie"
          details = ""
        end
        titles << {:title => "#{result['trackName']}", 
                   :type => "#{type}", 
                   :image => "#{result['artworkUrl100']}", 
                   :details => "#{details}",
                   :price => "$#{result['trackPrice']}",
                   :desc => "#{result['longDescription']}",
                   :link => "#{result['trackViewUrl']}"}
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
      #file_contents = File.read(File.expand_path(File.dirname(__FILE__) + '/examples/prestige-netflix.json'))
      #results = eval(file_contents)

      results['d']['results'].each do |result|
        titles << {:title => "#{result['Name']}",
                   :type => "#{result['Type']}",
                   :image => "#{result['BoxArt']['MediumUrl']}",
                   :instant => "#{result['Instant']['Available']}",
                   :link => "#{result['Url']}"}
      end
      titles
    end
  end
  
  aget '/search/:keyword' do |keyword|
    Fiber.new do
      EM.synchrony do
        callback = params.delete('callback') # jsonp
        out = JSONP.new(keyword)
        body out
        
        [Amazon,Hulu,Itunes,Netflix].each do |klass|
          Fiber.new do
            m = klass.new
            titles = m.query(keyword)
            if titles
              out.stream callback, klass.to_s => titles
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

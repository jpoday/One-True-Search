require 'sinatra'
require File.dirname(__FILE__) + '/sinatra/output_utils.rb'

module Output
  class JSONP
    include EventMachine::Deferrable

    def initialize(keyword)
      @counter = 0
      @all_results = Results.new
      @keyword = keyword
      @clean_keyword = clean(keyword)
      @output = ""
    end
  
    def stream(callback,object)
      object.each_pair do |service_type,results|
        results.each do |result|
          clean_title = clean(result[:title])
          clean_series = clean(result[:series]) if result[:series]
          if clean_title.include?(@clean_keyword) || (result[:series] && clean_series.include?(@clean_keyword))
            result[:service] = service_type
            @all_results << result
          end
        end
      end
      if @counter == 0
        # json p plus hack to remove braces to enable single object
        #@block.call "#{callback}({#{object.to_json.to_s[1..-2]}"
        @output << "#{callback}({#{object.to_json.to_s[1..-2]}"
      else
        #@block.call ",#{object.to_json.to_s[1..-2]}"
        @output << ",#{object.to_json.to_s[1..-2]}"
      end
      @counter += 1
      
      if @counter == 4
        top_result = TopResult.new(@all_results,@clean_keyword)
        
        # Add screen data
        amazon = {:price => top_result[:amazon][:price], :link => top_result[:amazon][:link]} if top_result[:amazon]
        hulu = {:link => top_result[:hulu][:link]} if top_result[:hulu]
        itunes = {:price => top_result[:itunes][:price], :link => top_result[:itunes][:link]} if top_result[:itunes]
        netflix = {:link => top_result[:netflix][:link], :instant => top_result[:netflix][:instant], 
                   :dvd => top_result[:netflix][:DVD], :bluray => top_result[:netflix][:"Blu-ray"]} if top_result[:netflix]

        # Full series or Movie
        if top_result.series_check
          image = top_result.set_image
          desc = top_result.set_desc
          screen_results = {"TopResult" => {:desc => desc, 
                                            :title => @keyword.titleize, 
                                            :image => image, 
                                            :amazon => amazon, 
                                            :hulu => hulu, 
                                            :itunes => itunes, 
                                            :netflix => netflix}}
        else # Mixed series results
          # merge mixed results
          amazon.merge!(:title => top_result[:amazon][:title],
                        :series => /\d/.match(top_result[:amazon][:series])[0], 
                        :episode => top_result[:amazon][:episode],
                        :image => top_result[:amazon][:image]) if amazon
          hulu.merge!(:title => top_result[:hulu][:title],
                      :series => /\d/.match(top_result[:hulu][:series])[0], 
                      :episode => top_result[:hulu][:episode],
                      :image => top_result[:hulu][:image]) if hulu
          itunes.merge!(:title => top_result[:itunes][:title],
                        :image => top_result[:itunes][:image]) if itunes
          itunes.merge!(:series => /\d/.match(top_result[:itunes][:series])[0],
                        :episode => top_result[:itunes][:episode]) if top_result[:itunes] && top_result[:itunes][:series]
          netflix.merge!(:title => top_result[:netflix][:title],
                         :image => top_result[:netflix][:image]) if netflix
                         
          screen_results = {"MixedResults" => {:amazon => amazon, 
                                               :hulu => hulu, 
                                               :itunes => itunes, 
                                               :netflix => netflix}}
        end
        #@block.call ",#{screen_results.to_json.to_s[1..-1]})"
        @output << ",#{screen_results.to_json.to_s[1..-1]})"
        @block.call @output
        self.succeed
      end
    end

    def each(&block)
      @block = block
    end
  end
end
class JSONP
  include EventMachine::Deferrable

  def initialize(keyword)
    @counter = 0
    @all_results = Array.new
    @keyword = keyword
    @clean_keyword = keyword.downcase.gsub("'","").gsub(/[^a-z0-9 ]/,' ').gsub(/(\d+)/) {|num| num.to_i.to_word }
  end
  
  def stream(callback,object)
    object.each_pair do |service,results|
      results.each do |result|
        clean_title = result[:title].downcase.gsub("'","").gsub(/[^a-z0-9 ]/,' ').gsub(/(\d+)/) {|num| num.to_i.to_word }
        clean_series = result[:series].downcase.gsub("'","").gsub(/[^a-z0-9 ]/,' ').gsub(/(\d+)/) {|num| num.to_i.to_word } if result[:series]
        if clean_title.include?(@clean_keyword) || (result[:series] && clean_series.include?(@clean_keyword))
          result[:service] = service
          @all_results << result
        end
      end
    end
    if @counter == 0
      # json p plus hack to remove braces to enable single object
      @block.call "#{callback}({#{object.to_json.to_s[1..-2]}"
    else
      @block.call ",#{object.to_json.to_s[1..-2]}"
    end
    @counter += 1
    if @counter == 4
      top = Hash.new
      top[:amazon] = @all_results.select{|r| r[:service]=="Amazon"}.min{|a,b| a[:price] <=> b[:price]}
      top[:hulu] = @all_results.select{|r| r[:service]=="Hulu"}.first
      if @all_results.select{|r| r[:service]=="Itunes"}.collect{|r| r[:series]}
        top[:itunes] = @all_results.select{|r| r[:service]=="Itunes"}.sort_by{|r| r[:episode]}.sort_by{|r| r[:series]}.last
      else
        top[:itunes] = @all_results.select{|r| r[:service]=="Itunes"}.min{|a,b| a[:price] <=> b[:price]}
      end
      top[:netflix] = @all_results.select{|r| r[:service]=="Netflix"}.first
      
      amazon = {:price => top[:amazon][:price], :link => top[:amazon][:link]} if top[:amazon]
      hulu = {:link => top[:hulu][:link]} if top[:hulu]
      itunes = {:price => top[:itunes][:price], :link => top[:itunes][:link]} if top[:itunes]
      netflix = {:link => top[:netflix][:link], :instant => top[:netflix][:instant]} if top[:netflix]
         
      # Not a series
      if top.delete_if{|k,v| v.nil?}.collect{|r| r[1][:title] if !r[1].nil?}.uniq{|s| s.downcase.gsub("'","").gsub(/[^a-z0-9 ]/,' ').gsub(/(\d+)/) {|num| num.to_i.to_word }}.length == 1        
        if top[:amazon]
          image = top[:amazon][:lg_image] 
        elsif top[:itunes]
          image = top[:itunes][:image]
        elsif top[:netflix]
          image = top[:netflix][:image]
        elsif top[:hulu]
          image = top[:hulu][:image]
        else
          image = ""
        end
      
        if top[:itunes]
          desc = top[:itunes][:desc]
        elsif top[:netflix]
          desc = top[:netflix][:desc]
        elsif top[:hulu]
          desc = top[:hulu][:desc]
        else
          desc = "Results unclear, see all results below"
        end
        
        screen_results = {"TopResult" => {:desc => desc, 
                                          :title => @keyword.titleize, 
                                          :image => image, 
                                          :amazon => amazon, 
                                          :hulu => hulu, 
                                          :itunes => itunes, 
                                          :netflix => netflix}}
      else # Add series data
        amazon.merge!(:title => top[:amazon][:title],
                      :series => /\d/.match(top[:amazon][:series])[0], 
                      :episode => top[:amazon][:episode],
                      :image => top[:amazon][:image]) if amazon
        hulu.merge!(:title => top[:hulu][:title],
                    :series => /\d/.match(top[:hulu][:series])[0], 
                    :episode => top[:hulu][:episode],
                    :image => top[:hulu][:image]) if hulu
        itunes.merge!(:title => top[:itunes][:title],
                      :series => /\d/.match(top[:itunes][:series])[0], 
                      :episode => top[:itunes][:episode],
                      :image => top[:itunes][:image]) if itunes
        screen_results = {"MixedResults" => {:amazon => amazon, 
                                             :hulu => hulu, 
                                             :itunes => itunes, 
                                             :netflix => netflix}}
      end
      @block.call ",#{screen_results.to_json.to_s[1..-1]})"
      self.succeed
    end
  end

  def each(&block)
    @block = block
  end
end
require 'sinatra/base'

module Sinatra
  module OutputUtils
    def clean(title)
      title.downcase.gsub("'","").gsub(/[^a-z0-9 ]/,' ').gsub(/(\d+)/) {|num| num.to_i.to_word }.gsub("hd","").strip.squeeze(' ')
    end
  end
  
  register OutputUtils
end
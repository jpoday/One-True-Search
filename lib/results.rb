module Output
  class Results < Array
  
    def sort_by_season
      sort{|a,b| ( a[:episode] and a[:series] and b[:episode] and b[:series]) ? [a[:series], a[:episode]] <=> [b[:series], b[:episode]] : ( a[:series] ? 1 : -1 )}
    end
  
    def filter_service(name)
      not_wanted = %w[Amazon Hulu Itunes Netflix]
      not_wanted = not_wanted - name.split
      reject{|r| not_wanted.include?(r[:service])}
    end
  
    def min_price
      min{|a,b| a[:price] <=> b[:price]}
    end
  
    def exact_title_match(keyword)
      reject{|r| clean(r[:title]) != keyword}
    end
  end
  
  class TopResult < Hash
    
    def initialize(all_results,clean_keyword)
      self[:amazon] = all_results.filter_service("Amazon").exact_title_match(clean_keyword).min_price
      if self[:amazon].nil?
        self[:amazon] = all_results.filter_service("Amazon").sort_by_season.first
      end
      
      self[:hulu] = all_results.filter_service("Hulu").first
      
      self[:itunes] = all_results.filter_service("Itunes").exact_title_match(clean_keyword).min_price
      if self[:itunes].nil?
        self[:itunes] = all_results.filter_service("Itunes").sort_by_season.first
      end
      
      self[:netflix] = all_results.filter_service("Netflix").first
      self
    end
    
    def series_check
      @top = delete_nils
      if uniqueness("title") || uniqueness("series") || netflix_left_out
        true
      else
        false
      end
    end
    
    def set_image
      if self[:amazon]
        image = self[:amazon][:lg_image]
      elsif self[:itunes]
        image = self[:itunes][:image]
      elsif self[:netflix]
        image = self[:netflix][:image]
      elsif self[:hulu]
        image = self[:hulu][:image]
      else
        image = ""
      end
      image
    end
    
    def set_desc
      if self[:itunes]
        desc = self[:itunes][:desc]
      elsif self[:netflix]
        desc = self[:netflix][:desc]
      elsif self[:hulu]
        desc = self[:hulu][:desc]
      else
        desc = "Results unclear, see all results below"
      end
      desc
    end
    
    private
    
      def delete_nils
        self.delete_if{|k,v| v.nil?}
      end
      
      def uniqueness(key)
        if collect_clean_keys(key).length == 1
          return true
        end
      end
      
      def collect_clean_keys(key)
        @top.collect{|r| r[1][key.to_sym] unless r[1].nil?}.uniq{|k| clean(k) unless k.nil?}
      end
      
      def netflix_left_out
        @top = @top.reject{|s| s == :netflix}
        series = collect_clean_keys("series")
        if series.length == 1
          return series[0].include? self[:netflix][:series]
        end
      end
  end
end
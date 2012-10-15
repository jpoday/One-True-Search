class Netflix
  def initialize
    @endpoint = "http://api-public.netflix.com/catalog/titles"
    @oauth_consumer_key = ENV['NETFLIX_CONSUMER_KEY']
    @oauth_secret_access_key = ENV['NETFLIX_SECRET_KEY']
  end
  
  def query(search)
    sorted_params = sort_and_escape_params(search_params(search))
    signature = sign(sorted_params).strip
    url = "#{@endpoint}?#{sorted_params}&oauth_signature=#{signature}"
    netflix = EM::HttpRequest.new(url).get(:timeout => 10)
    return nil if netflix.response_header.status != 200

    titles = []
    results = Nokogiri::XML(netflix.response)
    results.css("catalog_title").each do |result|
      details = {:title => "#{result.css('title').attr("regular").value}",
                 :type => "#{result.css('id').inner_html.match("series|movie")[0].capitalize}",
                 :image => "#{result.css('box_art').attr("medium").value}",
                 :link => "#{result.xpath("link[@title = 'web page']").attr('href').value}",
                 :desc => "#{result.css('synopsis').inner_html}"}
      result.css("availability/category").each do |format|
        details[format.attr('term').to_sym] = true
      end
      if details[:type] == "Series"
        details[:series] = details[:title]
      end
      titles << details
    end
    titles
  end
  
  protected 
    def search_params(search)
      params = {
        "term" => search,
        "max_results" => "10",
        "oauth_consumer_key" => @oauth_consumer_key,
        "oauth_nonce" => (0...4).map{rand(9)}.join,
        "oauth_signature_method" => "HMAC-SHA1",
        "oauth_timestamp" => Time.now.to_i.to_s,
        "oauth_version" => "1.0",
        "expand" => "formats,synopsis"
      }
    end
    
    def sort_and_escape_params(params)
      params.sort_by{|x,y| x}.map{|x,y| "#{x}=#{CGI::escape(y).gsub("+","%20")}"}.join('&')
    end
  
    def sign(params)
      params = CGI::escape(params)
      hmac = HMAC::SHA1.new(@oauth_secret_access_key+"&")
      hmac.update("GET&#{CGI::escape(@endpoint)}&"+params)
      CGI::escape(Base64.encode64(hmac.digest).chomp)
    end
end
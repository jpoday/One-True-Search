class Amazon
  def initialize
    @endpoint_url = "http://webservices.amazon.com/onca/xml"
    @aws_access_key_id = ENV['AWS_ACCESS_KEY_ID']
    @aws_secret_access_key = ENV['AWS_SECRET_ACCESS_KEY']
    @aws_associate_tag = ENV['AWS_ASSOCIATE_TAG']
  end
  
  def query(search)
    sorted_params = sort_and_escape_params(bulk_search_params(search))
    signature = sign("GET\nwebservices.amazon.com\n/onca/xml\n#{sorted_params}").strip
    url = "#{@endpoint_url}?#{sorted_params}&Signature=#{CGI::escape(signature)}"
    amazon = EM::HttpRequest.new(url).get(:timeout => 10)
    return nil if amazon.response_header.status != 200
    
    ids = []
    results = Nokogiri::XML(amazon.response)
    results.css("Item").each do |result|
      ids << result.css('ASIN').inner_html
    end
    
    sorted_params = sort_and_escape_params(detail_search_params(ids))
    signature = sign("GET\nwebservices.amazon.com\n/onca/xml\n#{sorted_params}").strip
    url = "#{@endpoint_url}?#{sorted_params}&Signature=#{CGI::escape(signature)}"
    amazon = EM::HttpRequest.new(url).get(:timeout => 10)
    return nil if amazon.response_header.status != 200
    
    titles = Array.new
    results = Nokogiri::XML(amazon.response)
    #file_contents = File.read(File.expand_path(File.dirname(__FILE__) + '/examples/prestige-amazon_batch_response_example.xml'))
    #results = Nokogiri::XML(file_contents)
    results.css("ItemLookupResponse/Items/Item").each do |result|
      if result.css('FormattedPrice').empty? || result.css('FormattedPrice').first.inner_html == "$0.00"
        price = "FREE"
      else
        price = "#{result.css('FormattedPrice').first.inner_html}"
      end
      details = {:title => "#{result.css('Title').first.inner_html}", 
                 :price => price,
                 :image => "#{result.css('TinyImage/URL').inner_html}",
                 :lg_image => "#{result.css('LargeImage/URL').first.inner_html}",
                 :link => "#{result.css('DetailPageURL').first.inner_html}"}
      if result.css('ProductGroup').first.inner_html == "TV Series Episode Video on Demand"
        details[:series] = "#{result.css('RelatedItem/Item/ItemAttributes/Title').inner_html}"
        details[:episode] = "#{result.css('EpisodeSequence').first.inner_html}"
      end
      if details[:title] =~ /recap|sneak peek/i || (details[:episode] && details[:episode]=="0")
        next
      end
      titles << details
    end
    titles
  end
  
  protected
    def bulk_search_params(search)
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
    end
  
    def detail_search_params(ids)
      params = {
        "Service" => "AWSECommerceService",
        "AWSAccessKeyId" => @aws_access_key_id,
        "Operation" => "ItemLookup",
        "ItemId" => "#{ids.join(',')}",
        "IdType" => "ASIN",
        "ResponseGroup" => "ItemAttributes,RelatedItems,Images,Offers",
        "RelationshipType" => "Episode",
        "Condition" => "New",
        "MerchantID" => "Amazon",
        "Timestamp" => Time.now.utc.iso8601,
        "Version" => '2011-08-01',
        "AssociateTag" => @aws_associate_tag
      }
    end
    
    def sort_and_escape_params(params)
      params.sort_by{|x,y| x}.map{|x,y| "#{x}=#{CGI::escape(y)}"}.join('&')
    end
  
    def sign(string)
      hmac = HMAC::SHA256.new(@aws_secret_access_key)
      hmac.update(string)
      Base64.encode64(hmac.digest).chomp
    end
end
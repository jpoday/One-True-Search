class NetflixOData
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
      details = {:title => "#{result['Name']}",
                 :type => "#{result['Type']}",
                 :image => "#{result['BoxArt']['MediumUrl']}",
                 :instant => "#{result['Instant']['Available']}",
                 :link => "#{result['Url']}",
                 :desc => "#{result['Synopsis']}"}
      if details[:type] == "Series"
        details[:series] = details[:title]
      end
      titles << details
    end
    titles
  end
end
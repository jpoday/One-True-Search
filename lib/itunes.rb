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
      details = {:title => "#{result['trackName']}",
                 :price => "$#{result['trackPrice']}",
                 :image => "#{result['artworkUrl100']}",
                 :link => "#{result['trackViewUrl']}",
                 :desc => "#{result['longDescription']}"}
      if details[:price][1..-1].to_f < 0
        next
      elsif details[:title] =~ /recap|sneak peek/i
        next
      elsif result['kind'] == "tv-episode"
        details[:series] = "#{result['collectionName']}"
        details[:episode] = "#{result['trackNumber']}"
      end
      titles << details
    end
    titles
  end
end
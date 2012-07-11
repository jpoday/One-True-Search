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
      details = {:title => "#{result.css('title').inner_html}", 
                 :image => "#{result.css('thumbnail-url').inner_html}",
                 :link => "http://www.hulu.com/watch/#{result.css('id').first.inner_html}",
                 :desc => "#{result.css('full-description').inner_html}"}
      unless result.css('media-type').inner_html == "Film"
        details[:series] = "#{result.css('show/name').inner_html}, Season #{result.css('season-number').inner_html}"
        details[:episode] = "#{result.css('episode-number').inner_html}"
      end
      titles << details
    end
    titles
  end
end
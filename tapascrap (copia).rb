require 'open-uri'
require 'nokogiri'

TOPIC_START = 1
TOPIC_END = 24462

def url(t, s)
  URI("https://www.tapatalk.com/groups/metanetfr/viewtopic.php?t=#{t}&start=#{s}")
end

def download(t, s)
  Nokogiri::HTML(open(url(t, s)))
end

def parse_posts(t, s)
  doc = download(t, s)
  posts = doc.at('div[class="viewtopic_wrapper topic_data_for_js"]')
             .search('div[class="postbody"]')
             .map{ |p|
               content = p.at('div[class="content"]')
               content.search('i[class="hide"]').last.remove
               {
                 id:       p['id'][/\d+/].to_i,
                 user:     p.parent.at('dl')['data-uid'].to_i,
                 username: p.parent.at('dl').at('a[itemprop="name"]').content,
                 date:     p.at('time')['datetime'],
                 content:  content.inner_html
               }
             }
end

require 'open-uri'
require 'nokogiri'

TOPIC_START = 1
TOPIC_END = 24462

def url_thread(t, s)
  URI("https://www.tapatalk.com/groups/metanetfr/viewtopic.php?t=#{t}&start=#{s}")
end

def url_member(id)
  URI("https://www.tapatalk.com/groups/metanetfr/memberlist.php?mode=viewprofile&u=#{id}")
end

def download_thread(t, s)
  Nokogiri::HTML(open(url_thread(t, s)))
end

def download_member(id)
  Nokogiri::HTML(open(url_member(id)))
end

def parse_member(id)
  doc = download_member(id)
  atts = {
    username: doc.at('span[class="edit-username-span"]')['data-origin-name'],
    rank: doc.at('span[class="profile-rank-name"]').content
  }
  fields = doc.search('div[class="group"]')[1].search('div[class="cl-af"]')

  field = fields.select{ |f| f.children[0].content.downcase == "birthday" }[0]
  atts[:birthday] = field.children[1].content if !field.nil?
  field = fields.select{ |f| f.children[0].content.downcase == "joined" }[0]
  atts[:joined] = field.at('span[class="timespan"]')['title'] if !field.nil?
  field = fields.select{ |f| f.children[0].content.downcase == "last active" }[0]
  atts[:active] = field.at('span[class="timespan"]')['title'] if !field.nil?
  field = fields.select{ |f| f.children[0].content.downcase == "total posts" }[0]
  atts[:posts] = field.at('a').content.strip.to_i if !field.nil?
  
  field = fields.select{ |f| f.children[0].content.downcase == "groups" }[0]
  if !field.nil?
    groups = field.search('option').map{ |g| [g['value'].to_i, g.content] }.to_h
    atts[:groups] = groups.keys
  end

  atts[:signature] = doc.at('div[class="signature standalone"]').inner_html rescue nil
end

def parse_thread(t, s)
  doc = download_thread(t, s)
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

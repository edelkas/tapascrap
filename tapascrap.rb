# Modules
require 'open-uri'
# Gems
require 'nokogiri'
require 'active_record'

THREAD_START = 1
THREAD_END = 24462
FORUM_START = 1
FORUM_END = 66
POSTS_PER_PAGE = 10
CONFIG = {
  'adapter'  => 'sqlite3',
  'database' => 'tapa.sql'
}

class Post < ActiveRecord::Base
  belongs_to :thread
  belongs_to :user
end

class Thread < ActiveRecord::Base
  belongs_to :forum
  belongs_to :user
  has_many :posts
end

class Forum < ActiveRecord::Base
  has_many :threads
end

class User < ActiveRecord::Base
  has_many :posts
  has_many :threads
  has_and_belongs_to_many :groups
end

class Group < ActiveRecord::Base
  has_and_belongs_to_many :users
end

def setup_db
  ActiveRecord::Base.establish_connection(
    :adapter  => CONFIG['adapter'],
    :database => CONFIG['database']
  )
  ActiveRecord::Base.connection.create_table :posts do |t|
    t.references :thread, index: true
    t.references :user, index: true
    t.timestamp :date
    t.string :content
  end
  ActiveRecord::Base.connection.create_table :threads do |t|
    t.references :forum, index: true
    t.references :user, index: true
    t.string :name
    t.timestamp :date
    t.boolean :pinned
    t.boolean :locked
    t.boolean :announcement
    t.boolean :poll
  end
  ActiveRecord::Base.connection.create_table :forums do |t|
    t.references :parent
    t.string :name
    t.string :description
  end
  ActiveRecord::Base.connection.create_table :users do |t|
    t.string :name
    t.string :rank
    t.timestamp :birthday
    t.timestamp :joined
    t.timestamp :active
    t.string :signature
  end
  ActiveRecord::Base.connection.create_table :groups do |t|
    t.string :name
  end
  ActiveRecord::Base.connection.create_table :users_groups do |t|
    t.references :user
    t.references :group
  end
end


def url_thread(t, s = 0)
  URI("https://www.tapatalk.com/groups/metanetfr/viewtopic.php?t=#{t}&start=#{s}")
end

def url_member(id)
  URI("https://www.tapatalk.com/groups/metanetfr/memberlist.php?mode=viewprofile&u=#{id}")
end

def url_forum(id)
  URI("https://www.tapatalk.com/groups/metanetfr/viewforum.php?f=#{id}")
end

def download_thread(t, s)
  Nokogiri::HTML(open(url_thread(t, s)))
end

def download_member(id)
  Nokogiri::HTML(open(url_member(id)))
end

def download_forum(id)
  Nokogiri::HTML(open(url_forum(id)))
end

def parse_posts(t, s)
  doc = download_thread(t, s) rescue nil
  return if doc.nil? # thread does not exist
  posts = doc.at('div[class="viewtopic_wrapper topic_data_for_js"]')
             .search('div[class="postbody"]')
             .map{ |p|
               content = p.at('div[class="content"]')
               content.search('i[class="hide"]').last.remove
               {
                 t: t,
                 id:       p['id'][/\d+/].to_i,
                 user:     p.parent.at('dl')['data-uid'].to_i,
                 username: p.parent.at('dl').at('a[itemprop="name"]').content,
                 date:     p.at('time')['datetime'],
                 content:  content.inner_html
               }
             }
end

def parse_thread(t)
  doc = download_thread(t) rescue nil
  return if doc.nil? # thread does not exist
  atts = {
    id: t,
    forum: doc.search('span[data-forum-id]').last['data-forum-id'].to_i,
    name: doc.at('h1[itemprop="headline"]').content.to_s,
    user_id: doc.at('h1[itemprop="headline"]').parent.at('dl')['data-uid'],
    username: doc.at('h1[itemprop="headline"]').parent.at('a[class="username"]').content.to_s,
    posts: doc.at('div[class="pagination"]').content[/\d+/i].to_i,
    pages: doc.at('div[class="pagination"]').search('a[class="button"]').last.content.to_i
  }
  (1..atts[:pages]).each{ |page| parse_posts(t, POSTS_PER_PAGE * (s - 1)) }
end

def parse_threads
  (THREAD_START..THREAD_END).each{ |t| parse_thread(t) }
end

# Note: Since we don't know the member list, we should first parse all posts,
# and create all members based on the posts (we won't be able to find members
# who didn't post). After that, we loop through them executing this method.
def parse_member(id)
  doc = download_member(id) rescue nil
  return if doc.nil? # member does not exist
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

def parse_forum(id)
  doc = download_forum(id) rescue nil
  return if doc.nil? # forum does not exist
  atts = {
    id: id,
    name: doc.at('h2').content.strip rescue "",
    description: doc.at('p[class="forum-description cl-af"]').content rescue "",
    parent: doc.search('span[data-forum-id]').last['data-forum-id'].to_i rescue 0 # 0 if root
  }
end

def setup
  setup_db if !File.file?(CONFIG['database'])
end

setup

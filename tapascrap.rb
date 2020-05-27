# Modules
require 'open-uri'
# Gems
require 'nokogiri'
require 'active_record'

TOPIC_START = 1
TOPIC_END = 24462
FORUM_START = 1
FORUM_END = 66
POSTS_PER_PAGE = 10
TOPICS_PER_FORUM = 25
CONFIG = {
  'adapter'  => 'sqlite3',
  'database' => 'db.sql'
}

class Post < ActiveRecord::Base
  belongs_to :topic
  belongs_to :user
end

class Topic < ActiveRecord::Base
  belongs_to :forum
  belongs_to :user
  has_many :posts
end

class Forum < ActiveRecord::Base
  has_many :topics
end

class User < ActiveRecord::Base
  has_many :posts
  has_many :topics
  has_and_belongs_to_many :groups
end

class Group < ActiveRecord::Base
  has_and_belongs_to_many :users
end

class Config < ActiveRecord::Base
end

def setup_db
  ActiveRecord::Base.establish_connection(
    :adapter  => CONFIG['adapter'],
    :database => CONFIG['database']
  )
  ActiveRecord::Base.connection.create_table :posts do |t|
    t.references :topic, index: true
    t.references :user, index: true
    t.timestamp :date
    t.string :content
  end
  ActiveRecord::Base.connection.create_table :topics do |t|
    t.references :forum, index: true
    t.references :user, index: true
    t.string :name
    t.timestamp :date
    t.timestamp :date_last
    t.integer :views
    t.integer :post_count
    t.integer :last_post
    t.boolean :pinned
    t.boolean :locked
    t.boolean :announcement
    t.boolean :poll
  end
  ActiveRecord::Base.connection.create_table :forums do |t|
    t.integer :parent
    t.string :name
    t.string :description
    t.integer :topic_count
    t.integer :last_post
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
  ActiveRecord::Base.connection.create_table :configs do |t|
    t.string :key
    t.string :value
  end
  Config.create(key: "topic start", value: TOPIC_START)
  Config.create(key: "topic end", value: TOPIC_END)
  Config.create(key: "forum start", value: FORUM_START)
  Config.create(key: "forum end", value: FORUM_END)
  Forum.find_or_create_by(id: 0).update(
    name: "Root",
    description: "Root forum.",
    topic_count: 0,
    parent: 0
  )
end


def url_topic(t, s = 0)
  URI("https://www.tapatalk.com/groups/metanetfr/viewtopic.php?t=#{t}&start=#{s}")
end

def url_member(id)
  URI("https://www.tapatalk.com/groups/metanetfr/memberlist.php?mode=viewprofile&u=#{id}")
end

def url_forum(f, s = 0)
  URI("https://www.tapatalk.com/groups/metanetfr/viewforum.php?f=#{f}&start=#{s}")
end

def download_topic(t, s = 0)
  Nokogiri::HTML(open(url_topic(t, s)))
end

def download_member(id)
  Nokogiri::HTML(open(url_member(id)))
end

def download_forum(f, s = 0)
  Nokogiri::HTML(open(url_forum(f, s)))
end

def parse_posts(t, s = 0)
  doc = download_topic(t, s) rescue nil
  return if doc.nil? # topic does not exist
  posts = doc.at('div[class="viewtopic_wrapper topic_data_for_js"]')
             .search('div[class="postbody"]')
             .map{ |p|
               content = p.at('div[class="content"]')
               content.search('i[class="hide"]').last.remove
               {
                 t: t,
                 id:       p['id'][/\d+/].to_i,
                 user:     (p.parent.at('script').content[/"POSTER_ID":"(\d+)"/, 1].to_i rescue 0),
                 username: (p.parent.at('script').content[/"POST_AUTHOR":"(.*?)"/, 1] rescue 'Guest'),
                 date:     p.at('time')['datetime'],
                 content:  content.inner_html
               }
             }
end

def parse_topic(t)
  doc = download_topic(t) rescue nil
  return if doc.nil? # topic does not exist
  atts = {
    id: t,
    forum: doc.search('span[data-forum-id]').last['data-forum-id'].to_i,
    name: doc.at('h1[itemprop="headline"]').content.to_s,
    user_id: doc.at('h1[itemprop="headline"]').parent.at('dl')['data-uid'],
    username: doc.at('h1[itemprop="headline"]').parent.at('a[class="username"]').content.to_s,
    posts: doc.at('div[class="pagination"]').content[/\d+/i].to_i,
    pages: doc.at('div[class="pagination"]').search('a[class="button"]').last.content.to_i
  }
  (1..atts[:pages]).each{ |s| parse_posts(t, POSTS_PER_PAGE * (s - 1)) }
end

def parse_topics
  (TOPIC_START..TOPIC_END).each{ |t| parse_topic(t) }
end

# Note: Since we don't know the member list, we must first parse all posts,
# and create all members based on the posts (we won't be able to find members
# who didn't post). After that, we loop through them executing this method.
def parse_user(id)
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

def parse_users
  User.all.each{ |u| parse_user(u.id) }
end

def scale(s)
  a = s.downcase.split /(?=[a-z])/
  Integer(a.first.to_f * Hash.new(1).merge('k' => 1000, 'm' => 1000**2)[a[1]] + 0.5)
end

def parse_forum_topics(doc, f, type, count, total)
  doc.at(type).at('ul[class="topiclist topics"]').children.each_with_index{ |t, i|
    print("\rParsing forum #{f}. Reading topic #{count + i + 1} / #{total}.")
    replies = t.at('dd[class="posts"]')
    replies.children.last.remove
    replies = replies.content.to_s.strip rescue 1
    views = t.at('dd[class="views"]')
    views.children.last.remove
    views = views.content.to_s.strip rescue 0
    user_id =  t.at('div[class="topic-poster"]').at('a')['href'][/\d+/].to_i rescue 0
    Topic.find_or_create_by(id: t.at('a[class="topictitle"]')['data-topic_id'].to_i).update(
      name: t.at('a[class="topictitle"]').content.to_s,
      forum: Forum.find_or_create_by(id: f),
      user: User.find_or_create_by(id: user_id),
      post_count: scale(replies) + 1,
      views: scale(views),
      date: t.at('time')['datetime'].to_s,
      date_last: t.at('dd[class="lastpost"]').at('span[class="timespan"]')['title'].to_s,
      last_post: t.at('dd[class="lastpost"]').at('span[class="sr-only"]').parent['href'][/#p(\d+)/, 1].to_i,
      pinned: !t.at('i[class="icon icon-small icon-sticky ml5"]').nil?,
      locked: !t.at('i[class="icon icon-small icon-locked ml5"]').nil?,
      poll: !t.at('i[class="icon icon-small icon-poll ml5"]').nil?,
      announcement: type[/announcement/].nil? ? false : true
    )
  }
end

def parse_forum_page(doc, f, count, total)
  parse_forum_topics(doc, f, 'div[class="forumbg announcement"]', count, total) if !doc.at('div[class="forumbg announcement"]').nil?
  parse_forum_topics(doc, f, 'div[class="forumbg normal"]', count, total) if !doc.at('div[class="forumbg normal"]').nil?
end

def parse_forum(f)
  doc = download_forum(f) rescue nil
  return if doc.nil? # forum does not exist
  atts = {}
  atts[:name] = doc.at('h2').content.strip rescue ""
  atts[:description] = doc.at('p[class="forum-description cl-af"]').content rescue ""
  atts[:parent] = doc.search('span[data-forum-id]').last['data-forum-id'].to_i rescue 0 # 0 if root
  atts[:topic_count] = doc.at('div[class="pagination"]').content[/\d+/].to_i rescue 0
  pages = doc.at('div[class="pagination"]').search('a[class="button"]').last.content.to_i rescue 0
  Forum.find_or_create_by(id: f).update(
    name: atts[:name],
    description: atts[:description],
    parent: atts[:parent],
    topic_count: atts[:topic_count]
  )
  parse_forum_page(doc, f, 0, atts[:topic_count])    # parse page 0
  (1..pages - 1).each{ |s| # parse remaining pages
    doc = download_forum(f, TOPICS_PER_FORUM * s)
    parse_forum_page(doc, f, TOPICS_PER_FORUM * s, atts[:topic_count])
  }
end

def parse_forums
  f_start = Config.find_by(key: "topic start") || TOPIC_START
  f_end = Config.find_by(key: "topic end") || TOPIC_END
  (f_start..f_end).each{ |f| parse_forum(f) }
end

def setup
  if !File.file?(CONFIG['database'])
    setup_db
  else
    ActiveRecord::Base.establish_connection(
      :adapter  => CONFIG['adapter'],
      :database => CONFIG['database']
    )
  end
end

def parse
  parse_forums # Creates Forum and Topic objects
  parse_topics # Creates Topic, Post and User objects
  parse_users
end

setup

parse_forum(1)

#parse

puts ""

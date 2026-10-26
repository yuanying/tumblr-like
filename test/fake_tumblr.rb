# Loaded with `ruby -r` ahead of download.rb so that it runs without Tumblr.
# tumblr_client is pointed at a server on loopback, which answers the likes API
# with canned posts and serves the media they link to. Only the host changes, so
# the request still goes through tumblr_client, OAuth signing and faraday's JSON
# middleware, and the run also works with the network turned off.
require 'json'
require 'socket'
require 'tumblr_client'

server = TCPServer.new('127.0.0.1', 0)
host = "127.0.0.1:#{server.addr[1]}"
base = "http://#{host}"

LIKED_POSTS = [
  {
    'type' => 'photo',
    'liked_timestamp' => 1700000300,
    'post_url' => "#{base}/post/photo",
    'photos' => [{ 'original_size' => { 'url' => "#{base}/media/photo.jpg" } }],
    'caption' => %(<p><img src="#{base}/media/caption.png"></p>),
  },
  {
    'type' => 'text',
    'liked_timestamp' => 1700000200,
    'post_url' => "#{base}/post/text",
    'body' => %(<p><img src="#{base}/media/body.jpg"></p>) +
              %(<video poster="#{base}/media/vid1.jpg"><source src="#{base}/media/v.mp4"></video>),
  },
  {
    'type' => 'video',
    'liked_timestamp' => 1700000100,
    'id' => 42,
    'post_url' => "#{base}/post/video",
    'video_url' => "#{base}/media/movie.mp4",
    'thumbnail_url' => "#{base}/media/thumb.jpg",
  },
  {
    'type' => 'photo',
    'liked_timestamp' => 1600000000,
    'post_url' => "#{base}/post/old",
    'photos' => [{ 'original_size' => { 'url' => "#{base}/media/old.jpg" } }],
    'caption' => '',
  },
].freeze

def likes_response(query, authorization)
  unless authorization.include?(%(oauth_consumer_key="#{ENV['TUMBLR_CONSUMER_KEY']}")) &&
         authorization.include?(%(oauth_token="#{ENV['TUMBLR_CONSUMER_TOKEN']}"))
    return [401, { 'meta' => { 'status' => 401, 'msg' => 'Unauthorized' } }]
  end
  offset = query[/(?:\A|&)offset=(\d+)/, 1].to_i
  posts = LIKED_POSTS[offset, LIKED_POSTS.size] || []
  [200, { 'meta' => { 'status' => 200 },
          'response' => { 'liked_posts' => posts, 'liked_count' => LIKED_POSTS.size } }]
end

Thread.new do
  loop do
    client = server.accept
    target = client.gets.to_s.split(' ')[1].to_s
    path, query = target.split('?', 2)
    headers = {}
    while (line = client.gets) && line != "\r\n"
      name, value = line.split(':', 2)
      headers[name.downcase] = value.to_s.strip
    end
    if path == '/v2/user/likes'
      status, body = likes_response(query.to_s, headers['authorization'].to_s)
      type = 'application/json'
      body = JSON.generate(body)
    else
      status, type, body = 200, 'application/octet-stream', path
    end
    client.write "HTTP/1.1 #{status} X\r\nContent-Type: #{type}\r\n" \
                 "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
    client.close
  end
end

Tumblr.configure { |config| config.api_scheme = 'http' }
# tumblr_client reads the host from here.
ENV['TUMBLR_API_HOST'] = host

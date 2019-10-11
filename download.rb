#!/usr/bin/env ruby
require 'open-uri'
require 'tumblr_client'
require 'nokogiri'
require 'fileutils'

script_dir    = File.expand_path(File.dirname(__FILE__))
contents_path = File.join(script_dir, 'contents')

FileUtils.mkdir_p(contents_path)

timestamp_file = File.join(contents_path, '.timestamp')
timestamp = 0

open(timestamp_file) do |io|
  timestamp = io.read.to_i
end if File.exists?(timestamp_file)

Tumblr.configure do |config|
  config.consumer_key       = ENV['TUMBLR_CONSUMER_KEY']
  config.consumer_secret    = ENV['TUMBLR_CONSUMER_SECRET']
  config.oauth_token        = ENV['TUMBLR_CONSUMER_TOKEN']
  config.oauth_token_secret = ENV['TUMBLR_CONSUMER_TOKEN_SECRET']
end

client          = Tumblr::Client.new
offset          = 0
saved_timestamp = nil

def create_filepath(contents_path, current_timestamp, url, filename=nil)
  time = Time.at(current_timestamp.to_i)
  year = time.year
  filename ||= File.basename(url)
  filename = "#{9999999999999 - current_timestamp}-#{filename}"
  filedir  = "#{contents_path}/#{year}"
  FileUtils.mkdir_p(filedir) unless File.directory?(filedir)
  filepath = "#{filedir}/#{filename}"

  filepath
end

def download like, url, filepath
  puts "url: #{url}"
  puts "filepath: #{filepath}"
  begin
    unless File.exists?(filepath)
      open(url) do |input|
        open(filepath, 'w') do |output|
          output.write input.read
        end
      end
      sleep 1
    else
      puts "Skipped: #{File.basename(filepath)}"
    end
  rescue => ex
    p ex
    puts "Can't download #{like['post_url']}"
  end
end

def download_photos(contents_path, like)
  current_timestamp = like['liked_timestamp']

  like['photos'].each do |photo|
    url = photo['original_size']['url']
    filepath = create_filepath(contents_path, current_timestamp, url)

    download(like, url, filepath)
  end
rescue => ex
  require 'pp'
  pp like
  pp ex
end

def download_text(contents_path, like)
  current_timestamp = like['liked_timestamp']

  like = Nokogiri::HTML.parse(like['body'])
  like.css('img').each do |img|
    url = img['src']
    filepath = create_filepath(contents_path, current_timestamp, url)

    download(like, url, filepath)
  end
rescue => ex
  require 'pp'
  pp like
  pp ex
end

def download_video(contents_path, like)
  current_timestamp = like['liked_timestamp']
  video_id = like['id']

  video_url = like['video_url']
  video_ext = File.extname(video_url)
  video_filename = "#{video_id}#{video_ext}"
  video_filepath = create_filepath(
    contents_path,
    current_timestamp,
    video_url,
    video_filename,
  )
  download(like, video_url, video_filepath)
  thumbnail_url = like['thumbnail_url']
  thumbnail_ext = File.extname(thumbnail_url)
  thumbnail_filename = "#{video_id}#{thumbnail_ext}"
  thumbnail_filepath = create_filepath(
    contents_path,
    current_timestamp,
    thumbnail_url,
    thumbnail_filename,
  )
  download(like, thumbnail_url, thumbnail_filepath)
rescue => ex
  require 'pp'
  pp like
  p like['video_url']
  pp ex
end

while true do
  likes = client.likes(offset: offset)
  likes['liked_posts'].each do |like|
    current_timestamp = like['liked_timestamp']
    unless saved_timestamp
      open(timestamp_file, 'w') do |io|
        saved_timestamp = current_timestamp
        io.write saved_timestamp
      end
    end
    if current_timestamp <= timestamp
      exit 0
    end

    puts "like! #{current_timestamp}"
    puts "Type: #{like['type']}"
    if like['type'] == 'photo'
      download_photos(contents_path, like)
    elsif like['type'] == 'video'
      download_video(contents_path, like)
    elsif like['type'] == 'text'
      download_text(contents_path, like)
    end

  end

  puts '========================================'

  offset += likes['liked_posts'].size
  if offset >= likes['liked_count']
    exit 0
  end
  if likes['liked_posts'].size == 0
    exit 0
  end
end

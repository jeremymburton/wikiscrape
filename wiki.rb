require "nokogiri"
require "open-uri"
require "csv"

BASE_URL = "https://en.wikipedia.org"

# This can likely be significantly improved but the time taken to execute this is minimal compared to the time taken to retrieve the page
def text_outside_brackets text
  pos = 0
  depth = 0
  output = ""
  inside_link = false
  
  while true
    bracket_pos = text.index(/[\(|\)]/, pos)
    
    link_open_pos = text.index("<a ", pos)
    link_close_pos = text.index("</a", pos)
    
    inside_link = (link_close_pos && (link_open_pos.nil? || link_close_pos < link_open_pos))
    
    if bracket_pos.nil?
      output = "#{output}#{text[pos..-1]}"
      break
    elsif text[bracket_pos] == '('
      if depth <= 0 
        output = "#{output}#{text[pos...bracket_pos]}"
      end
      depth += 1
    else # Close bracket
      if inside_link
        output = "#{output}#{text[pos - 1...bracket_pos + 1]}"
      end
      depth -= 1
    end
    
    pos = bracket_pos + 1
  end
  
  output
end

def get_article url
  doc = Nokogiri::HTML(open("#{BASE_URL}#{url}"))

  article_title = doc.css("h1#firstHeading").text

  text = doc.css("div.mw-parser-output > p").to_s
  text += doc.css("div.mw-parser-output > ul > li").to_s
    
  text = text_outside_brackets text

  doc_fragment = Nokogiri::HTML(text)

  first_link = doc_fragment.css("p > a").first
  
  if first_link.nil?
    first_link = doc_fragment.css("li > a").first
    puts first_link.to_s
  end
  
  return article_title, first_link.attr('href'), first_link.attr('title')
end

def follow_link link, link_counts, link_cache
  visited_links = []
  current_link = link
  hit_philosophy = false

  while true
    visited_links << current_link
    
    if current_link != "/wiki/Special:Random" && link_cache.has_key?(current_link)
      current_title, next_link, next_title = link_cache[current_link]
      cached = true
    else
      current_title, next_link, next_title = get_article current_link
      link_cache[current_link] = [current_title, next_link, next_title]
      cached = false
    end

    puts "#{current_title} (#{current_link}) leads to #{next_title} (#{next_link}) #{cached ? 'CACHED' : 'NEW'}"

    if visited_links.include? next_link
      puts "Loop detected - already visted: #{next_link} - total links: #{visited_links.length}"
      break
    elsif next_link == "/wiki/Philosophy"
      puts "HIT PHILOSOPHY after #{visited_links.length} links"
      hit_philosophy = true
    end
    current_link = next_link
  end
  
  visited_links.each do |link|
    if link_counts.has_key? link
      link_counts[link] = link_counts[link] + 1
    else
      link_counts[link] = 1
    end
  end
  
  return visited_links.length, hit_philosophy, visited_links
end

runs = 20000

link_cache = {}
link_counts = {}
total_depth = 0
success_count = 0
depth_counts = {}
error_messages = []
start_time = Time.now
biggest_depth = 0
biggest_depth_page = ""
depths = {}

runs.times do
  begin
    depth, success, visited_links = follow_link "/wiki/Special:Random", link_counts, link_cache
    total_depth += depth
    
    if depth_counts.has_key? depth
      depth_counts[depth] = depth_counts[depth] + 1
    else
      depth_counts[depth] = 1
    end
    
    if success
      success_count += 1
    end
    
    depths[visited_links[1]] = depth
    
    if depth > biggest_depth
      biggest_depth = depth
      biggest_depth_page = visited_links[1]
    end
  rescue => e
    error_messages << e.message
  end
end


# Handle depths
CSV.open("depths_#{Time.now.to_i}.csv", "wb") do |csv|
  csv << ["link", "depth"]
  ds = depths.sort_by {|k, v| -v}.to_h
  ds.keys.each do |k|
    csv << [k, ds[k]]
  end
end


# Handle link counts
puts "Link counts:"
puts link_counts.sort_by {|k, v| runs - v}.to_h

CSV.open("link_counts_#{Time.now.to_i}.csv", "wb") do |csv|
  csv << ["link", "count"]
  lc = link_counts.sort_by {|k, v| runs - v}.to_h
  lc.keys.each do |k|
    csv << [k, lc[k]]
  end
end

# Handle depth distribution
CSV.open("depth_distribution_#{Time.now.to_i}.csv", "wb") do |csv|
  csv << ["depth", "count"]
  depth_counts.keys.sort.each do |key|
    csv << [key, depth_counts[key]]
  end
end

puts "Elapsed time: #{Time.now - start_time} seconds"
puts "After #{runs} runs, total depth is #{total_depth} and hit Philosophy #{success_count} times"
puts "Error messages were: #{error_messages}"

puts "Deepest was #{biggest_depth_page} at depth #{biggest_depth}"

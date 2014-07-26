#!/usr/bin/env ruby

require 'fileutils'
require 'open-uri'
require 'digest'
require 'date'

def format_mb(size)
  conv = [ 'b', 'kb', 'mb', 'gb', 'tb', 'pb', 'eb' ];
  scale = 1024;

  ndx=1
  if( size < 2*(scale**ndx)  ) then
    return "#{(size)} #{conv[ndx-1]}"
  end
  size=size.to_f
  [2,3,4,5,6,7].each do |ndx|
    if( size < 2*(scale**ndx)  ) then
      return "#{'%.2f' % (size/(scale**(ndx-1)))} #{conv[ndx-1]}"
    end
  end
  ndx=7
  return "#{'%.2f' % (size/(scale**(ndx-1)))} #{conv[ndx-1]}"
end

puts '********************************************'
puts '* Apache Blur Incubating Release Validator *'
puts '********************************************'
if ARGV.length > 0
  version = ARGV[0]
else
  puts 'Enter version:'
  version = gets.chomp
end
if ARGV.length > 1
  rc = ARGV[1]
else
  puts 'Enter release candidate (enter for blank):'
  rc = gets.chomp
end

url = "https://dist.apache.org/repos/dist/dev/incubator/blur/#{version}-incubating/"
tag = "release-#{version}-incubating"
unless rc.nil? || rc.empty?
  tag += "-#{rc}"
end

puts "Setting up release folders... (#{tag})"
if Dir.exists? tag
  FileUtils.rm_r tag
end
FileUtils.mkdir_p File.join(tag, 'dist')
FileUtils.mkdir_p File.join(tag, 'src')

puts 'Downloading artifacts...'
dist_html = open(url).read
dist_files = dist_html.scan(/apache-blur-#{version}-incubating.*\..*"/)
dist_files.each_with_index do |dist_file, idx|
  clean_dist_file = dist_file.chomp('"')
  open(File.join(tag, 'dist', clean_dist_file), 'wb') do |file|
    puts "\rFetching #{idx+1} of #{dist_files.size}".ljust(60)
    length = 0
    file_url = url.chomp('/') + '/' + clean_dist_file
    file << open(file_url,
      :progress_proc => lambda{|size| print "\r#{format_mb(size)} of #{length}".ljust(60)},
      :content_length_proc => lambda{|size| length = format_mb(size)},
      :read_timeout => 30
    ).read
  end
end

puts "\rVerifying checksums..."
Dir.glob(File.join(tag, 'dist', '*.gz')) do |file|
  actual_md5 = "MD5 (#{File.basename(file)}) = #{Digest::MD5.file(file).hexdigest}"
  proposed_md5 = File.read("#{file}.md5").chomp

  if actual_md5 == proposed_md5
    puts "\u2713.....#{File.basename(file)} - MD5"
  else
    puts "fail.....#{File.basename(file)} - MD5"
  end

  actual_sha1 = "#{Digest::SHA1.file(file).hexdigest}  #{File.basename(file)}"
  proposed_sha1 = File.read("#{file}.sha1").chomp

  if actual_sha1 == proposed_sha1
    puts "\u2713.....#{File.basename(file)} - SHA1"
  else
    puts "fail.....#{File.basename(file)} - SHA1"
  end
end

puts 'Verifying signatures...'
Dir.glob(File.join(tag, 'dist', '*.gz')) do |file|
  out = `gpg --verify #{file}.asc 2>&1`
  if /Good signature/.match(out)
    puts "\u2713.....#{File.basename(file)} - Signature"
  else
    puts "fail.....#{File.basename(file)} - Signature"
  end
end

puts 'Verifying src build...'
`git clone -q https://git-wip-us.apache.org/repos/asf/incubator-blur.git #{File.join(tag, 'src')} 2>&1`
`pushd #{File.join(tag, 'src')}; git checkout tags/#{tag} 2>&1; popd`
`pushd #{File.join(tag, 'src')}; mvn install -Dhadoop2 -DskipTests 2>&1; popd`
dist_src = `tar -tf #{File.join(tag,'dist')}/apache-blur-#{version}-incubating-src.tar.gz`
compiled_src = `tar -tf #{File.join(tag,'src','distribution','target')}/apache-blur-#{version}-incubating-src.tar.gz`

dist_src_array = dist_src.split("\n")
compiled_src_array = compiled_src.split("\n")

diff_array_1 = dist_src_array - compiled_src_array
diff_array_2 = compiled_src_array - dist_src_array

diff_array = diff_array_1 + diff_array_2

if dist_src == compiled_src
  puts "\u2713.....Source Build Check"
else
  puts "fail.....Source Build Check"
  diff_array.each{|entry| puts entry}
end

puts 'Verifying license file...'
`tar -xvzf #{File.join(tag,'dist')}/apache-blur-#{version}-incubating-src.tar.gz -C #{File.join(tag, 'dist')} 2>&1`
missing_files = []
File.open("#{File.join(tag,'dist')}/apache-blur-#{version}-incubating-src/LICENSE", "r") do |infile|
  while (line = infile.gets)
    if line.start_with?('./')
      missing_files << line unless File.exist?(File.join(tag, 'dist', "apache-blur-#{version}-incubating-src", line.chomp))
    end
  end
end

if missing_files.empty?
  puts "\u2713.....All License File Libs exist"
else
  puts "fail.....License File Libs missing"
  missing_files.each{|entry| puts entry}
end

lib_paths = ['blur-console/src/main/webapp/libs', 'blur-console/src/main/webapp/js/utils', 'blur-gui/src/main/webapp/js']

missing_licenses = []
license_content = File.open("#{File.join(tag,'dist')}/apache-blur-#{version}-incubating-src/LICENSE").read
lib_paths.each do |path|
  Dir.glob(File.join(tag,'dist', "apache-blur-#{version}-incubating-src", path, '*.js')) do |file|
    path_file = File.join(path, File.basename(file))
    missing_licenses << path_file unless license_content.match(/#{path_file}/)
  end
end

if missing_licenses.empty?
  puts "\u2713.....All Libs in License File"
else
  puts "fail.....Libs missing from License File"
  missing_licenses.each{|entry| puts entry}
end

puts 'Veriying copyright in NOTICE...'
copyright_line = File.readlines(File.join(tag, 'dist', "apache-blur-#{version}-incubating-src", 'NOTICE'))[1]
puts copyright_line
if copyright_line.include?(DateTime.now.year.to_s)
  puts "\u2713.....Current year is in NOTICE"
else
  puts 'fail.....Current year is missing from NOTICE'
end

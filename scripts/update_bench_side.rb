#!/usr/bin/ruby
require 'fileutils' 

goblint = File.join(Dir.getwd,"goblint")
fail "Please run script from goblint dir!" unless File.exist?(goblint)
revshort = `git describe --tags --long`[/.*-\d+/]
$vrsn = `#{goblint} --version`
$testresults = File.expand_path("tests/bench_result") + "/"
bench = "../bench/"

class Project
  attr_reader :id, :name, :group, :path, :params
  attr_accessor :url
  def initialize(id, name, size, url, group, path, params)
    @id       = id
    @name     = name
    @size     = size
    @url      = url
    @group    = group
    @path     = path
    @params   = params
  end
  def to_html
    "<td>#{@id}</td><td><a href=\"#{@url}\">#{@name}</a></td>\n" + "<td>#{@size}</td>\n"
  end
  def to_s
    "#{@name}"
  end
end
$projects = []

$header = <<END
<head>
  <title>#{revshort} (#{`uname -n`.chomp})</title>
  <style type="text/css">
    A:link {text-decoration: none}
    A:visited {text-decoration: none}
    A:active {text-decoration: none}
    A:hover {text-decoration: underline}
</style>
</head>
END
$theresultfile = File.join($testresults, "index.html")
def print_res (i)
  File.open($theresultfile, "w") do |f|
    f.puts "<html>"
    f.puts $header
    f.puts "<body>"
    f.puts "<p>Benchmarking in progress: #{i}/#{$projects.length} <progress value=\"#{i}\" max=\"#{$projects.length}\" /></p>" unless i.nil?
    f.puts "<table border=2 cellpadding=4 style=\"font-size: 90%\">"
    gname = ""
    $projects.each do |p|
      if p.group != gname then
        gname = p.group
        f.puts "<tr><th colspan=#{4+$analyses.size}>#{gname}</th></tr>"
        if $print_desc then
          f.puts "<tr><th>#</th><th>Name</th><th>Description</th><th>Size</th>"
        else
          f.puts "<tr><th>#</th><th>Name</th><th>Size</th>"
        end
        $analyses.each do |a| 
          aname = a[0]
          f.puts "<th>#{aname}</th>"
        end
  #       f.puts "<th>Compared to Trier</th>"
      end
      f.puts "<tr>"
      f.puts p.to_html
      $analyses.each do |a|
        aname = a[0]
        outfile = File.basename(p.path,".c") + ".#{aname}.txt"
        if File.exists?($testresults + outfile) then
          badlines = `grep -E "Access to unknown address|with lockset" #{$testresults + outfile} | sed "s/.*(\\(.*\\))/\\1/g" | sort -u | wc -l`.split[0]
          dur = "?"            
          File.open($testresults + outfile, "r") do |g|
            lines = g.readlines
            dur = lines.grep(/^Duration: (.*) s/) { |x| $1 }
          end
          thenumbers =  "<font color=\"red\">#{badlines}</font>"
          f.puts "<td><a href = #{outfile}>#{"%.2f" % dur} s</a> (#{thenumbers})</td>"
        else
          f.puts "<td>N/A</a></td>"
        end
      end
      gb_file = $testresults + File.basename(p.path,".c") + ".mutex.txt"
  #     tr_file = trier_res + p.name + "/warnings.txt"
  #     if FileTest.exists? tr_file then
  #       comp_file = File.basename(p.path,".c") + ".comparison.txt" 
  #       `/home/vesal/kool/magister/goblint/scripts/mit_Trier_vergleichen.rb #{gb_file} #{tr_file} > #{$testresults + comp_file}`
  #       summary = File.new($testresults + comp_file).readlines[-1]
  #       f.puts "<td><a href=\"#{comp_file}\">#{summary}</td>"
  #     else
  #       f.puts "<td>No Trier!</td>"
  #     end
      f.puts "</tr>"
      f.puts "</tr>"
    end
    f.puts "</table>"
    f.print "<p style=\"font-size: 80%; white-space: pre-line\">"
    f.puts "Last updated: #{Time.now.strftime("%Y-%m-%d %H:%M:%S %z")}"
    f.puts "#{$vrsn}"
    f.puts "</p>"
    f.puts "</body>"
    f.puts "</html>"
  end
end

#Command line parameters

timeout = 900
timeout = ARGV[0].to_i unless ARGV[0].nil?
only = ARGV[1] unless ARGV[1].nil?
if only == "group" then
  only = nil
  thegroup = ARGV[2]
end

#processing the input file

skipgrp = []
file = "tests/benches/side_effect.txt"

$analyses = []
File.open(file, "r") do |f|
  id = 0
  while line = f.gets
    next if line =~ /^\s*$/ 
    if line =~ /Group: (.*)/
      gname = $1.chomp
      skipgrp << gname if line =~ /SKIP/
    elsif line =~ /(.*): ?(.*)/
      $analyses << [$1,$2]
    else
      name = line.chomp
      url = f.gets.chomp
      path = File.expand_path(f.gets.chomp, bench)
      size = `wc -l #{path}`.split[0] + " lines"
      params = f.gets.chomp
      params = "" if params == "-"
      id += 1
      p = Project.new(id,name,size,url,gname,path,params)
      $projects << p
    end
  end
end

#analysing the files
gname = ""
maxlen = $analyses.map { |x| x[0].length }.max + 1
$projects.each do |p|
  next if skipgrp.member? p.group
  next unless thegroup.nil? or p.group == thegroup
  next unless only.nil? or p.name == only 
  if p.group != gname then
    gname = p.group
    puts gname
  end
  filepath = p.path
  dirname = File.dirname(filepath)
  filename = File.basename(filepath)
  Dir.chdir(dirname)
  outfiles = $testresults + File.basename(filename,".c") + ".*"
  `rm -f #{outfiles}`
  if p.url == "generate!" then
    `code2html -l c -n #{p.path} #{$testresults + p.name}.html`
    p.url = p.name + ".html"
  end
  puts "Analysing #{filename} (#{p.id}/#{$projects.length})"
  $analyses.each do |a|
    aname = a[0]
    aparam = a[1]
    print "  #{format("%*s", -maxlen, aname)}"
    STDOUT.flush
    outfile = $testresults + File.basename(filename,".c") + ".#{aname}.txt"
    starttime = Time.now
    cmd = "timeout #{timeout} #{goblint} #{aparam} #{filename} #{p.params} --uncalled --allglobs --debug --stats --cilout /dev/null 1>#{outfile} 2>&1"
    system(cmd)
    status = $?.exitstatus
    endtime   = Time.now
    File.open(outfile, "a") do |f|
      f.puts "\n=== APPENDED BY BENCHMARKING SCRIPT ==="
      f.puts "Analysis began: #{starttime}"
      f.puts "Analysis ended: #{endtime}"
      f.puts "Duration: #{format("%.02f", endtime-starttime)} s"
      f.puts "Goblint params: #{cmd}"
      f.puts $vrsn
    end
    if status != 0 then
      if status == 124 then
        puts "-- Timeout!"
        `echo "TIMEOUT                    #{timeout} s" >> #{outfile}`
      else
        puts "-- Failed!"
        `echo "EXITCODE                   #{status}" >> #{outfile}`
      end
      print_res p.id
      break
    else
      puts "-- Done!"
    end
    #print_res p.id
  end
  `rm goblint.json`
end
print_res nil
puts ("Results: " + $theresultfile)
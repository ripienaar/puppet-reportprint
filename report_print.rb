#!/usr/bin/env ruby

require 'puppet'
require 'pp'
require 'optparse'

class ::Numeric
  def bytes_to_human
    # Prevent nonsense values being returned for fractions
    if self >= 1
      units = ['B', 'KB', 'MB' ,'GB' ,'TB']
      e = (Math.log(self)/Math.log(1024)).floor
      # Cap at TB
      e = 4 if e > 4
      s = "%.2f " % (to_f / 1024**e)
      s.sub(/\.?0*$/, units[e])
    else
      "0 B"
    end
  end
end

def load_report(path)
  YAML.load_file(path)
end

def report_resources(report)
  report.resource_statuses
end

def resource_with_evaluation_time(report)
  report_resources(report).select{|r_name, r| !r.evaluation_time.nil? }
end

def resource_by_eval_time(report)
  report_resources(report).reject{|r_name, r| r.evaluation_time.nil? }.sort_by{|r_name, r| r.evaluation_time rescue 0}
end

def resources_of_type(report, type)
  report_resources(report).select{|r_name, r| r.resource_type == type}
end

def color(code, msg, reset=false)
  colors = {
    :red       => "[31m",
    :green     => "[32m",
    :yellow    => "[33m",
    :cyan      => "[36m",
    :bold      => "[1m",
    :underline => "[4m",
    :reset     => "[0m",
  }

  colors.merge!(
    :changed   => colors[:yellow],
    :unchanged => colors[:green],
    :failed    => colors[:red],
  )

  return "%s%s%s%s" % [colors.fetch(code, ""), msg, colors[:reset], reset ? colors.fetch(reset, "") : ""] if @options[:color]

  msg
end

def print_report_summary(report)
  puts color(:bold, "Report for %s in environment %s at %s" % [color(:underline, report.host, :bold), color(:underline, report.environment, :bold), color(:underline, report.time, :bold)])
  puts
  puts "             Report File: %s" % @options[:report]
  puts "             Report Kind: %s" % report.kind
  puts "          Puppet Version: %s" % report.puppet_version
  puts "           Report Format: %s" % report.report_format
  puts "   Configuration Version: %s" % report.configuration_version
  puts "                    UUID: %s" % report.transaction_uuid rescue nil
  puts "               Log Lines: %s %s" % [report.logs.size, @options[:logs] ? "" : "(show with --log)"]

  puts
end

def print_report_motd(report, motd_path)
  motd = []
  header = "# #{report.host} #"
  headline = "#" * header.size
  motd << headline << header << headline << ''

  motd << "Last puppet run happened at %s in environment %s." % [report.time, report.environment]

  motd << "The result of this puppet run was %s." % color(report.status.to_sym, report.status)

  if report.metrics.empty? or report.metrics["events"].nil?
    motd << 'No Report Metrics.'
  else
    motd << 'Events:'
    report.metrics["events"].values.each do |metric|
      i, m, v = metric
      motd.last << ' ' << [m, v].join(': ') << '.'
    end
  end

  motd << '' << ''

  File.write(motd_path, motd.join("\n"))
end

def print_report_metrics(report)
  puts color(:bold, "Report Metrics:")
  puts

  padding = report.metrics.map{|i, m| m.values}.flatten(1).map{|i, m, v| m.size}.sort[-1] + 6

  report.metrics.sort_by{|i, m| m.label}.each do |i, metric|
    puts "   %s:" % metric.label

    metric.values.sort_by{|j, m, v| v}.reverse.each do |j, m, v|
      puts "%#{padding}s: %s" % [m, v]
    end

    puts
  end

  puts
end

def print_summary_by_type(report)
  summary = {}

  report_resources(report).each do |resource|
    if resource[0] =~ /^(.+?)\[/
      name = $1

      summary[name] ||= 0
      summary[name] += 1
    else
      STDERR.puts "ERROR: Cannot parse type %s" % resource[0]
    end
  end

  puts color(:bold, "Resources by resource type:")
  puts

  summary.sort_by{|k, v| v}.reverse.each do |type, count|
    puts "   %4d %s" % [count, type]
  end

  puts
end

def print_slow_resources(report, number=20)
  if report.report_format < 4
    puts color(:red, "   Cannot print slow resources for report versions %d" % report.report_format)
    puts
    return
  end

  resources = resource_by_eval_time(report)

  number = resources.size if resources.size < number

  puts color(:bold, "Slowest %d resources by evaluation time:" % number)
  puts

  resources[(0-number)..-1].reverse.each do |r_name, r|
    puts "   %7.2f %s" % [r.evaluation_time, r_name]
  end

  puts
end

def print_logs(report)
  puts color(:bold, "%d Log lines:" % report.logs.size)
  puts

  report.logs.each do |log|
    puts "   %s" % log.to_report
  end

  puts
end

def print_summary_by_containment_path(report, number=20)
  resources = resource_with_evaluation_time(report)

  containment = Hash.new(0)

  resources.each do |r_name, r|
    r.containment_path.each do |containment_path|
      #if containment_path !~ /\[/
        containment[containment_path] += r.evaluation_time
      #end
    end
  end

  number = containment.size if containment.size < number

  puts color(:bold, "%d most time consuming containment" % number)
  puts

  containment.sort_by{|c, s| s}[(0-number)..-1].reverse.each do |c_name, evaluation_time|
    puts "   %7.2f %s" % [evaluation_time, c_name]
  end

  puts
end

def print_files(report, number=20)
  resources = resources_of_type(report, "File")

  files = {}

  resources.each do |r_name, r|
    if r_name =~ /^File\[(.+)\]$/
      file = $1

      if File.exist?(file) && File.readable?(file) && File.file?(file) && !File.symlink?(file)
        files[file] = File.size?(file) || 0
      end
    end
  end

  number = files.size if files.size < number

  puts color(:bold, "%d largest managed files" % number) + " (only those with full path as resource name that are readable)"
  puts

  files.sort_by{|f, s| s}[(0-number)..-1].reverse.each do |f_name, size|
    puts "   %9s %s" % [size.bytes_to_human, f_name]
  end

  puts
end

def initialize_puppet
  require 'puppet/util/run_mode'
  Puppet.settings.preferred_run_mode = :agent
  Puppet.settings.initialize_global_settings([])
  Puppet.settings.initialize_app_defaults(Puppet::Settings.app_defaults_for_run_mode(Puppet.run_mode))
end

initialize_puppet

opt = OptionParser.new

@options = {
  :logs      => false,
  :motd      => false,
  :motd_path => '/etc/motd',
  :count     => 20,
  :report    => Puppet[:lastrunreport],
  :color     => STDOUT.tty?}

opt.on("--logs", "Show logs") do |val|
  @options[:logs] = val
end

opt.on("--motd", "Produce an output suitable for MOTD") do |val|
  @options[:motd] = val
end

opt.on("--motd-path [PATH]", "Path to the MOTD file to overwrite with the --motd option") do |val|
  @options[:motd_path] = val
end

opt.on("--count [RESOURCES]", Integer, "Number of resources to show evaluation times for") do |val|
  @options[:count] = val
end

opt.on("--report [REPORT]", "Path to the Puppet last run report") do |val|
  abort("Could not find report %s" % val) unless File.readable?(val)
  @options[:report] = val
end

opt.on("--[no-]color", "Colorize the report") do |val|
  @options[:color] = val
end

opt.parse!

report = load_report(@options[:report])

if @options[:motd]
  print_report_motd(report, @options[:motd_path])
else
  print_report_summary(report)
  print_report_metrics(report)
  print_summary_by_type(report)
  print_slow_resources(report, @options[:count])
  print_files(report, @options[:count])
  print_summary_by_containment_path(report, @options[:count])
  print_logs(report) if @options[:logs]
end

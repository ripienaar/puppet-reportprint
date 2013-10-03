#!/usr/bin/ruby

require 'puppet'
require 'pp'
require 'optparse'

def load_report(path)
  YAML.load_file(path)
end

def report_resources(report)
  report.resource_statuses
end

def resource_by_eval_time(report)
  report_resources(report).reject{|r_name, r| r.evaluation_time.nil? }.sort_by{|r_name, r| r.evaluation_time rescue 0}
end

def print_report_summary(report)
  puts "Report for %s in environment %s at %s" % [report.host, report.environment, report.time]
  puts
  puts "             Report File: %s" % @options[:report]
  puts "             Report Kind: %s" % report.kind
  puts "           Report Format: %s" % report.report_format
  puts "   Configuration Version: %s" % report.configuration_version
  puts "                    UUID: %s" % report.transaction_uuid rescue nil
  puts "          Puppet Version: %s" % report.puppet_version
  puts "               Log Lines: %s %s" % [report.logs.size, @options[:logs] ? "" : "(show with --log)"]

  puts
end

def print_report_metrics(report)
  puts "Report Metrics:"
  puts

  padding = report.metrics.map{|i, m| m.values}.flatten(1).map{|i, m, v| m.size}.sort[-1] + 6

  report.metrics.sort_by{|i, m| m.label}.each do |i, metric|
    puts "   %s:" % metric.label

    metric.values.sort_by{|i, m, v| v}.reverse.each do |i, m, v|
      puts "%#{padding}s: %s" % [m, v]
    end

    puts
  end

  puts
end

def summarize_by_type(report)
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

  puts "Resources by resource type:"
  puts

  padding = summary.keys.map{|r| r.size}.sort[-1] + 1

  summary.sort_by{|k, v| v}.reverse.each do |type, count|
    puts "   %#{padding}s: %s" % [type, count]
  end

  puts
end

def print_slow_resources(report, number=20)
  puts "Slowest %d resources by evaluation time:" % number
  puts

  if report.report_format < 4
    puts "   Cannot print slow resources for report versions %d" % report.report_format
    puts
    return
  end

  resources = resource_by_eval_time(report)

  resources[(0-number)..-1].reverse.each do |r_name, r|
    puts "   %7.2f %s" % [r.evaluation_time, r_name]
  end

  puts
end

def print_logs(report)
  puts "%d Log lines:" % report.logs.size
  puts

  report.logs.each do |log|
    puts "   %s" % log.to_report
  end
end

def initialize_puppet
  require 'puppet/util/run_mode'
  Puppet.settings.preferred_run_mode = :agent
  Puppet.settings.initialize_global_settings([])
  Puppet.settings.initialize_app_defaults(Puppet::Settings.app_defaults_for_run_mode(Puppet.run_mode))
end

initialize_puppet

opt = OptionParser.new

@options = {:logs => false, :count => 20, :report => Puppet[:lastrunreport]}

opt.on("--logs", "Show logs") do |val|
  @options[:logs] = val
end

opt.on("--count [RESOURCES]", Integer, "Number of resources to show evaluation times for") do |val|
  @options[:count] = val
end

opt.on("--report [REPORT]", "Path to the Puppet last run report") do |val|
  abort("Could not find report %s" % val) unless File.readable?(val)
  @options[:report] = val
end

opt.parse!

report = load_report(@options[:report])

print_report_summary(report)
print_report_metrics(report)
summarize_by_type(report)
print_slow_resources(report, @options[:count])
print_logs(report) if @options[:logs]

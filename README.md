What?
=====

A simple CLI viewer for Puppet Reports

Why?
----

Because fuck web shit.

The main question I have is why is Puppet so slow to apply a specific
catalog.  This report printer will show you standard issue report metrics
and such but it will also show you the resources in the report sorted
by slowest evaluation time as well as the largest files being managed.

Evaluation time is how long Puppet took at run time to apply a specific
resource.

A Package resource might go out to the internet to fetch the package and
so you'll have long evaluation times.  Services takes long to restart
and so forth.

This is the information you'll find using the _--evaltrace_ option to
Puppet which have recently been included in Puppet reports.

If you run it as root it should magically figure out where to find you
most recent report - usually in */var/lib/puppet/state/last_run_report.yaml*
but you can pass in a path using --report

An example report is included in SAMPLE.txt  Tested against Puppet 3.3.0
it might have bugs against older versions.

Puppet server support
---------------------

This script can also print Puppet Server reports stored with `reports = store`.

Supported Puppet Server commands:

`report_print.rb --nodelist`: List nodes and their last report status

`report_print.rb --node foobar.example.com`: Prints last report for
node foobar.example.com

`report_print.rb --node foobar.example.com --history`: Prints reports ID and
summary for node foobar.example.com

`report_print.rb --node foobar.example.com --report-id 204212041337`: Prints
report 204212041337 of node foobar.example.com

Future?
-------

 * Parse the Puppet compiler metrics that was recently introduced to figure
   out why compiling is slow
 * Retrieve a report from PuppetDB based on some criteria

Who?
----

R.I.Pienaar / rip@devco.net / @ripienaar / http://devco.net

#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long;

use Bio::KBase::PROM::Client;
use Bio::KBase::PROM::Util qw(getPromURL);

my $DESCRIPTION =
"
NAME
      prom-url -- update/view url of the prom service endpoint

SYNOPSIS
      prom-url [OPTIONS] [NEW_URL]

DESCRIPTION
      Display or set the URL endpoint for the prom service.  If run with no
      arguments or options, then the current URL is displayed. If run with
      a single argument, the current URL will be switched to the specified
      URL.  If the specified URL is named default, then the URL is reset to
      the default production URL
      
      -h, --help         display this help message, ignore all arguments

EXAMPLES
      Display the current URL:
      > prom-url
      http://kbase.us/services/PROM
      
      Reset to the default URL:
      > prom-url default
      changed to: http://kbase.us/services/PROM
      
      Use a new URL:
      > prom-url http://localhost:8080/PROM
      changed to: http://localhost:8080/PROM
      
AUTHORS
      Michael Sneddon (mwsneddon\@lbl.gov)
      
";

my $help = '';
my $default = '';
my $opt = GetOptions (
        "help" => \$help,
        );

if($help) {
     print $DESCRIPTION;
     exit 0;
}

my $n_args = $#ARGV+1;
if($n_args==0) {
     print getPromURL()."\n";
     exit 0;
} elsif($n_args==1) {
     my $url = getPromURL($ARGV[0]);
     print "changed to: $url\n";
     exit 0;
}

print "Invalid number of arguments.  Run with --help for usage.\n";
exit 1;


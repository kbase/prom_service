#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long;


#use Bio::KBase::workspaceService::Helpers qw(auth get_ws_client workspace workspaceURL parseObjectMeta parseWorkspaceMeta printObjectMeta);
#Defining globals describing behavior

my $DESCRIPTION =
"
NAME
      prom-url -- update/view url of the prom service endpoint

SYNOPSIS
      prom-url [OPTION] [NEW_URL]

DESCRIPTION
      Display or set the URL endpoint for the prom service.  If run with no
      arguments or options, then the current URL is displayed. If run with
      a single argument, the current URL will be switched to the specified
      URL.
      
      -h, --help         diplay this help message, ignore all arguments
      -d, --default      reset the URL to the default URL, ignore all arguments

EXAMPLES
      Display the current URL:
      > prom-url
      http://kbase.us/services/PROM
      
      Reset to the default URL:
      > prom-url -d
      
      Use a new URL:
      > prom-url http://localhost:8080/PROM
      
AUTHORS
      Michael Sneddon (mwsneddon\@lbl.gov)
      
";

my $help = '';
my $default = '';
my $opt = GetOptions (
                "help" => \$help,
                "default" => \$default);

if($help) {
        print $DESCRIPTION;
        exit 0;
}
if($default) {
        print "changed to: http://kbase.us/services/PROM\n";
        exit 0;
}

my $URL = "http://blah";
my $n_args = $#ARGV+1;
if($n_args==0) {
        print $URL."\n";
        exit 0;
} elsif($n_args==1) {
        print "changed to: $ARGV[0]\n";
        exit 0;
}

print "Invalid number of arguments.  Run with --help for usage.\n";
exit 1;


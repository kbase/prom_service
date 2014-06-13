#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long;

use Bio::KBase::PROM::Client;
use Bio::KBase::PROM::Util qw(get_prom_client get_auth_token);
use Bio::KBase::workspace::ScriptHelpers qw(workspace);


my $DESCRIPTION =
"
NAME
      prom-load-regulatory-network -- load a regulatory network to a workspace

SYNOPSIS
      prom-load-regulatory-network [OPTIONS]

DESCRIPTION
      Load a regulatory network to a workspace from the CDS.  In the future,
      this method will also support loading data from a file. See the API
      specification of the Prom service for more details on the format of the
      regulatory network.  This method prints out the ID of the regulatory
      network object that is created, or 'FAILURE' if the data could not be
      loaded, followed by an error message.  The error code is zero if successful,
      one otherwise.  Use the regulation service to determine how much expression
      data for the given genome exists.
      
      -g [GENOME_ID], --genome [GENOME_ID]
                        indicate the genome id of the regulatory network
                        to load into the current workspace
        
      -w [WORKSPACE_ID], --workspace [WORKSPACE_ID]
                        specify the workspace to use.  If left blank, the default
                        workspace that is configured by the workspace service
                        scripts is used
                        
      -v, --verbose
                        in addition to the workspace regulatory network ID, which
                        will be on the last line, status messages are displayed; more
                        verbose errors are also displayed, which may be useful for
                        debugging
                        
      -h, --help
                        display this help message, ignore all arguments
                        
                        

EXAMPLES
      Load a regulatory network for genome kb|g.20848:
      > prom-load-regulatory-network -g 'kb|g.20848'
      AF74A066-6B03-11E2-8DAE-9375BC200E61

SEE ALSO
      prom-change-regulatory-network-namespace
      
AUTHORS
      Michael Sneddon (mwsneddon\@lbl.gov)
      
";

my $help = '';
my $verbose = '';
my $genomeId = '';
my $ws = workspace(); # defaults to the workspace configured by the workspace service
my $opt = GetOptions (
        "help" => \$help,
        "verbose" => \$verbose,
        "genome=s" => \$genomeId,
        "workspace=s" => \$ws
        );

if($help) {
     print $DESCRIPTION;
     exit 0;
}

my $n_args = $#ARGV+1;
if($n_args==0) {
    if($genomeId) {
        #create client
        my $prom;
        eval{
            $prom = get_prom_client();
        };
        if(!$prom) {
            print "FAILURE - unable to create prom service client.  Is you PROM URL correct? see prom-url.\n";
            exit 1;
        }
        #grab auth info
        my $token = get_auth_token();
        #make the call
        my $status; my $regulatory_network_id;
        if($verbose) {
          ($status,$regulatory_network_id) =
             $prom->get_regulatory_network_by_genome($genomeId,$ws, $token);
        } else {
          eval {
            ($status,$regulatory_network_id) =
               $prom->get_regulatory_network_by_genome($genomeId,$ws, $token);
          };
          if(!$status) {
              print "FAILURE - unknown internal server error. Run with --help for usage.\n";
              exit 1;
          }
        }
        if($verbose) { print $status."\n"; }
        if($regulatory_network_id ne '') {
            print $regulatory_network_id."\n";
            exit 0;
        } else {
            print $status."\n";
            exit 1;
        }
    } else {
        print "FAILURE - no genome specified.  Run with --help for usage.\n";
        exit 1;
    }
}

print "Bad options / Invalid number of arguments.  Run with --help for usage.\n";
exit 1;


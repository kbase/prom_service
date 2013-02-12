#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long;

use Bio::KBase::PROM::Client;
use Bio::KBase::PROM::Util qw(get_prom_client get_auth_token);
use Bio::KBase::workspaceService::Helpers qw(workspace);


my $DESCRIPTION =
"
NAME
      prom-load-expression-data -- load expression data to a workspace

SYNOPSIS
      prom-load-expression-data [OPTIONS]

DESCRIPTION
      Load gene expression data to a workspace from the CDS.  In the future,
      this method will also support loading data from a file.  Data is saved
      as a set of on/off calls.  See the API specification of the Prom service
      for more details on the format of the expression data.  This method prints
      out the ID of the expression data collection that is created, or 'FAILURE'
      if the data could not be loaded, followed by an error message.  The error
      code is zero if successful, one otherwise. Note that depending on the
      amount of data available in the CDS, this method may take 5 or more minutes
      to complete.  Use the CDM API to determine how much expression data for
      the given genome exists.
      
      -g [GENOME_ID], --genome [GENOME_ID]
                        indicate the genome id of the CDS expression data
                        to load into the current workspace
        
      -w [WORKSPACE_ID], --workspace [WORKSPACE_ID]
                        specify the workspace to use.  If left blank, the default
                        workspace that is configured by the workspace service
                        scripts is used
                        
      -v, --verbose
                        in addition to the expression data collection ID, which
                        will be on the last line, status messages are displayed; more
                        verbose errors are also displayed, which may be useful for
                        debugging
                        
      -h, --help
                        diplay this help message, ignore all arguments
                        
                        

EXAMPLES
      Load expression data for E.coli genome kb|g.0:
      > prom-load-expression-data -g 'kb|g.0'
      E9C193DC-6B03-11E2-8DAE-9375BC200E61
      
      
AUTHORS
      Michael Sneddon (mwsneddon\@lbl.gov)
      
";

my $help = '';
my $verbose = '';
my $genomeId = '';
my $ws = workspace();
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
        my $status; my $expression_collection_id;
        if($verbose) {
          ($status,$expression_collection_id) =
             $prom->get_expression_data_by_genome($genomeId,$ws, $token);
        } else {
          eval {
            ($status,$expression_collection_id) =
               $prom->get_expression_data_by_genome($genomeId,$ws, $token);
          };
          if(!$status) {
              print "FAILURE - unknown internal server error. Run with --help for usage.\n";
              exit 1;
          }
        }
        if($verbose) { print $status."\n"; }
        if($expression_collection_id ne '') {
            print $expression_collection_id."\n";
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


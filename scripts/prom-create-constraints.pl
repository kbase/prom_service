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
      prom-create-constraints -- create fba constraints from data

SYNOPSIS
      prom-create-constraints [OPTIONS]

DESCRIPTION
      With a genome object in the workspace, gene expression data in the
      same namespace as the genome, and a regulatory network in the same
      namespace as a genome, you can create a set of FBA model constraints
      that can be used to predict transcription factor knockouts using the
      PROM method (see Chandrasekarana and Price, 2010 PNAS).  This method
      will return the ID of the new PROM model constraints object if
      successful, or an error message if something failed.  This method
      will exit with zero if the method was successful, or one if something
      failed.  Run with the verbose option to get a log and status message
      of the steps involved in the constraints construction.
      
      -g [GENOME_ID], --genome [GENOME_ID]
                        indicate the genome object id of a genome in the
                        workspace to link the constraints to; a genome object
                        can be created with the kbfba-loadgenome script.

      -e [EXP_ID], --expression-data [EXP_ID]
                        indicate the id of the expression data collection with
                        which to use

      -r [REG_NET_ID], --regulatory-network [REG_NET_ID]
                        indicate the id of the regulatory network with which
                        to use
        
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
      Create a PROM model constraints object:
      > prom-create-constraints -g 'kb|g.20848'

SEE ALSO
      prom-load-expression-data
      prom-load-regulatory-network
      kbfba-loadgenome
      
AUTHORS
      Michael Sneddon (mwsneddon\@lbl.gov)
      Matt DeJongh (dejongh\@hope.edu)
      Shinnosuke Kondo (shinnosuke.kondo\@hope.edu)
      Christopher Henry (chenry\@mcs.anl.gov)
      with help from Sriram Chandrasekaran
";

my $help = '';
my $verbose = '';
my $genomeId = '';
my $expressionId = '';
my $regNetworkId = '';
my $ws = workspace(); # defaults to the workspace configured by the workspace service
my $opt = GetOptions (
        "help" => \$help,
        "verbose" => \$verbose,
        "genome=s" => \$genomeId,
        "expression-data=s" => \$expressionId,
        "regulatory-network=s" => \$regNetworkId,
        "workspace=s" => \$ws
        );

if($help) {
     print $DESCRIPTION;
     exit 0;
}

my $n_args = $#ARGV+1;
if($n_args==0) {
    if($genomeId) {
        if($expressionId) {
            if($regNetworkId) {
                #create client
                my $prom;
                eval{ $prom = get_prom_client(); };
                if(!$prom) {
                    print "FAILURE - unable to create prom service client.  Is you PROM URL correct? see prom-url.\n";
                    exit 1;
                }
                #grab auth info
                my $token = get_auth_token();
                #make the call
                my $status; my $prom_id;
                my $create_prom_constraints_parameters = {
                    genome_object_id => $genomeId,
                    expression_data_collection_id => $expressionId,
                    regulatory_network_id => $regNetworkId,
                    workspace_name => $ws,
                    token =>  $token
                };
                if($verbose) {
                    ($status, $prom_id) = $prom->create_prom_constraints($create_prom_constraints_parameters);
                } else {
                    eval {
                          ($status, $prom_id) = $prom->create_prom_constraints($create_prom_constraints_parameters);
                    };
                    if(!$status) {
                         print "FAILURE - unknown internal server error. Run with --help for usage.\n";
                         print "This error is often caused if you provided an ID of an expression data or regulatory network\n";
                         print "data object which is not of the correct type.  Check the ids you provided.\n";
                         exit 1;
                    }
                }
        
                if($verbose) { print $status."\n"; }
                if($prom_id ne '') {
                    print $prom_id."\n";
                    exit 0;
                } else {
                    print $status."\n";
                    exit 1;
                }
            } else {
                print "FAILURE - no expression data collection specified.  Run with --help for usage.\n";
                exit 1;
            }
        } else {
            print "FAILURE - no expression data collection specified.  Run with --help for usage.\n";
            exit 1;
        }
    } else {
        print "FAILURE - no genome specified.  Run with --help for usage.\n";
        exit 1;
    }
}

print "Bad options / Invalid number of arguments.  Run with --help for usage.\n";
exit 1;


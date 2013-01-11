use strict;
use warnings;

use Data::Dumper;
use Test::More;

# MAKE SURE WE LOCALLY HAVE JSON RPC LIBS INSTALLED
use Bio::KBase::workspaceService::Client;
use Bio::KBase::AuthToken;


# AUTH INFORMATION
my $user_id='kbasepromuser1';
my $password='open4me!';
my $workspace_name="workspace_1";
my $token = Bio::KBase::AuthToken->new(user_id => $user_id, password => $password);

#boot up a workspace client
my $workspace_url = 'http://bio-data-1.mcs.anl.gov/services/fba_gapfill';
my $ws = Bio::KBase::workspaceService::Client->new($workspace_url);

# view what is in the workspace
my $get_workspacemeta_params = {
  workspace=>$workspace_name,
  auth=>$token->token,
};
my $workspace_meta = $ws->get_workspacemeta($get_workspacemeta_params);
print 'Workspace Meta Data: \n'.Dumper($workspace_meta)."\n";

# try to get a boolean gene expression data in the workspace
my $expression_collection_id = 'E19C6662-5B7E-11E2-A52E-A3E9BDAD6664';
my $get_object_params = {
    id => $expression_collection_id,
    type => "Unspecified",
    workspace => $workspace_name,
    auth => $token->token,
};
my $object = $ws->get_object($get_object_params);
print 'Collection: '.Dumper($object)."\n";

# try to get regulatory network from the workspace
#my $reg_network_id = "CFAC8EDE-59EC-11E2-A47A-6BBB7CBB0AD3"; #reg network for 20848
my $reg_network_id = "129A7B6A-5B8D-11E2-B9FB-82EFBDAD6664"; #dummy network
$get_object_params = {
    id => $reg_network_id,
    type => "Unspecified",
    workspace => $workspace_name,
    auth => $token->token,
};
$object = $ws->get_object($get_object_params);
print 'Collection: '.Dumper($object)."\n";



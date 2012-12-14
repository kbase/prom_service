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
my $workspace_url = 'http://140.221.92.231/services/workspaceService/';
my $ws = Bio::KBase::workspaceService::Client->new($workspace_url);

# view what is in the workspace
my $get_workspacemeta_params = {
  workspace=>$workspace_name,
  auth=>$token->token,
};
my $workspace_meta = $ws->get_workspacemeta($get_workspacemeta_params);
print 'Workspace Meta Data: \n'.Dumper($workspace_meta)."\n";

# try to get a boolean gene expression data in the workspace
my $expression_collection_id = '58FB832C-455F-11E2-917E-B6D34D1A8A4B';
my $get_object_params = {
    id => $expression_collection_id,
    type => "Unspecified",
    workspace => $workspace_name,
    auth => $token->token,
};
my $object = $ws->get_object($get_object_params);
print 'Collection: '.Dumper($object)."\n";







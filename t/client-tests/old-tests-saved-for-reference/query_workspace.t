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
#my $workspace_url = 'http://bio-data-1.mcs.anl.gov/services/fba_gapfill';
my $workspace_url = 'http://localhost:7058';
my $ws = Bio::KBase::workspaceService::Client->new($workspace_url);
my $object;

# view what is in the workspace
my $get_workspacemeta_params = {
  workspace=>$workspace_name,
  auth=>$token->token,
};
#my $workspace_meta = $ws->get_workspacemeta($get_workspacemeta_params);
#print 'Workspace Meta Data: \n'.Dumper($workspace_meta)."\n";

# try to get a boolean gene expression data in the workspace
my $expression_collection_id = 'E19C6662-5B7E-11E2-A52E-A3E9BDAD6664';
my $get_object_params = {
    id => $expression_collection_id,
    type => "Unspecified",
    workspace => $workspace_name,
    auth => $token->token,
};
$object = $ws->get_object($get_object_params);
print 'Collection: '.Dumper($object)."\n";

# try to get regulatory network from the workspace
#my $reg_network_id = "CFAC8EDE-59EC-11E2-A47A-6BBB7CBB0AD3"; #reg network for 20848
#my $reg_network_id = "129A7B6A-5B8D-11E2-B9FB-82EFBDAD6664"; #dummy network
my $reg_network_id = "DE633B86-5C34-11E2-A3A3-93838B8565CF"; #network mapped to g.372, same as expression data
$get_object_params = {
    id => $reg_network_id,
    type => "Unspecified",
    workspace => $workspace_name,
    auth => $token->token,
};
#$object = $ws->get_object($get_object_params);
#print 'Collection: '.Dumper($object)."\n";


# try to get the prom_constraint object from the workspace
#my $prom_constraint_id = "82F0AE3A-5E9D-11E2-A794-ED78498F8F53"; #small test model
my $prom_constraint_id = "80714A94-5F64-11E2-B1E9-279A371F29C2"; #full model
$get_object_params = {
    id => $prom_constraint_id,
    type => "Unspecified",
    workspace => $workspace_name,
    auth => $token->token,
};
my $prom_constraints = $ws->get_object($get_object_params)->{data};
print 'Collection: '.Dumper($prom_constraints)."\n";

# create prom model

use lib "/home/msneddon/Desktop/ModelSEED_ENVIRONMENT/ModelSEED/lib";
use ModelSEED::MS::PROMModel;
my $pmodel = ModelSEED::MS::PROMModel->new(
           "annotation_uuid" => $prom_constraints->{annotation_uuid},
           "transcriptionFactorMaps" => $prom_constraints->{transcriptionFactorMaps},
           "id" => $prom_constraint_id
);

print Dumper($pmodel)."\n";
$ws->save_object({"id"=>"kb|g.372.pm.1", "type"=>"PROMModel", "data"=>$pmodel->serializeToDB(),     "auth" => $token->token, "replace"=>1, "workspace"=>"workspace_1"});

# = [
#          'kb|g.372',
#          'Genome',
#          '2013-01-15T18:54:54',
#          0,
#          1,
#          'kbasepromuser1',
#          'kbasepromuser1',
#          'workspace_1',
#          '0CE81EF0-5F45-11E2-9E50-E90B7082D269',
#          '7390e317cf0c0d61d8bb339710b293cb',
#          {}
#        ];

my $genome_id = "kb|g.372";
$get_object_params = {
    id => $genome_id,
    type => "Genome",
    workspace => $workspace_name,
    auth => $token->token,
};
#$object = $ws->get_object($get_object_params);
#print "Collection: \n".Dumper(\keys %{$object->{data}})."\n";

my $list_ws_obj_params = {
    type => "Annotation",
    workspace => $workspace_name,
    auth => $token->token,
    asHash => 0,
    showDeletedObject => 1
};
#$object = $ws->list_workspace_objects($list_ws_obj_params);
#print "Objects: \n".Dumper($object)."\n";
	
#          'kb|g.372.fbamdl.1',
#          'Model',
#          '2013-01-15T19:36:54',
#          0,
#          1,
#          'kbasepromuser1',
#          'kbasepromuser1',
#          'workspace_1',
#          'EAABD330-5F4A-11E2-885E-EA0B7082D269',
#          'e19a50154eb979aeb28ba0026f00037d',


my $annot_id = "kb|g.372.fbamdl.1.anno";
$get_object_params = {
    id => $annot_id,
    type => "Annotation",
    workspace => $workspace_name,
    auth => $token->token,
};
#$object = $ws->get_object($get_object_params);
#print "Annotation: \n".Dumper(\$object->{data}->{features})."\n";



